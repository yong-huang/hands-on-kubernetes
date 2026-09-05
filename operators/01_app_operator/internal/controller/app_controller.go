/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	appv1 "example.com/app-operator/api/v1"
)

// appFinalizer 保证 CR 删除时我们有机会清理"外部资源"，
// 否则 Kubernetes 会直接把对象删掉，外部资源成为孤儿
const appFinalizer = "app.example.com/finalizer"

// AppReconciler reconciles a App object
type AppReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=app.example.com,resources=apps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=app.example.com,resources=apps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=app.example.com,resources=apps/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

// Reconcile 把 App 的期望状态（spec）与集群实际状态收敛：
// 依次保证 ConfigMap / Deployment / Service 存在且与 spec 一致，
// 最后把观察结果写回 status（Available Condition）。
func (r *AppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("app", req.NamespacedName)

	// 1. 取期望状态：CR 可能已被删除
	var app appv1.App
	if err := r.Get(ctx, req.NamespacedName, &app); err != nil {
		if apierrors.IsNotFound(err) {
			logger.Info("App 已删除，无需调谐")
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}
	logger = logger.WithValues("generation", app.Generation, "image", app.Spec.Image)

	// 2. 删除中的对象：先执行外部资源清理，再移除 Finalizer 放行删除。
	//    这就是"两阶段删除"：k8s 只在 finalizer 清空后才真正删掉对象。
	if !app.DeletionTimestamp.IsZero() {
		if controllerutil.ContainsFinalizer(&app, appFinalizer) {
			logger.Info("② 清理外部资源（模拟慢速外部 API，5s）", "externalID", app.Status.ExternalID)
			// 真实场景：这里调云 API 删盘/删 DNS 记录/删托管数据库……
			// 外部清理往往很慢，期间对象会一直停在 Terminating——
			// 这正是 Finalizer 的价值：宁可慢，不可留孤儿资源
			time.Sleep(5 * time.Second)
			controllerutil.RemoveFinalizer(&app, appFinalizer)
			if err := r.Update(ctx, &app); err != nil {
				return ctrl.Result{}, err
			}
		}
		return ctrl.Result{}, nil
	}

	// 3. 新对象：补上 Finalizer（幂等），并模拟向外部系统注册资源
	if controllerutil.AddFinalizer(&app, appFinalizer) {
		logger.Info("① 添加 Finalizer")
		if err := r.Update(ctx, &app); err != nil {
			return ctrl.Result{}, err
		}
	}
	if app.Status.ExternalID == "" {
		// 模拟"外部系统"分配的资源 ID（真实场景：云盘 ID / 托管 DB 实例名）
		app.Status.ExternalID = fmt.Sprintf("ext-%.8s", string(app.UID))
	}

	// 4. 保证三个子资源存在且与 spec 一致（CreateOrPatch：没有就建，有差异就 patch）
	cm := r.desiredConfigMap(&app)
	if err := controllerutil.SetControllerReference(&app, cm, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	op, err := controllerutil.CreateOrPatch(ctx, r.Client, cm, func() error {
		cm.Data = app.Spec.ConfigData // 数据以 spec 为准
		return controllerutil.SetControllerReference(&app, cm, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reconcile ConfigMap: %w", err)
	}

	dep := r.desiredDeployment(&app)
	if err := controllerutil.SetControllerReference(&app, dep, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	op2, err := controllerutil.CreateOrPatch(ctx, r.Client, dep, func() error {
		dep.Spec = appDepSpec(&app) // spec 以 CR 为准（漂移会被拉回）
		return controllerutil.SetControllerReference(&app, dep, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reconcile Deployment: %w", err)
	}

	svc := r.desiredService(&app)
	if err := controllerutil.SetControllerReference(&app, svc, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	op3, err := controllerutil.CreateOrPatch(ctx, r.Client, svc, func() error {
		svc.Spec.Selector = appLabels(app.Name)
		svc.Spec.Ports = []corev1.ServicePort{{
			Name:       "http",
			Port:       80,
			TargetPort: intstr.FromInt32(80),
		}}
		return controllerutil.SetControllerReference(&app, svc, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reconcile Service: %w", err)
	}

	// 3. 读子资源实际状态，回写 status（status 子资源只归 controller 写）
	var depLive appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Namespace: app.Namespace, Name: app.Name}, &depLive); err != nil {
		return ctrl.Result{}, err
	}
	available := depLive.Status.ReadyReplicas > 0
	cond := metav1.Condition{
		Type:               "Available",
		Status:             metav1.ConditionFalse,
		Reason:             "WaitingForReadyReplicas",
		Message:            fmt.Sprintf("%d/%d 副本 Ready", depLive.Status.ReadyReplicas, *app.Spec.Replicas),
		ObservedGeneration: app.Generation,
		LastTransitionTime: metav1.Now(),
	}
	if available {
		cond.Status = metav1.ConditionTrue
		cond.Reason = "DeploymentReady"
	}
	changed := !meta.IsStatusConditionPresentAndEqual(app.Status.Conditions, cond.Type, cond.Status) ||
		app.Status.ObservedGeneration != app.Generation
	meta.SetStatusCondition(&app.Status.Conditions, cond)
	app.Status.ObservedGeneration = app.Generation
	if changed {
		if err := r.Status().Update(ctx, &app); err != nil {
			return ctrl.Result{}, err
		}
	}

	logger.Info("调谐完成",
		"configMap", string(op), "deployment", string(op2), "service", string(op3),
		"readyReplicas", depLive.Status.ReadyReplicas,
		"desired", *app.Spec.Replicas, "available", available,
		"externalID", app.Status.ExternalID)
	return ctrl.Result{}, nil
}

// appLabels 是所有子资源共用的标签，也是 Deployment/Service 相互认领的 selector
func appLabels(name string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       name,
		"app.kubernetes.io/managed-by": "app-operator",
	}
}

// desiredConfigMap: spec.configData → ConfigMap
func (r *AppReconciler) desiredConfigMap(app *appv1.App) *corev1.ConfigMap {
	data := map[string]string{}
	for k, v := range app.Spec.ConfigData {
		data[k] = v
	}
	return &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: app.Name, Namespace: app.Namespace, Labels: appLabels(app.Name)},
		Data:       data,
	}
}

// desiredDeployment: spec.image/replicas/env → Deployment（spec 构造复用 appDepSpec）
func (r *AppReconciler) desiredDeployment(app *appv1.App) *appsv1.Deployment {
	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: app.Name, Namespace: app.Namespace, Labels: appLabels(app.Name)},
		Spec:       appDepSpec(app),
	}
}

// appDepSpec 返回 Deployment 的 spec（创建与 CreateOrPatch 的 mutate 共用，
// 保证"声明什么就是什么"：mutate 每次都用 spec 覆盖，漂移会被拉回）
func appDepSpec(app *appv1.App) appsv1.DeploymentSpec {
	replicas := int32(1)
	if app.Spec.Replicas != nil {
		replicas = *app.Spec.Replicas
	}
	var envs []corev1.EnvVar
	for k, v := range app.Spec.Env {
		envs = append(envs, corev1.EnvVar{Name: k, Value: v})
	}
	return appsv1.DeploymentSpec{
		Replicas: &replicas,
		Selector: &metav1.LabelSelector{MatchLabels: appLabels(app.Name)},
		Template: corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: appLabels(app.Name)},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:  "app",
					Image: app.Spec.Image,
					Ports: []corev1.ContainerPort{{Name: "http", ContainerPort: 80}},
					Env:   envs,
					VolumeMounts: []corev1.VolumeMount{{
						Name:      "config",
						MountPath: "/etc/app",
						ReadOnly:  true,
					}},
				}},
				Volumes: []corev1.Volume{{
					Name: "config",
					VolumeSource: corev1.VolumeSource{
						ConfigMap: &corev1.ConfigMapVolumeSource{
							LocalObjectReference: corev1.LocalObjectReference{Name: app.Name},
						},
					},
				}},
			},
		},
	}
}

// desiredService: ClusterIP，selector 精确到本 App 的实例标签
func (r *AppReconciler) desiredService(app *appv1.App) *corev1.Service {
	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: app.Name, Namespace: app.Namespace, Labels: appLabels(app.Name)},
		Spec: corev1.ServiceSpec{
			Selector: appLabels(app.Name),
			Ports: []corev1.ServicePort{{
				Name:       "http",
				Port:       80,
				TargetPort: intstr.FromInt32(80),
			}},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
// Owns()：子资源（Deployment/ConfigMap/Service）变化时也触发本 Reconcile——
// 这是"有人手改子资源 → controller 拉回期望状态"的漂移自愈来源。
func (r *AppReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&appv1.App{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.ConfigMap{}).
		Owns(&corev1.Service{}).
		Named("app").
		Complete(r)
}
