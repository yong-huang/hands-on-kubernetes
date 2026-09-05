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

// CanaryStep 一次流量推进
type CanaryStep struct {
	// canaryWeight 是金丝雀版承载的流量百分比（0-100）
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=100
	// +required
	Weight int32 `json:"weight"`
}

// CanarySpec defines the desired state of Canary
type CanarySpec struct {
	// targetRef 是稳定版 Deployment 的名字（同 namespace）
	// +required
	// +kubebuilder:validation:MinLength=1
	TargetRef string `json:"targetRef"`

	// stableImage 是当前稳定版镜像
	// +required
	StableImage string `json:"stableImage"`

	// canaryImage 是金丝雀版要验证的新镜像
	// +required
	CanaryImage string `json:"canaryImage"`

	// steps 是逐步推进的流量比例序列
	// +required
	// +kubebuilder:validation:MinItems=1
	Steps []CanaryStep `json:"steps"`

	// totalReplicas 是稳定版+金丝雀版的总副本数
	// +optional
	// +kubebuilder:default=4
	// +kubebuilder:validation:Minimum=2
	TotalReplicas int32 `json:"totalReplicas,omitempty"`
}

// CanaryPhase 是发布状态机的阶段
const (
	CanaryPhaseProgressing = "Progressing"
	CanaryPhaseCompleted   = "Completed"
	CanaryPhaseFailed      = "Failed"
)

// CanaryStatus defines the observed state of Canary
type CanaryStatus struct {
	// phase 是当前发布阶段
	// +optional
	Phase string `json:"phase,omitempty"`

	// currentStep 是当前执行的 step 下标（从 0 开始）
	// +optional
	CurrentStep int32 `json:"currentStep,omitempty"`

	// canaryReplicas 是当前金丝雀版的 Pod 数
	// +optional
	CanaryReplicas int32 `json:"canaryReplicas,omitempty"`

	// stableReplicas 是当前稳定版的 Pod 数
	// +optional
	StableReplicas int32 `json:"stableReplicas,omitempty"`

	// conditions represent the current state of Canary
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
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Step",type=integer,JSONPath=`.status.currentStep`
// +kubebuilder:printcolumn:name="Canary",type=integer,JSONPath=`.status.canaryReplicas`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Canary is the Schema for the canaries API
type Canary struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Canary
	// +required
	Spec CanarySpec `json:"spec"`

	// status defines the observed state of Canary
	// +optional
	Status CanaryStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// CanaryList contains a list of Canary
type CanaryList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Canary `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &Canary{}, &CanaryList{})
		return nil
	})
}
