# 08 · GPU 训练任务 Operator：扩展资源调度

> 联动 labs/31 的 fake GPU：普通节点模拟 `nvidia.com/gpu` 扩展资源，`TrainingJob` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 按 gpuCount 自动调度到"有卡"节点，任务生命周期（Pending → Running → Succeeded）全程 status 上报，完成后按 TTL 自动清理——无需真卡即可体验 AI Ops 完整流程。读完本篇，你将理解"CR 翻译成带扩展资源的 Job，再把 Job 状态翻译回 phase"的双向翻译模式。

## Background

算法同学提交训练任务的原始形态是一堆手工动作：写一个 Job 清单，在 resources 里手写 `nvidia.com/gpu: 1`，自己加 TTL 清理，跑完盯 Pod 状态判断成败——每个任务重复一遍，写错的（资源单位、清理策略）只有跑了才发现。

这些动作的共性是"机械翻译"：用户意图（要 1 张卡、跑完 60 秒清理）到 K8s 对象（扩展资源请求 + TTLSecondsAfterFinished）之间有固定映射。

本实验把翻译固化进 Operator：`TrainingJob` CR 两个字段说清意图，Job 的编排与状态汇报由 Controller 完成——配合 labs/31 的假卡，整套机制零真卡成本。

## What

一个 `TrainingJob` CR 长这样：

```yaml
apiVersion: ai.example.com/v1
kind: TrainingJob
metadata: { name: demo-training }
spec:
  image: busybox:1.36
  command: ["sleep", "30"]
  gpuCount: 1
  ttlSecondsAfterFinished: 60
```

apply 后：Job 被创建且 `resources.requests` 带 `nvidia.com/gpu: 1` → 只能调度到"有卡"节点 → status 逐阶段上报（Pending/Running/Succeeded）→ 完成后 TTL 到期自动清理。

一句话心智模型：**CR 翻译成带扩展资源的 Job，再把 Job 状态翻译回 CR 的 phase**——但和"模板渲染"不同的是，翻译是双向且持续的：Job 侧任何状态变化都会被翻译回 CR。

| 翻译方向 | 内容 |
|---|---|
| CR → Job | gpuCount → `requests["nvidia.com/gpu"]`；ttl 字段透传 |
| Job → CR | Job/Pod 状态 → Pending / Running / Succeeded |

## When to Use

典型场景：给算法团队屏蔽 K8s 细节（两个字段就是全部心智负担）；统一训练任务的清理策略（TTL 平台统一下发）；为后续接真卡集群/换调度器预留不变的用户接口。

何时不用：多卡分布式训练（需要多 Pod 组网与成员发现，见 operators/09 的 PyTorchJob）；需要 gang 调度的场景（原生调度器会死锁，见 labs/31 Q2）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 裸 Job + 手写资源请求 | 每次重复，易错 | 一次性试验 |
| TrainingJob Operator（本实验） | 领域字段 + 状态翻译 | 单卡训练任务的平台化 |
| Kubeflow Training Operator | 多框架、分布式齐全 | 生产级 ML 平台 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；先跑 labs/31 给节点上报 fake GPU；Go 环境可用。

```bash
cd operators/08_gpu_job_operator
make install && make run
kubectl apply -f config/samples/ai_v1_trainingjob.yaml
kubectl get trainingjob demo-training -w    # Pending → Running → Succeeded
kubectl get pods -l job-name=demo-training-trainer
```

诚实预期：`gpuCount` 超过节点上报的假卡数时任务会 Pending（FailedScheduling）——这与真卡集群行为完全一致，正好可以用来验证调度约束。

## How It Works

扩展资源调度的关键只有一行：Job Pod 的 `resources.requests` 里声明 `nvidia.com/gpu: N`，调度器就会把"有足够 GPU 余量"作为可调度前提。

labs/31 的 fake GPU DaemonSet 在指定节点 `patch --overwrite` 上报这个扩展资源，普通节点摇身一变成了"GPU 节点"——调度器只做算术，不辨真伪。

```go
// 幂等：按固定名找 Trainer Job，没有才创建（CreateOrPatch 同效）
jobName := tj.Name + "-trainer"
err := r.Get(ctx, ..., &existing); hasJob := err == nil
// 扩展资源声明：调度器据此选择"有卡"节点
job.Spec.Template.Spec.Containers[0].Resources.Requests =
    corev1.ResourceList{"nvidia.com/gpu": int32ToQuantity(tj.Spec.GPUCount)}
// TTL 直接透传给 Job：完成后由 kubelet 按 TTL 清理，Operator 不用自己写定时器
TTLSecondsAfterFinished: tj.Spec.TTLSecondsAfterFinished,
// Owns(&batchv1.Job{})：Job 状态变化触发 Reconcile → 翻译成 CR 的 phase
```

`nvidia.com/gpu` 只是名字，调度器只做算术（节点上报多少、请求多少），真正的设备分配由各节点的 Device Plugin 完成——fake GPU 钻的就是这个空子。你在 `get trainingjob -w` 看到的阶段推进，就是 Owns() 触发 Reconcile 后的翻译结果。

验收记录（2026-09-05，kind v1.36 + labs/31 fake GPU）：

| 验收项 | 结果 |
|:---|:---|
| 任务被调度到"有卡"节点并 Running | ✅ |
| status 逐阶段上报 Pending/Running/Succeeded | ✅ |
| TTL 到期自动清理 | ✅ |

## Pitfalls & Q&A

踩坑清单：

- 扩展资源 requests ≠ limits：创建即被拒（不可超卖），翻译层要保证两处一致。
- 用 update 改 Job：Job 的 pod 模板创建后不可变，变更意图应落在 CR 上由 Controller 重建 Job。

**Q1: 有了 Job，为什么还要 TrainingJob Operator？**

裸 Job 把运维知识摊给每个用户：扩展资源怎么写、TTL 怎么设、状态怎么查。

Operator 把这些固化成领域 API——`gpuCount` 和 `ttlSecondsAfterFinished` 两个字段就是全部心智负担，且平台侧可以在不惊动用户的情况下升级实现（换 gang 调度器、接真实 GPU 集群、加配额管控）。

**Q2: CR 的 phase 为什么要"翻译"而不是直接透传 Job 状态？**

status 是 CR 的对外契约：消费方（流水线、面板、告警）只需要 Pending/Running/Succeeded 这三个语义阶段，不应该被迫理解 Job 的 Conditions 细节。翻译层还隔离了实现变化——哪天把 Job 换成 Volcano 或 RayJob，phase 语义不变，消费方无感。
