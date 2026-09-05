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
	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// MicroServiceSpec 定义微服务全栈资源的期望状态
type MicroServiceSpec struct {
	// +required
	Image string `json:"image"`

	// +optional
	// +kubebuilder:default=3
	Replicas *int32 `json:"replicas,omitempty"`

	// +optional
	Env map[string]string `json:"env,omitempty"`

	// +optional
	ConfigData map[string]string `json:"configData,omitempty"`

	// +optional
	Port int32 `json:"port,omitempty"`

	// +optional
	IngressHost string `json:"ingressHost,omitempty"`

	// +optional
	HPAEnabled bool `json:"hpaEnabled,omitempty"`

	// +optional
	// +kubebuilder:default=2
	MinReplicas int32 `json:"minReplicas,omitempty"`

	// +optional
	// +kubebuilder:default=10
	MaxReplicas int32 `json:"maxReplicas,omitempty"`
}

// MicroServiceStatus defines the observed state of MicroService
type MicroServiceStatus struct {
	// +optional
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`

	// +optional
	ResourcesCreated int32 `json:"resourcesCreated,omitempty"`

	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Image",type=string,JSONPath=`.spec.image`
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=`.status.readyReplicas`
// +kubebuilder:printcolumn:name="Resources",type=integer,JSONPath=`.status.resourcesCreated`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// MicroService is the Schema for the microservices API
type MicroService struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec MicroServiceSpec `json:"spec"`
	Status MicroServiceStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type MicroServiceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items []MicroService `json:"items"`
}

// DeploySpec 引用 appsv1.DeploymentSpec 的模板（保持与 appsv1 的一致性）
var _ = appsv1.DeploymentSpec{}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &MicroService{}, &MicroServiceList{})
		return nil
	})
}
