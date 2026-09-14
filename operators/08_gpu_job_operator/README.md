# GPU 训练任务 Operator（项目 8）

> 联动 labs/31 的 fake GPU：普通节点模拟 `nvidia.com/gpu` 扩展资源，`TrainingJob` CR
> 按 gpuCount 自动调度到"有卡"节点，任务生命周期（Pending → Running → Succeeded）
> 全程 status 上报，完成后按 TTL 自动清理——无需真卡即可体验 AI Ops 完整流程。

## 1. 它做什么

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

apply 后：Job 被创建且 `resources.requests` 带 `nvidia.com/gpu: 1` → 只能调度到
"有卡"节点 → status 逐阶段上报（Pending/Running/Succeeded）→ 完成后 TTL 到期自动清理。

## 2. 架构总览

![GPU Job](images/gpu_job.svg)

扩展资源调度的关键只有一行：Job Pod 的 `resources.requests` 里声明
`nvidia.com/gpu: N`，调度器就会把"有足够 GPU 余量"作为可调度前提。
labs/31 的 fake GPU DaemonSet 在指定节点 `patch --overwrite` 上报这个
扩展资源，于是普通节点摇身一变成了"GPU 节点"。Operator Owns 这个 Job，
读 Job 状态翻译成 CR 的 phase。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/08_gpu_job_operator/images/gpu_job.html)
> （或本地打开 [`images/gpu_job.html`](images/gpu_job.html)）。

## 3. 快速开始

```bash
# 前置：先跑 labs/31 给节点上报 fake GPU
cd operators/08_gpu_job_operator
make install && make run
kubectl apply -f config/samples/ai_v1_trainingjob.yaml
kubectl get trainingjob train-sample -w     # Pending → Running → Succeeded
kubectl get pods -l job-name=train-sample-trainer
```

## 4. Reconcile 代码走读

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

## 5. 验收记录（2026-09-05，kind v1.36 + labs/31 fake GPU）

| 验收项 | 结果 |
|:---|:---|
| 任务被调度到"有卡"节点并 Running | ✅ |
| status 逐阶段上报 Pending/Running/Succeeded | ✅ |
| TTL 到期自动清理 | ✅ |

## 6. 文件结构

```
08_gpu_job_operator/
├── internal/controller/trainingjob_controller.go   # Job 编排 + 扩展资源 + phase 翻译
├── config/samples/ai_v1_trainingjob.yaml
└── images/gpu_job.*                                # 架构图三件套
```

## 7. 深入要点

1. **扩展资源调度原理**：`nvidia.com/gpu` 只是名字，调度器只做算术（节点上报多少、
   请求多少），真正的设备分配由各节点的 Device Plugin 完成——fake GPU 钻的就是这个空子；
2. **Operator vs 裸 Job**：裸 Job 自己写调度亲和、自己清理；Operator 把这些固化成
   可复用的领域 API（一个 CR 搞定）；
3. **phase 翻译模式**：CR status 不存细节，只把子资源状态翻译成语义阶段
   （Pending/Running/Succeeded），消费方无需理解 Job 机制。
