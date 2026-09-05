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

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// ScaleSchedule 一条定时扩缩容规则：cron 匹配时把目标 Deployment 调到 replicas
type ScaleSchedule struct {
	// cron 表达式（分 时 日 月 周）
	// +required
	Cron string `json:"cron"`

	// cron 匹配时目标 Deployment 的期望副本数
	// +kubebuilder:validation:Minimum=0
	// +required
	Replicas int32 `json:"replicas"`
}

// ScalerSpec defines the desired state of Scaler
type ScalerSpec struct {
	// targetName 是要被扩缩容的目标 Deployment 名字（同 namespace）
	// +required
	// +kubebuilder:validation:MinLength=1
	TargetName string `json:"targetName"`

	// schedules 是一组定时规则：当前时间匹配某条 cron 时，把目标调到对应 replicas。
	// 多条规则可重叠（如工作日/节假日），取最后一条匹配的。
	// +required
	// +kubebuilder:validation:MinItems=1
	Schedules []ScaleSchedule `json:"schedules"`
}

// ScalerStatus defines the observed state of Scaler
type ScalerStatus struct {
	// lastReplicas 是 controller 最近一次设置的目标副本数
	// +optional
	LastReplicas int32 `json:"lastReplicas,omitempty"`

	// lastScaleTime 是最近一次执行扩缩容的时间
	// +optional
	LastScaleTime *metav1.Time `json:"lastScaleTime,omitempty"`

	// currentSchedule 是当前生效的 cron 规则
	// +optional
	CurrentSchedule string `json:"currentSchedule,omitempty"`

	// conditions represent the current state of Scaler
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// observedGeneration 记录 controller 最近处理的 generation
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Target",type=string,JSONPath=`.spec.targetName`
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=`.status.lastReplicas`
// +kubebuilder:printcolumn:name="Schedule",type=string,JSONPath=`.status.currentSchedule`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Scaler is the Schema for the scalers API
type Scaler struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Scaler
	// +required
	Spec ScalerSpec `json:"spec"`

	// status defines the observed state of Scaler
	// +optional
	Status ScalerStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// ScalerList contains a list of Scaler
type ScalerList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Scaler `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &Scaler{}, &ScalerList{})
		return nil
	})
}
