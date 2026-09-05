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
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	// restartAnnotation 打上这个注解即触发滚动重启
	restartAnnotation = "ops.example.com/rolling-restart"
	// restartedAtAnnotation 模板上的时间戳注解，变更 = 触发滚动更新
	restartedAtAnnotation = "ops.example.com/restarted-at"
)

// RestartReconciler watches Deployments with the restart annotation and
// triggers a rolling restart by patching the pod template.
type RestartReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;update;patch

// Reconcile 检查目标 Deployment 是否带有 rolling-restart 注解；
// 有则 patch pod template（等价于 kubectl rollout restart），触发逐 Pod 重建。
func (r *RestartReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("deployment", req.NamespacedName)

	var dep appsv1.Deployment
	if err := r.Get(ctx, req.NamespacedName, &dep); err != nil {
		if client.IgnoreNotFound(err) != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{}, nil
	}

	// 无注解或注解不为 "true" 则跳过
	if dep.Annotations[restartAnnotation] != "true" {
		return ctrl.Result{}, nil
	}

	logger.Info("滚动重启触发", "deployment", dep.Name)

	// patch pod template 注解——等价于 kubectl rollout restart
	if dep.Spec.Template.Annotations == nil {
		dep.Spec.Template.Annotations = map[string]string{}
	}
	dep.Spec.Template.Annotations[restartedAtAnnotation] = time.Now().Format(time.RFC3339)

	if err := r.Update(ctx, &dep); err != nil {
		return ctrl.Result{}, err
	}

	// 移除触发注解（防重复触发）
	delete(dep.Annotations, restartAnnotation)
	if err := r.Update(ctx, &dep); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("滚动重启已触发（Deployment 逐 Pod 替换）")
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *RestartReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&appsv1.Deployment{}).
		Named("restart").
		Complete(r)
}

// 确保 corev1 被引用（避免 unused import 报错）
var _ = corev1.PodSpec{}
var _ = metav1.ObjectMeta{}
var _ = types.NamespacedName{}
var _ = logf.Log
