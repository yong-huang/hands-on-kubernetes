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
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	platformv1 "example.com/microservice-operator/api/v1"
)

// MicroServiceReconciler 编排微服务全栈资源
type MicroServiceReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=platform.example.com,resources=microservices,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=platform.example.com,resources=microservices/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=configmaps;services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=networking.k8s.io,resources=ingresses,verbs=get;list;watch;create;update;patch;delete

func (r *MicroServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("microservice", req.NamespacedName)

	var ms platformv1.MicroService
	if err := r.Get(ctx, req.NamespacedName, &ms); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	port := ms.Spec.Port
	if port == 0 {
		port = 8080
	}
	labels := map[string]string{
		"app.kubernetes.io/name":       ms.Name,
		"app.kubernetes.io/managed-by": "microservice-operator",
	}

	created := int32(0)

	// 1. ConfigMap
	if len(ms.Spec.ConfigData) > 0 {
		cm := &corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{Name: ms.Name + "-config", Namespace: ms.Namespace, Labels: labels},
			Data:       ms.Spec.ConfigData,
		}
		if err := controllerutil.SetControllerReference(&ms, cm, r.Scheme); err != nil {
			return ctrl.Result{}, err
		}
		if err := r.Create(ctx, cm); err == nil { created++ } else if !apierrors.IsAlreadyExists(err) { return ctrl.Result{}, err }
	}

	// 2. Deployment
	dep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: ms.Name, Namespace: ms.Namespace, Labels: labels},
		Spec: appsv1.DeploymentSpec{
			Replicas: ms.Spec.Replicas,
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "app",
						Image: ms.Spec.Image,
						Ports: []corev1.ContainerPort{{ContainerPort: port}},
						Env:   envFromSpec(ms.Spec.Env),
					}},
				},
			},
		},
	}
	if err := controllerutil.SetControllerReference(&ms, dep, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.Create(ctx, dep); err == nil { created++ } else if !apierrors.IsAlreadyExists(err) { return ctrl.Result{}, err }

	// 3. Service
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: ms.Name, Namespace: ms.Namespace, Labels: labels},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports:    []corev1.ServicePort{{Port: port, TargetPort: intstr.FromInt32(port)}},
		},
	}
	if err := controllerutil.SetControllerReference(&ms, svc, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.Create(ctx, svc); err == nil { created++ } else if !apierrors.IsAlreadyExists(err) { return ctrl.Result{}, err }

	// 4. Ingress（可选）
	if ms.Spec.IngressHost != "" {
		ing := &networkingv1.Ingress{
			ObjectMeta: metav1.ObjectMeta{Name: ms.Name, Namespace: ms.Namespace, Labels: labels},
			Spec: networkingv1.IngressSpec{
				Rules: []networkingv1.IngressRule{{
					Host: ms.Spec.IngressHost,
					IngressRuleValue: networkingv1.IngressRuleValue{
						HTTP: &networkingv1.HTTPIngressRuleValue{
							Paths: []networkingv1.HTTPIngressPath{{
								Path: "/", PathType: &pathTypePrefix,
								Backend: networkingv1.IngressBackend{Service: &networkingv1.IngressServiceBackend{
									Name: ms.Name, Port: networkingv1.ServiceBackendPort{Number: port},
								}},
							}},
						},
					},
				}},
			},
		}
		if err := controllerutil.SetControllerReference(&ms, ing, r.Scheme); err != nil {
			return ctrl.Result{}, err
		}
		if err := r.Create(ctx, ing); err == nil { created++ }
	}

	// status 回写
	var live appsv1.Deployment
	_ = r.Get(ctx, client.ObjectKeyFromObject(dep), &live)
	cond := metav1.Condition{
		Type: "Ready", Status: metav1.ConditionTrue, Reason: "StackDeployed",
		Message: fmt.Sprintf("%d resources created", created),
		ObservedGeneration: ms.Generation, LastTransitionTime: metav1.Now(),
	}
	meta.SetStatusCondition(&ms.Status.Conditions, cond)
	ms.Status.ReadyReplicas = live.Status.ReadyReplicas
	ms.Status.ResourcesCreated = created
	ms.Status.ObservedGeneration = ms.Generation
	if err := r.Status().Update(ctx, &ms); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("微服务栈部署完成", "resources", created)
	return ctrl.Result{}, nil
}

var pathTypePrefix = networkingv1.PathTypePrefix

func envFromSpec(env map[string]string) []corev1.EnvVar {
	var result []corev1.EnvVar
	for k, v := range env {
		result = append(result, corev1.EnvVar{Name: k, Value: v})
	}
	return result
}

// SetupWithManager sets up the controller with the Manager.
func (r *MicroServiceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&platformv1.MicroService{}).
		Named("microservice").
		Complete(r)
}
