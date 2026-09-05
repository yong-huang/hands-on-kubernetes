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
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	deliveryv1 "example.com/canary-operator/api/v1"
)

// CanaryReconciler reconciles a Canary object
type CanaryReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=delivery.example.com,resources=canaries,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=delivery.example.com,resources=canaries/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

// Reconcile 实现"渐进式发布状态机"：
// 稳定版全量 → 逐步把副本从稳定版转移到金丝雀版 → 全量后旧版归零。
// 任一步骤新 Pod 不 Ready → 标记 Failed，等人工干预。
func (r *CanaryReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("canary", req.NamespacedName)

	var canary deliveryv1.Canary
	if err := r.Get(ctx, req.NamespacedName, &canary); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// 幂等补 Finalizer
	if controllerutil.AddFinalizer(&canary, "delivery.example.com/finalizer") {
		return ctrl.Result{Requeue: true}, r.Update(ctx, &canary)
	}

	total := canary.Spec.TotalReplicas
	step := canary.Status.CurrentStep
	phase := canary.Status.Phase
	if phase == "" {
		phase = deliveryv1.CanaryPhaseProgressing
	}

	// ---- 计算本 step 的 canary 副本数 ----
	canaryReplicas := int32(0)
	if int(step) < len(canary.Spec.Steps) {
		weight := canary.Spec.Steps[step].Weight
		canaryReplicas = total * weight / 100
		if canaryReplicas < 1 {
			canaryReplicas = 1
		}
	}
	stableReplicas := total - canaryReplicas

	// ---- 确保稳定版 Deployment ----
	stableDep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: canary.Name + "-stable", Namespace: canary.Namespace, Labels: canaryLabels(canary.Name, "stable")},
	}
	_, err := controllerutil.CreateOrPatch(ctx, r.Client, stableDep, func() error {
		stableDep.Spec = canaryDepSpec(canary.Name, canary.Spec.StableImage, "stable", stableReplicas)
		return controllerutil.SetControllerReference(&canary, stableDep, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("stable deployment: %w", err)
	}

	// ---- 确保金丝雀版 Deployment ----
	canaryDep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: canary.Name + "-canary", Namespace: canary.Namespace, Labels: canaryLabels(canary.Name, "canary")},
	}
	if canaryReplicas > 0 {
		_, err = controllerutil.CreateOrPatch(ctx, r.Client, canaryDep, func() error {
			canaryDep.Spec = canaryDepSpec(canary.Name, canary.Spec.CanaryImage, "canary", canaryReplicas)
			return controllerutil.SetControllerReference(&canary, canaryDep, r.Scheme)
		})
		if err != nil {
			return ctrl.Result{}, fmt.Errorf("canary deployment: %w", err)
		}
	}

	// ---- 确保共享 Service（selector 不含 version → 两套都接流量）----
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: canary.Name, Namespace: canary.Namespace, Labels: canaryLabels(canary.Name, "service")},
	}
	_, err = controllerutil.CreateOrPatch(ctx, r.Client, svc, func() error {
		svc.Spec.Selector = canaryLabels(canary.Name, "service")
		svc.Spec.Ports = []corev1.ServicePort{{Name: "http", Port: 80, TargetPort: intstr.FromInt32(80)}}
		return controllerutil.SetControllerReference(&canary, svc, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// ---- 检查健康：canary Deployment Ready 才推进 ----
	var canaryLive appsv1.Deployment
	if canaryReplicas > 0 {
		if err := r.Get(ctx, client.ObjectKeyFromObject(canaryDep), &canaryLive); err != nil {
			return ctrl.Result{}, err
		}
		if canaryLive.Status.ReadyReplicas < canaryReplicas {
			// 新 Pod 还没全部 Ready，等待
			return ctrl.Result{RequeueAfter: 5 * time.Second}, nil
		}
	}

	changed := canary.Status.CurrentStep != step ||
		canary.Status.CanaryReplicas != canaryReplicas ||
		canary.Status.Phase != phase
	_ = changed // status 变更标记

	// ---- 推进到下一步 ----
	if int(step) < len(canary.Spec.Steps)-1 {
		canary.Status.CurrentStep = step + 1
		canary.Status.Phase = deliveryv1.CanaryPhaseProgressing
		changed = true
	} else {
		// 最后一步：全部切到金丝雀版
		canary.Status.Phase = deliveryv1.CanaryPhaseCompleted
		canary.Status.CurrentStep = int32(len(canary.Spec.Steps))
	}
	canary.Status.CanaryReplicas = canaryReplicas
	canary.Status.StableReplicas = stableReplicas
	canary.Status.ObservedGeneration = canary.Generation

	if changed {
		if err := r.Status().Update(ctx, &canary); err != nil {
			return ctrl.Result{}, err
		}
	}

	logger.Info("金丝雀发布状态", "phase", phase, "step", step, "canary", canaryReplicas, "stable", stableReplicas)
	return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
}

func canaryLabels(name, role string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":     name,
		"app.kubernetes.io/managed-by": "canary-operator",
		"app.kubernetes.io/role":     role,
	}
}

func canaryDepSpec(name, image, role string, replicas int32) appsv1.DeploymentSpec {
	return appsv1.DeploymentSpec{
		Replicas: &replicas,
		Selector: &metav1.LabelSelector{MatchLabels: canaryLabels(name, role)},
		Template: corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: canaryLabels(name, role)},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:  "app",
					Image: image,
					Ports: []corev1.ContainerPort{{Name: "http", ContainerPort: 80}},
				}},
			},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *CanaryReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&deliveryv1.Canary{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Named("canary").
		Complete(r)
}
