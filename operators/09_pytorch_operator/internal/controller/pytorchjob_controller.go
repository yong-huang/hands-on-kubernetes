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
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	aiv1 "example.com/pytorch-operator/api/v1"
)

// PyTorchJobReconciler 编排 1 Master + N Worker 的分布式训练
type PyTorchJobReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=ai.example.com,resources=pytorchjobs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=ai.example.com,resources=pytorchjobs/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

func (r *PyTorchJobReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("pytorchjob", req.NamespacedName)

	var pj aiv1.PyTorchJob
	if err := r.Get(ctx, req.NamespacedName, &pj); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// 1. Headless Service
	hsvc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: pj.Name + "-h", Namespace: pj.Namespace, Labels: ptLabels(pj.Name)},
		Spec: corev1.ServiceSpec{
			ClusterIP:                "None",
			Selector:                 ptLabels(pj.Name),
			Ports:                    []corev1.ServicePort{{Name: "torch", Port: 29500}},
			PublishNotReadyAddresses: true,
		},
	}
	if err := ctrl.SetControllerReference(&pj, hsvc, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	_, err := controllerutil.CreateOrPatch(ctx, r.Client, hsvc, func() error {
		hsvc.Spec.Selector = ptLabels(pj.Name)
		return ctrl.SetControllerReference(&pj, hsvc, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// 2. Master Pod（rank 0）
	master := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: pj.Name + "-master", Namespace: pj.Namespace, Labels: ptLabels(pj.Name)},
		Spec: corev1.PodSpec{
			RestartPolicy: corev1.RestartPolicyNever,
			Containers: []corev1.Container{{
				Name:  "torch",
				Image: pj.Spec.Image,
				Ports: []corev1.ContainerPort{{Name: "torch", ContainerPort: 29500}},
			}},
		},
	}
	if err := ctrl.SetControllerReference(&pj, master, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	_, err = controllerutil.CreateOrPatch(ctx, r.Client, master, func() error {
		return ctrl.SetControllerReference(&pj, master, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// 3. Worker Deployment（N-1 个）
	workerCount := pj.Spec.Workers - 1
	workers := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: pj.Name + "-worker", Namespace: pj.Namespace, Labels: ptLabels(pj.Name)},
	}
	wOp, err := controllerutil.CreateOrPatch(ctx, r.Client, workers, func() error {
		workers.Spec = ptWorkerSpec(pj.Name, pj.Spec.Image, pj.Spec.Command, workerCount)
		return ctrl.SetControllerReference(&pj, workers, r.Scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}

	// status 回写
	cond := metav1.Condition{
		Type: "Ready", Status: metav1.ConditionTrue, Reason: "DistributedTraining",
		Message:            fmt.Sprintf("master + %d workers 编排完成", workerCount),
		ObservedGeneration: pj.Generation, LastTransitionTime: metav1.Now(),
	}
	meta.SetStatusCondition(&pj.Status.Conditions, cond)
	pj.Status.ObservedGeneration = pj.Generation
	pj.Status.Phase = "Training"
	pj.Status.ReadyWorkers = workerCount
	pj.Status.DesiredWorkers = workerCount + 1
	if err := r.Status().Update(ctx, &pj); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("PyTorchJob 编排完成", "workers", wOp,
		"workers", workerCount+1)
	return ctrl.Result{}, nil
}

func ptLabels(name string) map[string]string {
	return map[string]string{"app.kubernetes.io/name": name, "app.kubernetes.io/framework": "pytorch"}
}

func ptWorkerSpec(name, image string, cmd []string, count int32) appsv1.DeploymentSpec {
	replicas := count
	return appsv1.DeploymentSpec{
		Replicas: &replicas,
		Selector: &metav1.LabelSelector{MatchLabels: ptLabels(name + "-worker")},
		Template: corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{Labels: ptLabels(name + "-worker")},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name:    "torch",
					Image:   image,
					Command: append([]string{"torchrun", "--nproc_per_node=1"}, cmd...),
					Env: []corev1.EnvVar{
						{Name: "MASTER_ADDR", Value: name + "-master"},
						{Name: "MASTER_PORT", Value: "29500"},
					},
				}},
			},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *PyTorchJobReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&aiv1.PyTorchJob{}).
		Named("pytorchjob").
		Complete(r)
}
