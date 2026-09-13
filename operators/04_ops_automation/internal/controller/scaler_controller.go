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

	cronlib "github.com/robfig/cron/v3"
	appsv1 "k8s.io/api/apps/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	opsv1 "example.com/ops-automation/api/v1"
)

// ScalerReconciler reconciles a Scaler object
type ScalerReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=ops.example.com,resources=scalers,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=ops.example.com,resources=scalers/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;get;update;patch

// Reconcile 每 30 秒（或 CR/Deployment 变化时）检查：
// 当前时间是否命中某条 cron 规则 → 命中则把目标 Deployment 调到对应副本数。
// 无论是否命中，都会 requeue 30s 后再查——实现"持续值守"。
func (r *ScalerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("scaler", req.NamespacedName)

	var scaler opsv1.Scaler
	if err := r.Get(ctx, req.NamespacedName, &scaler); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// 找到目标 Deployment
	var dep appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Namespace: scaler.Namespace, Name: scaler.Spec.TargetName}, &dep); err != nil {
		if apierrors.IsNotFound(err) {
			logger.Info("目标 Deployment 不存在", "name", scaler.Spec.TargetName)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		return ctrl.Result{}, err
	}

	// 逐条检查 cron 规则，取最后一条当前时间命中的
	now := time.Now()
	var matched *opsv1.ScaleSchedule
	for i := range scaler.Spec.Schedules {
		s := &scaler.Spec.Schedules[i]
		match, err := cronMatches(s.Cron, now)
		if err != nil {
			logger.Error(err, "cron 解析失败", "cron", s.Cron)
			continue
		}
		if match {
			matched = s
		}
	}

	// 命中了才改副本数；没命中就只等待下一次检查
	if matched != nil {
		current := int32(0)
		if dep.Spec.Replicas != nil {
			current = *dep.Spec.Replicas
		}
		if current != matched.Replicas {
			dep.Spec.Replicas = &matched.Replicas
			if err := r.Update(ctx, &dep); err != nil {
				return ctrl.Result{}, err
			}
			logger.Info("定时扩缩容", "cron", matched.Cron, "replicas", matched.Replicas)
		}
	}

	// status 回写
	cond := metav1.Condition{
		Type:               "Ready",
		Status:             metav1.ConditionTrue,
		Reason:             "Reconciled",
		Message:            fmt.Sprintf("监听 %d 条规则 · 目标 %s", len(scaler.Spec.Schedules), scaler.Spec.TargetName),
		ObservedGeneration: scaler.Generation,
		LastTransitionTime: metav1.Now(),
	}
	statusChanged := !meta.IsStatusConditionPresentAndEqual(scaler.Status.Conditions, cond.Type, cond.Status) ||
		scaler.Status.ObservedGeneration != scaler.Generation
	if matched != nil {
		newLast := matched.Replicas
		if scaler.Status.LastReplicas != newLast {
			scaler.Status.LastReplicas = newLast
			now := metav1.Now()
			scaler.Status.LastScaleTime = &now
			statusChanged = true
		}
		scaler.Status.CurrentSchedule = matched.Cron
	}
	meta.SetStatusCondition(&scaler.Status.Conditions, cond)
	scaler.Status.ObservedGeneration = scaler.Generation
	if statusChanged {
		if err := r.Status().Update(ctx, &scaler); err != nil {
			return ctrl.Result{}, err
		}
	}

	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

// cronMatches 用 robfig/cron 库判断 now 是否命中 cron 表达式
func cronMatches(cronExpr string, now time.Time) (bool, error) {
	sched, err := cronParse(cronExpr)
	if err != nil {
		return false, err
	}
	// 找到 now 之后的下一次触发时间，如果它落在 [now, now+1min) 内则命中
	next := sched.Next(now)
	if next.IsZero() {
		return false, nil
	}
	// cron 分钟粒度：now 的分钟数与 next - 1min 的分钟数相同时视为命中
	prev := next.Add(-time.Minute)
	return now.Truncate(time.Minute).Equal(prev.Truncate(time.Minute)), nil
}

// cronParse 解析 cron 表达式（分 时 日 月 周）
func cronParse(expr string) (cronlib.Schedule, error) {
	return cronlib.ParseStandard(expr)
}

// SetupWithManager sets up the controller with the Manager.
// requeueAfter 30s 实现"持续值守"——定时规则由时间驱动而非事件驱动。
func (r *ScalerReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&opsv1.Scaler{}).
		Named("scaler").
		Complete(r)
}
