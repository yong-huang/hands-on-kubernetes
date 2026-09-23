# 08 · GPU 训练任务 Operator：扩展资源调度

> 联动 labs/31 的 fake GPU：普通节点模拟 `nvidia.com/gpu` 扩展资源，`TrainingJob` CR 按 gpuCount 自动调度到"有卡"节点，任务生命周期（Pending → Running → Succeeded）全程 status 上报，完成后按 TTL 自动清理——无需真卡即可体验 AI Ops 完整流程。

## What

一个 `TrainingJob` CR 长这样：

```yaml
apiVersion: ai.example.com/v1
kind: TrainingJob
metadata: { name: train-sample }
spec:
  image: busybox:1.36
  command: ["sleep", "30"]
  gpuCount: 1
  ttlSecondsAfterFinished: 60
```

apply 后：Job 被创建且 `resources.requests` 带 `nvidia.com/gpu: 1` → 只能调度到"有卡"节点 → status 逐阶段上报（Pending/Running/Succeeded）→ 完成后 TTL 到期自动清理。一句话心智模型：**CR 翻译成带扩展资源的 Job，再把 Job 状态翻译回 CR 的 phase**——用户面对的是"训练任务"，不是 Job 和调度细节。

## Why

AI 训练任务的运维动作高度雷同：申请 N 张卡、调度到有卡的节点、盯生命周期、跑完清理。裸 Job 每次都要手写资源请求、清理策略和状态轮询；把这些固化进 Operator，算法同学只需要提交一个 CR——卡的申请量、生命周期、清理全部声明式，且平台可以统一演进（换调度器、接真卡集群）而 CR 不变。

## How

```bash
# 前置：先跑 labs/31 给节点上报 fake GPU
cd operators/08_gpu_job_operator
make install && make run
kubectl apply -f config/samples/ai_v1_trainingjob.yaml
kubectl get trainingjob train-sample -w     # Pending → Running → Succeeded
kubectl get pods -l job-name=train-sample-trainer
```

诚实预期：`gpuCount` 超过节点上报的假卡数时任务会 Pending（FailedScheduling）——这与真卡集群行为完全一致，正好可以用来验证调度约束。

## Deep Dive

扩展资源调度的关键只有一行：Job Pod 的 `resources.requests` 里声明 `nvidia.com/gpu: N`，调度器就会把"有足够 GPU 余量"作为可调度前提。labs/31 的 fake GPU DaemonSet 在指定节点 `patch --overwrite` 上报这个扩展资源，普通节点摇身一变成了"GPU 节点"——调度器只做算术，不辨真伪。

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

`nvidia.com/gpu` 只是名字，调度器只做算术（节点上报多少、请求多少），真正的设备分配由各节点的 Device Plugin 完成——fake GPU 钻的就是这个空子。

验收记录（2026-09-05，kind v1.36 + labs/31 fake GPU）：

| 验收项 | 结果 |
|:---|:---|
| 任务被调度到"有卡"节点并 Running | ✅ |
| status 逐阶段上报 Pending/Running/Succeeded | ✅ |
| TTL 到期自动清理 | ✅ |

## Q&A

**Q1: 有了 Job，为什么还要 TrainingJob Operator？**
裸 Job 把运维知识摊给每个用户：扩展资源怎么写、TTL 怎么设、状态怎么查。Operator 把这些固化成领域 API——`gpuCount` 和 `ttlSecondsAfterFinished` 两个字段就是全部心智负担，且平台侧可以在不惊动用户的情况下升级实现（换 gang 调度器、接真实 GPU 集群、加配额管控）。

**Q2: CR 的 phase 为什么要"翻译"而不是直接透传 Job 状态？**
status 是 CR 的对外契约：消费方（流水线、面板、告警）只需要 Pending/Running/Succeeded 这三个语义阶段，不应该被迫理解 Job 的Conditions 细节。翻译层还隔离了实现变化——哪天把 Job 换成 Volcano 或 RayJob，phase 语义不变，消费方无感。
