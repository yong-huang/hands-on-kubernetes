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

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	controllerutil "sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	aiv1 "example.com/gpu-job-operator/api/v1"
)

// TrainingJobReconciler reconciles a TrainingJob object
type TrainingJobReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=ai.example.com,resources=trainingjobs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=ai.example.com,resources=trainingjobs/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=batch,resources=jobs,verbs=get;list;watch;create;update;patch;delete

// Reconcile 把 TrainingJob CR 转化为 K8s Job 并追踪其生命周期。
// GPU 需求通过 resources.requests 中的扩展资源名（nvidia.com/gpu）传达给调度器。
func (r *TrainingJobReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("trainingjob", req.NamespacedName)

	var tj aiv1.TrainingJob
	if err := r.Get(ctx, req.NamespacedName, &tj); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// 已有 Job 则只更新 status
	var existing batchv1.Job
	jobName := tj.Name + "-trainer"
	err := r.Get(ctx, client.ObjectKey{Namespace: tj.Namespace, Name: jobName}, &existing)
	hasJob := err == nil

	if !hasJob {
		// 创建 Job
		job := &batchv1.Job{
			ObjectMeta: metav1.ObjectMeta{Name: jobName, Namespace: tj.Namespace},
			Spec: batchv1.JobSpec{
				BackoffLimit:            &[]int32{3}[0],
				TTLSecondsAfterFinished: tj.Spec.TTLSecondsAfterFinished,
				Template: corev1.PodTemplateSpec{
					Spec: corev1.PodSpec{
						RestartPolicy: corev1.RestartPolicyNever,
						Containers: []corev1.Container{{
							Name:    "trainer",
							Image:   tj.Spec.Image,
							Command: tj.Spec.Command,
							Resources: corev1.ResourceRequirements{
								Limits: corev1.ResourceList{
									"nvidia.com/gpu": int32ToQuantity(tj.Spec.GPUCount),
								},
							},
						}},
						// fake GPU 集群所有节点均可调度
						NodeSelector: nil,
					},
				},
			},
		}
		if err := controllerutil.SetControllerReference(&tj, job, r.Scheme); err != nil {
			return ctrl.Result{}, err
		}
		if err := r.Create(ctx, job); err != nil && !apierrors.IsAlreadyExists(err) {
			return ctrl.Result{}, err
		}
		meta.SetStatusCondition(&tj.Status.Conditions, metav1.Condition{
			Type: "Created", Status: metav1.ConditionTrue, Reason: "JobCreated",
			Message:            fmt.Sprintf("Job %s created with %d GPU", jobName, tj.Spec.GPUCount),
			ObservedGeneration: tj.Generation, LastTransitionTime: metav1.Now(),
		})
		tj.Status.Phase = "Running"
		tj.Status.JobName = jobName
		if err := r.Status().Update(ctx, &tj); err != nil {
			return ctrl.Result{}, err
		}
		logger.Info("Training Job 已创建", "gpuCount", tj.Spec.GPUCount)
		return ctrl.Result{}, nil
	}

	// Job 存在，更新 phase
	switch {
	case existing.Status.Succeeded > 0:
		tj.Status.Phase = "Succeeded"
	case existing.Status.Failed > 0:
		tj.Status.Phase = "Failed"
	default:
		tj.Status.Phase = "Running"
	}
	tj.Status.JobName = jobName
	changed := tj.Status.Phase != ""
	if changed {
		if err := r.Status().Update(ctx, &tj); err != nil {
			return ctrl.Result{}, err
		}
	}

	logger.Info("TrainingJob 状态", "phase", tj.Status.Phase)
	return ctrl.Result{}, nil
}

func int32ToQuantity(n int32) resource.Quantity {
	return resource.MustParse(fmt.Sprintf("%d", n))
}

// SetupWithManager sets up the controller with the Manager.
func (r *TrainingJobReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&aiv1.TrainingJob{}).
		Owns(&batchv1.Job{}).
		Named("trainingjob").
		Complete(r)
}
