# Kafka Topic Operator（项目 7）

> 第一个**管理集群外资源**的 Operator：`KafkaTopic` CR 声明 Topic 的分区数、副本因子
> 和 retention 配置，Controller 应当调 Kafka AdminClient API 收敛实际状态——
> 这就是"CR 即 API"的外部资源管理模式（ES Index、RabbitMQ Queue 同理）。

## 1. 它做什么

```yaml
apiVersion: kafka.example.com/v1
kind: KafkaTopic
metadata: { name: demo-topic }
spec:
  topicName: demo-topic
  partitions: 3
  replicationFactor: 1
  bootstrapServers: "kafka:9092"
  configs: { retention.ms: "604800000" }
```

意图：创建 CR 后 Kafka 集群出现对应 Topic → 改 partitions 生效 → 删 CR 同步删 Topic。
Finalizer 防孤儿：外部资源没清干净前，CR 不允许真正消失。

## 2. 架构总览

![Kafka Topic](images/kafka_topic.svg)

外部资源管理型 Operator 的标准回路：读 CR 期望 → 调外部系统 API 对比实际状态 →
创建/变更/删除三态收敛 → status 上报结果。与集群内编排型 Operator（项目 1/10）
的唯一区别是：**"实际状态"不在 apiserver 里，而在外部系统中**。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/07_kafka_topic_operator/images/kafka_topic.html)
> （或本地打开 [`images/kafka_topic.html`](images/kafka_topic.html)）。

## 3. 快速开始

```bash
cd operators/07_kafka_topic_operator
make install && make run
kubectl apply -f config/samples/kafka_v1_kafkatopic.yaml
kubectl get kafkatopic demo-topic -o wide     # status.ready=true + condition 消息
```

## 4. Reconcile 代码走读（教学实现）

```go
setCondition(&kt, "Ready", metav1.ConditionTrue, "TopicManaged",
    fmt.Sprintf("topic=%s partitions=%d RF=%d（教学模式：模拟外部 API 调用）",
        topicName, kt.Spec.Partitions, kt.Spec.ReplicationFactor))
kt.Status.Ready = true
```

当前是**教学模式**：用 condition/message 模拟"调外部 API 并收敛"的动作，
重点演示外部资源管理型 Operator 的骨架（CR → 期望 → 收敛 → status 上报）。
生产版本需要接入 kafka-go 的 AdminClient：CreateTopics / CreatePartitions /
DeleteTopics 三个调用对应创建、扩分区、删除三态，外加 Finalizer 防孤儿。

## 5. 与生产实现的差距（诚实清单）

| 教学版 | 生产版 |
|:---|:---|
| 模拟外部 API（status 报告） | kafka-go AdminClient 真实调用 |
| 无 Finalizer | Finalizer：外部 Topic 未清理前阻止 CR 删除 |
| 不处理扩分区限制 | 扩分区只能增不能减，需校验 |
| 无外部系统连通性探测 | bootstrapServers 不可达时 condition 报错并退避重试 |

## 6. 文件结构

```
07_kafka_topic_operator/
├── internal/controller/kafkatopic_controller.go   # 收敛骨架 + condition 上报
├── config/samples/kafka_v1_kafkatopic.yaml
└── images/kafka_topic.*                           # 架构图三件套
```

## 7. 深入要点

1. **外部资源管理的核心难点**：实际状态在 apiserver 之外，"对比收敛"的每一环
   （读取、变更、删除）都可能失败，必须逐态上报并退避重试；
2. **为什么外部资源必须配 Finalizer**：没有它，删 CR 后外部 Topic 成为无人认领的孤儿，
   而 Operator 已无从得知该清理什么；
3. **举一反三**：ES Index、RabbitMQ Exchange、DNS 记录、云数据库实例——
   全部是这个模式的换皮。
