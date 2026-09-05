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

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// MySQLSpec defines the desired state of MySQL
type MySQLSpec struct {
	// storageSize 是数据卷容量（volumeClaimTemplates 动态供给）
	// +kubebuilder:default="5Gi"
	// +kubebuilder:validation:Pattern=`^[0-9]+([.][0-9]+)?(Mi|Gi)$`
	StorageSize string `json:"storageSize"`

	// rootPasswordSecret 引用已有 Secret 里的 root 密码——
	// 密码不进 CR 明文（CR 会进 etcd 与审计日志）
	// +required
	RootPasswordSecret SecretRef `json:"rootPasswordSecret"`

	// backupSchedule 是备份 CronJob 的 cron 表达式；留空 = 不备份
	// +optional
	// +kubebuilder:example:="0 2 * * *"
	BackupSchedule string `json:"backupSchedule,omitempty"`

	// backupRetentionDays 只影响命名/说明，清理交给外部 ILM 或人工
	// +optional
	// +kubebuilder:validation:Minimum=1
	BackupRetentionDays int `json:"backupRetentionDays,omitempty"`
}

// SecretRef 指向一个 Secret 的某个键
type SecretRef struct {
	// +required
	Name string `json:"name"`
	// +required
	Key string `json:"key"`
}

// MySQLStatus defines the observed state of MySQL.
type MySQLStatus struct {
	// backupCronJobName 记录备份 CronJob 的名字
	// +optional
	BackupCronJobName string `json:"backupCronJobName,omitempty"`

	// conditions represent the current state of the MySQL resource.
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
// +kubebuilder:printcolumn:name="Storage",type=string,JSONPath=`.spec.storageSize`
// +kubebuilder:printcolumn:name="Backup",type=string,JSONPath=`.status.backupCronJobName`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// MySQL is the Schema for the mysqls API
type MySQL struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of MySQL
	// +required
	Spec MySQLSpec `json:"spec"`

	// status defines the observed state of MySQL
	// +optional
	Status MySQLStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// MySQLList contains a list of MySQL
type MySQLList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []MySQL `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &MySQL{}, &MySQLList{})
		return nil
	})
}
