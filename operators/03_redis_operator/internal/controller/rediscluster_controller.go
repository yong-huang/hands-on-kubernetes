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

	cachev1 "example.com/redis-operator/api/v1"
)

// RedisClusterReconciler reconciles a RedisCluster object
type RedisClusterReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=cache.example.com,resources=redisclusters,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cache.example.com,resources=redisclusters/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cache.example.com,resources=redisclusters/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

// labels 返回资源共带的标签集，role 区分主从
func labels(name, role string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       name,
		"app.kubernetes.io/managed-by": "redis-operator",
		"app.kubernetes.io/component":  role,
	}
}

// Reconcile 收敛主从拓扑：1 个 master Deployment + master Service +
// N 副本的 replicas StatefulSet。从库启动即 replicaof 主库，自动进入复制。
func (r *RedisClusterReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("redis", req.NamespacedName)

	var rc cachev1.RedisCluster
	if err := r.Get(ctx, req.NamespacedName, &rc); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}
	if rc.Spec.Replicas == nil {
		one := int32(1)
		rc.Spec.Replicas = &one
	}
	replicas := *rc.Spec.Replicas
	image := rc.Spec.Image
	if image == "" {
		image = "redis:7-alpine"
	}

	// ---- 1. master Deployment（单副本，role=master）----
	master := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: rc.Name + "-master", Namespace: rc.Namespace, Labels: labels(rc.Name, "master")},
		Spec: appsv1.DeploymentSpec{
			Replicas: &[]int32{1}[0],
			Selector: &metav1.LabelSelector{MatchLabels: labels(rc.Name, "master")},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels(rc.Name, "master")},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "redis",
						Image: image,
						Ports: []corev1.ContainerPort{{Name: "redis", ContainerPort: 6379}},
					}},
				},
			},
		},
	}
	if err := controllerutil.SetControllerReference(&rc, master, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	mOp, err := controllerutil.CreateOrPatch(ctx, r.Client, master, func() error {
		master.Spec.Template = corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: labels(rc.Name, "master")},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:  "redis",
					Image: image,
					Ports: []corev1.ContainerPort{{Name: "redis", ContainerPort: 6379}},
				}},
			},
		}
		return controllerutil.SetControllerReference(&rc, master, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("master: %w", err)
	}

	// ---- 2. master Service（从库与验证的复制源）----
	mSvc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: rc.Name + "-master", Namespace: rc.Namespace, Labels: labels(rc.Name, "master")},
		Spec: corev1.ServiceSpec{
			Selector: labels(rc.Name, "master"),
			Ports:    []corev1.ServicePort{{Name: "redis", Port: 6379, TargetPort: intstr.FromInt32(6379)}},
		},
	}
	sOp, err := controllerutil.CreateOrPatch(ctx, r.Client, mSvc, func() error {
		mSvc.Spec.Selector = labels(rc.Name, "master")
		return controllerutil.SetControllerReference(&rc, mSvc, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// ---- 3. replicas StatefulSet（从库，启动即 replicaof 主库）----
	replicasSTS := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: rc.Name + "-replicas", Namespace: rc.Namespace, Labels: labels(rc.Name, "replica")},
		Spec: appsv1.StatefulSetSpec{
			ServiceName: rc.Name + "-replicas",
			Replicas:    &replicas,
			Selector:    &metav1.LabelSelector{MatchLabels: labels(rc.Name, "replica")},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels(rc.Name, "replica")},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "redis",
						Image: image,
						Ports: []corev1.ContainerPort{{Name: "redis", ContainerPort: 6379}},
						Command: []string{
							"redis-server",
							"--replicaof", rc.Name + "-master." + rc.Namespace + ".svc.cluster.local", "6379",
							"--replica-read-only", "yes",
						},
					}},
				},
			},
		},
	}
	if err := controllerutil.SetControllerReference(&rc, replicasSTS, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	rOp, err := controllerutil.CreateOrPatch(ctx, r.Client, replicasSTS, func() error {
		replicasSTS.Spec.Replicas = &replicas
		replicasSTS.Spec.Template = corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: labels(rc.Name, "replica")},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:  "redis",
					Image: image,
					Ports: []corev1.ContainerPort{{Name: "redis", ContainerPort: 6379}},
					Command: []string{
						"redis-server",
						"--replicaof", rc.Name + "-master." + rc.Namespace + ".svc.cluster.local", "6379",
						"--replica-read-only", "yes",
					},
				}},
			},
		}
		return controllerutil.SetControllerReference(&rc, replicasSTS, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// ---- 4. status 回写 ----
	var stsLive appsv1.StatefulSet
	if err := r.Get(ctx, types.NamespacedName{Namespace: rc.Namespace, Name: rc.Name + "-replicas"}, &stsLive); err != nil {
		return ctrl.Result{}, err
	}
	var masterLive appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Namespace: rc.Namespace, Name: rc.Name + "-master"}, &masterLive); err != nil {
		return ctrl.Result{}, err
	}

	ready := masterLive.Status.ReadyReplicas > 0 && stsLive.Status.ReadyReplicas == replicas
	cond := metav1.Condition{
		Type:               "Ready",
		Status:             metav1.ConditionFalse,
		Reason:             "WaitingForReplicas",
		Message:            fmt.Sprintf("master Ready=%v, replicas %d/%d", masterLive.Status.ReadyReplicas > 0, stsLive.Status.ReadyReplicas, replicas),
		ObservedGeneration: rc.Generation,
		LastTransitionTime: metav1.Now(),
	}
	if ready {
		cond.Status = metav1.ConditionTrue
		cond.Reason = "AllReplicasReady"
		cond.Message = fmt.Sprintf("master + %d replicas Ready", replicas)
	}
	changed := !meta.IsStatusConditionPresentAndEqual(rc.Status.Conditions, cond.Type, cond.Status) ||
		rc.Status.ObservedGeneration != rc.Generation ||
		rc.Status.ReadyReplicas != stsLive.Status.ReadyReplicas ||
		rc.Status.DesiredReplicas != replicas
	meta.SetStatusCondition(&rc.Status.Conditions, cond)
	rc.Status.ObservedGeneration = rc.Generation
	rc.Status.ReadyReplicas = stsLive.Status.ReadyReplicas
	rc.Status.DesiredReplicas = replicas
	if changed {
		if err := r.Status().Update(ctx, &rc); err != nil {
			return ctrl.Result{}, err
		}
	}

	logger.Info("调谐完成",
		"master", string(mOp), "masterSvc", string(sOp), "replicasSTS", string(rOp),
		"readyReplicas", stsLive.Status.ReadyReplicas, "desired", replicas)
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
// Owns()：master Deployment / master Service / replicas STS 任一变化都触发调谐——
// 手改副本数或参数，下一轮自动拉回期望状态。
func (r *RedisClusterReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cachev1.RedisCluster{}).
		Owns(&appsv1.Deployment{}).
		Owns(&appsv1.StatefulSet{}).
		Owns(&corev1.Service{}).
		Named("rediscluster").
		Complete(r)
}
