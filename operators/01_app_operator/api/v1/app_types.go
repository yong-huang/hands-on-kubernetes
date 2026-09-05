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

// AppSpec defines the desired state of App
type AppSpec struct {
	// image 是业务容器镜像，必须带 tag（生产禁止 latest）
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:example:="nginx:alpine"
	Image string `json:"image"`

	// replicas 是期望的 Pod 副本数，缺省 1
	// +optional
	// +kubebuilder:default=1
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=50
	Replicas *int32 `json:"replicas,omitempty"`

	// env 注入容器的环境变量
	// +optional
	Env map[string]string `json:"env,omitempty"`

	// configData 写入 ConfigMap 的键值对，经 volume 挂载到容器 /etc/app
	// +optional
	ConfigData map[string]string `json:"configData,omitempty"`
}

// AppStatus defines the observed state of App.
type AppStatus struct {
	// conditions represent the current state of the App resource.
	// Each condition has a unique type and reflects the status of a specific aspect of the resource.
	//
	// Standard condition types include:
	// - "Available": the resource is fully functional
	// - "Progressing": the resource is being created or updated
	// - "Degraded": the resource failed to reach or maintain its desired state
	//
	// The status of each condition is one of True, False, or Unknown.
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// observedGeneration 是 controller 最近一次处理的 metadata.generation。
	// 若它小于 generation，说明 spec 改了但 controller 还没看完。
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// externalID 模拟"外部系统"里的资源 ID（真实场景：云盘 ID、DNS 记录、
	// 托管数据库实例等）。Pod/CR 销毁时 Operator 要负责清理它——这正是
	// Finalizer 存在的理由。
	// +optional
	ExternalID string `json:"externalID,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Image",type=string,JSONPath=`.spec.image`
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=`.spec.replicas`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Available")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// App is the Schema for the apps API
type App struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of App
	// +required
	Spec AppSpec `json:"spec"`

	// status defines the observed state of App
	// +optional
	Status AppStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// AppList contains a list of App
type AppList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []App `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &App{}, &AppList{})
		return nil
	})
}
