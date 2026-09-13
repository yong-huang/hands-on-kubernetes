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

// KafkaTopicSpec defines the desired state of KafkaTopic
type KafkaTopicSpec struct {
	// topic 在 Kafka 集群中的名字（默认与 CR 同名）
	// +optional
	TopicName string `json:"topicName,omitempty"`

	// +kubebuilder:default=3
	// +kubebuilder:validation:Minimum=1
	Partitions int32 `json:"partitions"`

	// +kubebuilder:default=1
	// +kubebuilder:validation:Minimum=1
	ReplicationFactor int32 `json:"replicationFactor"`

	// +optional
	Configs map[string]string `json:"configs,omitempty"`

	// kafkaBootstrapServers 是 Kafka 集群的 bootstrap 地址
	// +required
	BootstrapServers string `json:"bootstrapServers"`
}

// KafkaTopicStatus defines the observed state of KafkaTopic
type KafkaTopicStatus struct {
	// +optional
	Ready bool `json:"ready,omitempty"`

	// +optional
	Message string `json:"message,omitempty"`

	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Partitions",type=integer,JSONPath=`.spec.partitions`
// +kubebuilder:printcolumn:name="RF",type=integer,JSONPath=`.spec.replicationFactor`
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=`.status.ready`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// KafkaTopic is the Schema for the kafkatopics API
type KafkaTopic struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              KafkaTopicSpec   `json:"spec"`
	Status            KafkaTopicStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type KafkaTopicList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []KafkaTopic `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &KafkaTopic{}, &KafkaTopicList{})
		return nil
	})
}
