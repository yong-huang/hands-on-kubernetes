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
	"crypto/sha256"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	webv1 "example.com/nginx-operator/api/v1"
)

// NginxProxyReconciler reconciles a NginxProxy object
type NginxProxyReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=web.example.com,resources=nginxproxies,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=web.example.com,resources=nginxproxies/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

// Reconcile 渲染 nginx.conf → ConfigMap → Deployment（nginx 挂载 ConfigMap）→ Service
// 配置变更 = ConfigMap 变更 = nginx 重新加载配置
func (r *NginxProxyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("nginxproxy", req.NamespacedName)

	var np webv1.NginxProxy
	if err := r.Get(ctx, req.NamespacedName, &np); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	confHash := fmt.Sprintf("%x", sha256.Sum256([]byte(renderNginxConf(&np))))[:12]

	// ---- 1. ConfigMap（nginx.conf）----
	cm := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: np.Name + "-conf", Namespace: np.Namespace, Labels: ngxLabels(np.Name)},
		Data:       map[string]string{"nginx.conf": renderNginxConf(&np)},
	}
	if err := controllerutil.SetControllerReference(&np, cm, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	_, err := controllerutil.CreateOrPatch(ctx, r.Client, cm, func() error {
		cm.Data = map[string]string{"nginx.conf": renderNginxConf(&np)}
		return controllerutil.SetControllerReference(&np, cm, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("configmap: %w", err)
	}

	// ---- 2. Deployment ----
	dep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: np.Name, Namespace: np.Namespace, Labels: ngxLabels(np.Name)},
	}
	_, err = controllerutil.CreateOrPatch(ctx, r.Client, dep, func() error {
		dep.Spec = ngxDepSpec(np.Name, confHash)
		dep.Spec.Template.Annotations = map[string]string{"config-hash": confHash}
		return controllerutil.SetControllerReference(&np, dep, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("deployment: %w", err)
	}

	// ---- 3. Service ----
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: np.Name, Namespace: np.Namespace, Labels: ngxLabels(np.Name)},
	}
	_, err = controllerutil.CreateOrPatch(ctx, r.Client, svc, func() error {
		svc.Spec.Selector = ngxLabels(np.Name)
		svc.Spec.Ports = []corev1.ServicePort{{Name: "http", Port: 80, TargetPort: intstr.FromInt32(80)}}
		return controllerutil.SetControllerReference(&np, svc, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// ---- status 回写 ----
	changed := np.Status.ConfigHash != confHash || np.Status.ObservedGeneration != np.Generation
	cond := metav1.Condition{
		Type: "Ready", Status: metav1.ConditionTrue, Reason: "Deployed",
		Message: fmt.Sprintf("config %s deployed", confHash),
		ObservedGeneration: np.Generation, LastTransitionTime: metav1.Now(),
	}
	meta.SetStatusCondition(&np.Status.Conditions, cond)
	np.Status.ConfigHash = confHash
	np.Status.ObservedGeneration = np.Generation
	if changed {
		if err := r.Status().Update(ctx, &np); err != nil {
			return ctrl.Result{}, err
		}
	}

	logger.Info("调谐完成", "configHash", confHash)
	return ctrl.Result{}, nil
}

// renderNginxConf 从 CR 生成 nginx.conf
func renderNginxConf(np *webv1.NginxProxy) string {
	conf := "events {}\nworker_processes 1;\nhttp {\n"
	for _, u := range np.Spec.Upstreams {
		conf += "  upstream " + u.Name + " {\n"
		for _, s := range u.Servers {
			conf += "    server " + s + ";\n"
		}
		conf += "  }\n"
	}
	conf += "  server {\n    listen 80;\n"
	for _, loc := range np.Spec.Locations {
		conf += "    location " + loc.Path + " {\n"
		conf += "      proxy_pass http://" + loc.Upstream + ";\n"
		conf += "    }\n"
	}
	conf += "  }\n}\n"
	return conf
}

func ngxLabels(name string) map[string]string {
	return map[string]string{"app.kubernetes.io/name": name, "app.kubernetes.io/managed-by": "nginx-operator"}
}

func ngxDepSpec(name, hash string) appsv1.DeploymentSpec {
	replicas := int32(2)
	return appsv1.DeploymentSpec{
		Replicas: &replicas,
		Selector: &metav1.LabelSelector{MatchLabels: ngxLabels(name)},
		Template: corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: ngxLabels(name)},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:  "nginx",
					Image: "nginx:alpine",
					Ports: []corev1.ContainerPort{{Name: "http", ContainerPort: 80}},
					VolumeMounts: []corev1.VolumeMount{{
						Name: "conf", MountPath: "/etc/nginx/nginx.conf",
						SubPath: "nginx.conf", ReadOnly: true,
					}},
				}},
				Volumes: []corev1.Volume{{
					Name: "conf",
					VolumeSource: corev1.VolumeSource{
						ConfigMap: &corev1.ConfigMapVolumeSource{
							LocalObjectReference: corev1.LocalObjectReference{Name: name + "-conf"},
						},
					},
				}},
			},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *NginxProxyReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&webv1.NginxProxy{}).
		Owns(&corev1.ConfigMap{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Named("nginxproxy").
		Complete(r)
}
