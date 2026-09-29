# 31 · Fake GPU Operator：扩展资源与 AI Ops

> GPU 是 AI 基础设施里最稀缺的资源，但没有真卡也能把 GPU Ops 的完整流程跑通。本实验在普通节点上模拟 `nvidia.com/gpu` 扩展资源：DaemonSet 定时向 Node status 写入假容量，调度器视角与真实 GPU 完全一致——随后体验 AI 任务按卡调度、ResourceQuota 卡配额、describe node 巡检分配的全套日常。读完本篇，你将理解扩展资源"只是数字"的记账本质。

## Background

GPU 调度的学习一直有个门槛：先得有卡。真卡昂贵且稀缺，个人环境几乎不可能搭一套"申请卡、排队、占卡、释放"的完整流程来学。而运维 AI 平台的核心日常——按卡调度、卡配额、查卡去哪了——其实建立在 K8s 的扩展资源记账机制上，与卡是不是物理存在无关。

扩展资源（`nvidia.com/gpu` 这类带域名的资源键）在 K8s 里只做算术：节点上报多少、Pod 请求多少，调度器比较数字做决策。理解了这一点，就可以用假数字把整套机制学透——换到真卡集群，差异只剩 device plugin 的安装。

## What

K8s 对扩展资源（`nvidia.com/gpu` 这类带域名的 key）只做算术：调度时比较 requests 与 allocatable、绑定时扣减记账，**不验证资源物理存在**——这正是 fake 方案成立的基础：

```yaml
status:
  allocatable:
    nvidia.com/gpu: "8"
```

一句话心智模型：**扩展资源只是数字，调度器只认数字不辨真伪**。可以把扩展资源想象成"食堂饭票额度"；

但和饭票不同的是，真实与模拟殊途同归于 Node status：真实链路是 Device Plugin 经 gRPC socket 向 kubelet 上报设备列表，模拟版直接 patch 同样的字段，下游全链路无感。

本实验的三件套：

| 部件 | 角色 |
|------|------|
| updater（DaemonSet） | 每 15s patch `nodes/status` 写入假 GPU 容量 |
| ResourceQuota | 团队级卡配额（准入阶段拦截） |
| 演示 Job | train-small（1 卡，成功）/ train-big（6 卡，超配额被拒） |

## When to Use

典型场景：学习/验证 GPU 调度与配额机制（零真卡成本）；给 AI 平台做调度策略回归测试（假卡环境下断言调度行为）；配合 Quota 演练"卡不够"的两种失败现场。

何时不用：利用率、显存、温度等真实指标（假卡没有物理数据，那要 dcgm-exporter + 真卡）；对业务方承诺容量（假卡只用于机制验证）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 真卡 + NVIDIA device plugin | 生产标准 | 有卡环境 |
| Fake GPU（本实验） | 只记账不辨真伪 | 机制学习与调度测试 |
| time-slicing / MIG | 一张卡拆多个份额 | 提高真卡利用率（见 Q1） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/31_fake_gpu_operator
./gpu_ops.sh install   # 部署 updater DaemonSet，节点出现 nvidia.com/gpu: 8
./gpu_ops.sh deploy    # ResourceQuota + train-small(1卡) + train-big(6卡)
./gpu_ops.sh inspect   # describe node 分配率 + 按 Pod 反查占卡
./gpu_ops.sh clean
```

诚实预期：train-small 要 1 张——配额内且节点有余量 → Running；train-big 要 6 张——已用 1 + 申请 6 > 团队额度 4 → 在**准入阶段就被 ResourceQuota 拒绝**，Pod 根本不会被创建。

注意这与"调度不满足而 Pending"是两种不同失败，排障时看事件文本区分。

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

## How It Works

**为什么用 DaemonSet + 定时补写**：Node status 可能被 kubelet 的周期心跳覆盖回"没有 GPU"，所以 updater 需要常驻补写——这与真实 gpu-operator 的行为一致（插件崩溃后 kubelet 同样会撤掉资源上报）。

`--subresource=status` 配合最小 RBAC（只允许 patch nodes/status），权限面收敛清晰。

**两道关卡的顺序**：配额先于调度。请求先过 ResourceQuota（namespace 级准入，超了直接拒绝创建），再过 Scheduler Filter（节点余量够才绑定）。

你在 `deploy` 步骤看到 train-big 直接消失（而非 Pending），就是第一道关卡拦截的结果。

所以"卡不够"有两种截然不同的失败现场：Quota 拒绝（事件在 namespace 资源配额上，Pod 不存在）vs Pending（Pod 存在，FailedScheduling 事件）。

**巡检是 AI Ops 最高频的动作**："卡去哪了"的答案分两层——节点级分配率看 `describe node` 的 Allocated resources 区段，

Pod 级占用用 custom-columns 抽取 `spec.containers[].resources.requests["nvidia.com/gpu"]`。

配上 lab 23 的 Prometheus（DCGM exporter）还能画利用率曲线。

## Pitfalls & Q&A

踩坑清单：

- 把扩展资源 requests 写得不等于 limits：创建即被拒，扩展资源不支持超卖。
- updater 挂了节点"卡"消失：kubelet 心跳会覆盖回去——它与真实 gpu-operator 的崩溃行为一致，可以当特性观察。
- 假卡环境验证利用率监控：永远拿不到数据，利用率要真卡（分配率的账本是真实的）。

**Q1: 一张卡服务多个任务可以吗？**

可以，真实场景上 NVIDIA time-slicing 或 MIG（把一张物理卡切成多个隔离实例）——一张 A100 拆给多个任务用。这是 device plugin 层面的改动，对用户透明：Pod 里申请的还是 `nvidia.com/gpu: 1`，只是背后对应的是时间片或 MIG 实例。

**Q2: 多卡分布式训练为什么原生调度器会死锁？**
"N 个 Pod 同时就位"是 gang 语义：各 Pod 单独调度时，每个都占着一部分资源等同伴，谁也凑不齐。需要 Volcano 这类 gang scheduler——要么全批调度，要么全批等待，资源不许被半批占用。

**Q3: 这套模拟和前面的实验怎么串起来？**

把本实验的演示 Job 换成训练任务、配 lab 30 的 Karmada 联邦分发到有真实 GPU 的远端集群，再接 lab 23 的监控——"按卡调度 → 跨集群分发 → 利用率可观测"就是 AI 平台的完整骨架；operators/08 的 TrainingJob Operator 是这条线的代码化版本。
