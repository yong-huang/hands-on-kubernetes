# 07 · Kafka Topic Operator：集群外资源管理

> 第一个**管理集群外资源**的 Operator：`KafkaTopic` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 声明 Topic 的分区数（partition，Topic 的并行单元）、副本因子（replicationFactor，每个分区的数据存几份）和 retention（数据保留时长，`retention.ms: "604800000"` 即 7 天）配置，Controller 应当调 Kafka AdminClient API 收敛实际状态——这就是"CR 即 API"的外部资源管理模式（ES Index、RabbitMQ Queue 同理）。读完本篇，你将理解外部资源管理与集群内编排的本质差异，以及当前教学版与生产版的诚实差距。

## Background

Kafka Topic、ES 索引、消息队列这类集群外资源的生命周期通常靠工单和脚本管理：谁建的、什么配置、删应用时谁负责清理，全靠口头约定。删应用不删 Topic 是常态，孤儿资源越积越多，没人敢清。

把它们接进 K8s API 之后，Topic 获得 CR 的一切待遇：声明式、有审计、进 Git、随应用一起删除。

与集群内编排型 Operator（operators/01、10）不同的是，Topic 的实际状态不在 apiserver 里而在 Kafka 集群里——收敛的每一环都要跨网络调用外部 API，这是这一类 Operator 的核心难点。

## What

一个 `KafkaTopic` CR 长这样：

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

意图：创建 CR 后 Kafka 集群出现对应 Topic → 改 partitions 生效 → 删 CR 同步删 Topic；Finalizer 防孤儿——外部资源没清干净前，CR 不允许真正消失。

一句话心智模型：**收敛回路与集群内 Operator 一模一样，唯一区别是"实际状态"在外部系统中**——但和集群内模式不同的是，级联删除没有 ownerRef 可以委托，清理必须自己动手（Finalizer）。

## When to Use

典型场景：平台团队统一管理"集群内 + 集群外"全部基础设施（Topic、索引、队列都变成 CR）；应用删除时自动清理它声明的 Topic（Finalizer 保证）；Topic 配置进 Git 走评审。

何时不用：外部系统没有完备 CRUD API 或无法读取实际状态（收敛无从谈起）；Topic 高频动态创建销毁（每秒级创建的场景，控制面延迟会成为瓶颈）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 工单 + 脚本 | 灵活但无审计无级联 | 建Topic 频率极低的团队 |
| Strimzi 等 Kafka Operator | 整个 Kafka 集群编排 | 需要连集群本身一起管 |
| 本模式（Topic 级 CRD） | 只管 Topic 生命周期 | Kafka 集群已存在、只管 Topic |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用。不需要真实 Kafka 集群——当前为教学模式。

```bash
cd operators/07_kafka_topic_operator
make install && make run
kubectl apply -f config/samples/kafka_v1_kafkatopic.yaml
kubectl get kafkatopic demo-topic -o wide     # status.ready=true + condition 消息
```

诚实预期：当前是**教学模式**——Controller 用 condition/message 模拟"调外部 API 并收敛"的动作，不要求真实 Kafka 集群；status 上报 `topic=xxx partitions=3 RF=1（教学模式：模拟外部 API 调用）`。

## How It Works

外部资源管理型 Operator 的标准回路：读 CR 期望 → 调外部系统 API 对比实际状态 → 创建/变更/删除三态收敛 → status 上报结果。

教学版的收敛动作（骨架完整，外部调用为模拟）：

```go
setCondition(&kt, "Ready", metav1.ConditionTrue, "TopicManaged",
    fmt.Sprintf("topic=%s partitions=%d RF=%d（教学模式：模拟外部 API 调用）",
        topicName, kt.Spec.Partitions, kt.Spec.ReplicationFactor))
kt.Status.Ready = true
```

与生产实现的差距（诚实清单）：

| 教学版 | 生产版 |
|:---|:---|
| 模拟外部 API（status 报告） | kafka-go AdminClient 真实调用（CreateTopics / CreatePartitions / DeleteTopics 对应三态） |
| 无 Finalizer | Finalizer：外部 Topic 未清理前阻止 CR 删除 |
| 不处理扩分区限制 | 扩分区只能增不能减，需校验 |
| 无外部系统连通性探测 | bootstrapServers 不可达时 condition 报错并退避重试 |

## Pitfalls & Q&A

踩坑清单：

- **外部资源必须配 Finalizer**：没有它，删 CR 后外部 Topic 成为无人认领的孤儿，而 Operator 已无从得知该清理什么——这是外部资源模式与集群内模式（ownerRef 自动级联）最本质的差异，级联必须自己动手。
- **扩分区只能增不能减**：Kafka 的硬限制，Reconcile 里把 partitions 改小要么拒绝、要么报 condition，绝不能盲目下发。

**Q1: 外部资源管理为什么比集群内编排难？**

实际状态在 apiserver 之外，"对比收敛"的每一环（读取、变更、删除）都是一次可能失败的网络调用，且无法靠 ownerRef 委托 K8s 清理。所以生产实现必须逐态上报 condition、失败退避重试、用 Finalizer 保证删除顺序——err 处理的密度比集群内 Operator 高一个量级。

**Q2: 这个模式还能管什么？**

ES Index、RabbitMQ Exchange/Queue、DNS 记录、云数据库实例、GitHub 仓库——凡是"有 API 的外部系统"都可以套这个壳：CR 声明期望、Controller 调对方 API 收敛、Finalizer 防孤儿。

判断标准只有一个：外部系统是否有完备的 CRUD API 以及"读取实际状态"的能力。
