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

// Upstream 定义一个上游服务组
type Upstream struct {
	// +required
	Name string `json:"name"`
	// +required
	// +kubebuilder:validation:MinItems=1
	Servers []string `json:"servers"`
}

// Location 定义一个路由规则
type Location struct {
	// +required
	Path string `json:"path"`
	// +required
	Upstream string `json:"upstream"`
}

// NginxProxySpec defines the desired state of NginxProxy
type NginxProxySpec struct {
	// +required
	// +kubebuilder:validation:MinItems=1
	Upstreams []Upstream `json:"upstreams"`

	// +required
	// +kubebuilder:validation:MinItems=1
	Locations []Location `json:"locations"`
}

// NginxProxyStatus defines the observed state of NginxProxy
type NginxProxyStatus struct {
	// +optional
	ConfigHash string `json:"configHash,omitempty"`

	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="ConfigHash",type=string,JSONPath=`.status.configHash`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// NginxProxy is the Schema for the nginxproxies API
type NginxProxy struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitzero"`
	Spec NginxProxySpec `json:"spec"`
	Status NginxProxyStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type NginxProxyList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items []NginxProxy `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &NginxProxy{}, &NginxProxyList{})
		return nil
	})
}
