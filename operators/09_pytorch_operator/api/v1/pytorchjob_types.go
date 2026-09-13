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

// PyTorchJobSpec defines the desired state of PyTorchJob
type PyTorchJobSpec struct {
	// +required
	// +kubebuilder:default="pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime"
	Image string `json:"image"`

	// +required
	Command []string `json:"command"`

	// +kubebuilder:default=1
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=8
	Workers int32 `json:"workers"`
}

// PyTorchJobStatus defines the observed state of PyTorchJob
type PyTorchJobStatus struct {
	// +optional
	Phase string `json:"phase,omitempty"`

	// +optional
	ReadyWorkers int32 `json:"readyWorkers,omitempty"`

	// +optional
	DesiredWorkers int32 `json:"desiredWorkers,omitempty"`

	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Workers",type=integer,JSONPath=`.status.readyWorkers`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// PyTorchJob is the Schema for the pytorchjobs API
type PyTorchJob struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              PyTorchJobSpec   `json:"spec"`
	Status            PyTorchJobStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type PyTorchJobList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []PyTorchJob `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &PyTorchJob{}, &PyTorchJobList{})
		return nil
	})
}
