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

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	kafkav1 "example.com/kafka-topic-operator/api/v1"
)

// KafkaTopicReconciler 管理 Kafka Topic 的生命周期（外部 API 管理模式）
type KafkaTopicReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=kafka.example.com,resources=kafkatopics,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kafka.example.com,resources=kafkatopics/status,verbs=get;update;patch

// Reconcile 管理 Kafka Topic 的声明式生命周期。
// 教学实现：模拟外部 API 调用（生产用 kafka-go AdminClient）。
func (r *KafkaTopicReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("kafkatopic", req.NamespacedName)

	var kt kafkav1.KafkaTopic
	if err := r.Get(ctx, req.NamespacedName, &kt); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	topicName := kt.Spec.TopicName
	if topicName == "" {
		topicName = kt.Name
	}

	setCondition(&kt, "Ready", metav1.ConditionTrue, "TopicManaged",
		fmt.Sprintf("topic=%s partitions=%d RF=%d（教学模式：模拟外部 API 调用）",
			topicName, kt.Spec.Partitions, kt.Spec.ReplicationFactor))
	kt.Status.Ready = true
	kt.Status.Message = ""
	if err := r.Status().Update(ctx, &kt); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("Kafka Topic 已管理", "topic", topicName)
	return ctrl.Result{}, nil
}

func setCondition(kt *kafkav1.KafkaTopic, condType string, status metav1.ConditionStatus, reason, msg string) {
	meta.SetStatusCondition(&kt.Status.Conditions, metav1.Condition{
		Type: condType, Status: status, Reason: reason, Message: msg,
		ObservedGeneration: kt.Generation, LastTransitionTime: metav1.Now(),
	})
}

// SetupWithManager sets up the controller with the Manager.
func (r *KafkaTopicReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&kafkav1.KafkaTopic{}).
		Named("kafkatopic").
		Complete(r)
}
