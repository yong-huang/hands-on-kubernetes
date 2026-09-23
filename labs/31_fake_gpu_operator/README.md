# 31 · Fake GPU Operator：扩展资源与 AI Ops

> GPU 是 AI 基础设施里最稀缺的资源，但没有真卡也能把 GPU Ops 的完整流程跑通。本实验在普通节点上模拟 `nvidia.com/gpu` 扩展资源：DaemonSet 定时向 Node status 写入假容量，调度器视角与真实 GPU 完全一致——随后体验 AI 任务按卡调度、ResourceQuota 卡配额、describe node 巡检分配的全套日常。

## What

K8s 对扩展资源（`nvidia.com/gpu` 这类带域名的 key）只做算术：调度时比较 requests 与 allocatable、绑定时扣减记账，**不验证资源物理存在**——这正是 fake 方案成立的基础：

```yaml
status:
  allocatable:
    nvidia.com/gpu: "8"
```

一句话心智模型：**扩展资源只是数字，调度器只认数字不辨真伪**。真实与模拟殊途同归于 Node status：真实链路是 Device Plugin 经 gRPC socket 向 kubelet 上报设备列表；模拟版直接 patch 同样的字段，下游全链路无感。

本实验的三件套：

| 部件 | 角色 |
|------|------|
| updater（DaemonSet） | 每 15s patch `nodes/status` 写入假 GPU 容量 |
| ResourceQuota | 团队级卡配额（准入阶段拦截） |
| 演示 Job | train-small（1 卡，成功）/ train-big（6 卡，超配额被拒） |

## Why

AI 平台运维的核心日常——按卡调度、卡配额、查卡去哪了——全部建立在扩展资源的记账机制上，与卡是不是真的无关。用假卡把这套机制学透，换到有真卡的集群，差异只剩 device plugin 的安装，其余（调度、配额、巡检、监控）一字不变。这是零成本理解 GPU 调度模型的捷径，也是排查"卡分配不对"问题时绕不开的底层机制。

## How

```bash
cd labs/31_fake_gpu_operator
./gpu_ops.sh install   # 部署 updater DaemonSet，节点出现 nvidia.com/gpu: 8
./gpu_ops.sh deploy    # ResourceQuota + train-small(1卡) + train-big(6卡)
./gpu_ops.sh inspect   # describe node 分配率 + 按 Pod 反查占卡
./gpu_ops.sh clean
```

updater 的核心动作（常驻补写，`manifests/fake_gpu.yaml`）：

```bash
while true; do kubectl patch node $NODE --subresource=status ...; sleep 15; done
```

两道关卡的配置——注意扩展资源的 requests 必须等于 limits（不可超卖）：

```yaml
# ResourceQuota
hard: {requests.nvidia.com/gpu: "4"}
# Job 容器
resources: {requests: {nvidia.com/gpu: 6}, limits: {nvidia.com/gpu: 6}}
```

GPU 巡检的日常视角：

```text
describe nodes -> Allocated resources 区段: nvidia.com/gpu 1 (12%)
get pods -o custom-columns=POD,GPU,NODE   # 按 Pod 反查谁占着卡
```

诚实预期：train-small 要 1 张——配额内且节点有余量 → Running；train-big 要 6 张——已用 1 + 申请 6 > 团队额度 4 → 在**准入阶段就被 ResourceQuota 拒绝**，Pod 根本不会被创建。注意这与"调度不满足而 Pending"是两种不同失败，排障时看事件文本区分。

## Deep Dive

**为什么用 DaemonSet + 定时补写**：Node status 可能被 kubelet 的周期心跳覆盖回"没有 GPU"，所以 updater 需要常驻补写——这与真实 gpu-operator 的行为一致（插件崩溃后 kubelet 同样会撤掉资源上报）。`--subresource=status` 配合最小 RBAC（只允许 patch nodes/status），权限面收敛清晰。

**两道关卡的顺序**：配额先于调度。请求先过 ResourceQuota（namespace 级准入，超了直接拒绝创建），再过 Scheduler Filter（节点余量够才绑定）。所以"卡不够"有两种截然不同的失败现场：Quota 拒绝（事件在 namespace 资源配额上，Pod 不存在）vs Pending（Pod 存在，FailedScheduling 事件）。

**巡检是 AI Ops 最高频的动作**："卡去哪了"的答案分两层——节点级分配率看 `describe node` 的 Allocated resources 区段，Pod 级占用用 custom-columns 抽取 `spec.containers[].resources.requests["nvidia.com/gpu"]`。配上 lab 23 的 Prometheus（DCGM exporter）还能画利用率曲线。

## Q&A

**Q1: 一张卡服务多个任务可以吗？**
可以，真实场景上 NVIDIA time-slicing 或 MIG 切分——一张 A100 拆给多个任务用。这是 device plugin 层面的改动，对用户透明：Pod 里申请的还是 `nvidia.com/gpu: 1`，只是背后对应的是时间片或 MIG 实例。

**Q2: 多卡分布式训练为什么原生调度器会死锁？**
"N 个 Pod 同时就位"是 gang 语义：各 Pod 单独调度时，每个都占着一部分资源等同伴，谁也凑不齐。需要 Volcano 这类 gang scheduler——要么全批调度，要么全批等待，资源不许被半批占用。

**Q3: 假卡环境能接监控吗？**
利用率曲线要真卡（dcgm-exporter 采 GPU 利用率/显存/温度进 Prometheus），但分配率的账本（allocatable/allocated）是调度器记的，假卡环境完全真实。配 HPA 还能按卡排队深度扩容。

**Q4: 这套模拟和前面的实验怎么串起来？**
把本实验的演示 Job 换成训练任务、配 lab 30 的 Karmada 联邦分发到有真实 GPU 的远端集群，再接 lab 23 的监控——"按卡调度 → 跨集群分发 → 利用率可观测"就是 AI 平台的完整骨架。
