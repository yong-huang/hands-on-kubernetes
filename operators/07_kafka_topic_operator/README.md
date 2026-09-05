# Kafka Topic Operator（项目 7）

> 第一个**管理集群外资源**的 Operator：`KafkaTopic` CR 声明 Topic 的分区数、副本因子
> 和配置，Controller 调 Kafka AdminClient API 收敛实际状态——这就是"CR 即 API"的
> 外部资源管理模式。

## 1. 架构总览

![Kafka Topic](images/kafka_topic.svg)

## 2. 快速开始

```bash
make install && make run
kubectl apply -f config/samples/kafka_v1_kafkatopic.yaml
kubectl get kafkatopic demo-topic -o wide
```

## 3. 文件结构

标准 kubebuilder 工程 + images/ 三件套。教学实现（模拟外部 API 调用），
生产版本需接入 kafka-go AdminClient。
