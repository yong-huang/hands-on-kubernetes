# Fake GPU Operator 与 AI Ops 体验

## 1. 文件结构

```
31_fake_gpu_operator/
├── README.md            # 本文档
├── gpu_ops.sh           # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── fake_gpu.yaml    # 演示用的 K8s 清单
└── images/
    ├── fake_gpu_gates.architecture.json  # 图源（Archify Typed JSON IR）
    ├── fake_gpu_gates.html               # 交互版架构图
    └── fake_gpu_gates.svg                # 双主题矢量版（本文档 §5 内嵌）
```

## 2. 项目概述

GPU 是 AI 基础设施里最稀缺的资源，但没有真卡也能把 GPU Ops 的完整流程跑通。本项目（`fake_gpu.yaml` + `gpu_ops.sh`）在普通节点上模拟 `nvidia.com/gpu` 扩展资源：DaemonSet 定时向 Node status 写入假容量，调度器视角与真实 GPU 完全一致——随后体验 AI 任务按卡调度、ResourceQuota 卡配额、describe node 巡检分配的全套日常。

---

## 3. 核心机制解析

### 1. 扩展资源只是数字：模拟的合法性来源

```yaml
status:
  allocatable:
    nvidia.com/gpu: "8"
```

K8s 对扩展资源（`nvidia.com/gpu` 这类带域名的 key）只做算术：调度时比较 requests 与 allocatable、绑定时扣减记账。**它不验证资源物理存在**——这正是 fake 方案成立的基础。真实链路是 Device Plugin 经 gRPC socket 向 kubelet 上报设备列表；模拟版直接 patch 同样的字段，下游全链路无感。

### 2. 为什么用 DaemonSet + 定时补写

```bash
while true; do kubectl patch node $NODE --subresource=status ...; sleep 15; done
```

Node status 可能被 kubelet 的周期心跳覆盖回"没有 GPU"，所以 updater 需要常驻补写——这与真实 gpu-operator 的行为一致（插件崩溃后 kubelet 同样会撤掉资源上报）。`--subresource=status` 配合最小 RBAC（只允许 patch nodes/status），权限面收敛清晰。

### 3. 两道关卡：配额先于调度

```yaml
# ResourceQuota
hard: {requests.nvidia.com/gpu: "4"}
# Job 容器
resources: {requests: {nvidia.com/gpu: 6}, limits: {nvidia.com/gpu: 6}}
```

扩展资源的 requests 必须等于 limits（不可超卖）。train-small 要 1 张：配额内且节点有余量 → Running。train-big 要 6 张：已用 1 + 申请 6 > 团队额度 4 → 在**准入阶段就被 ResourceQuota 拒绝**，Pod 根本不会被创建——注意这与"调度不满足而 Pending"是两种不同失败，排障时看事件文本区分。

### 4. GPU 巡检的日常视角

```text
describe nodes -> Allocated resources 区段: nvidia.com/gpu 1 (12%)
get pods -o custom-columns=POD,GPU,NODE   # 按 Pod 反查谁占着卡
```

AI Ops 最常见的问题就是"卡去哪了"：节点级分配率看 describe，Pod 级占用用 custom-columns 抽取 `spec.containers[].resources.requests["nvidia.com/gpu"]`。配上项目 23 的 Prometheus（DCGM exporter）还能画利用率曲线。

---

## 4. 可视化

![Fake GPU 关卡](images/fake_gpu_gates.svg)

左半是合法性来源：真实链路（device plugin 经 gRPC 上报）与模拟链路（updater 定时 patch nodes/status）**殊途同归于 Node status**——调度器只认数字不辨真伪。右半是 AI 任务的两道关卡：先过 ResourceQuota（train-big 要 6 卡 > 团队额度 4，准入即拒），再过 Scheduler Filter（余量够才绑定），train-small 1 卡顺利 Running。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/31_fake_gpu_operator/images/fake_gpu_gates.html)（或本地打开 [`images/fake_gpu_gates.html`](images/fake_gpu_gates.html)）。

---

## 5. 工程延伸

- **时间片/共享**: 真实场景可上 NVIDIA time-slicing 或 MIG 切分，一张 A100 服务多个任务——device plugin 层面的改动对用户透明
- **Volcano/Gang 调度**: 多卡分布式训练要求"N 个 Pod 同时就位"，原生 scheduler 会死锁，需要 gang scheduler
- **DCGM 监控**: 接入 dcgm-exporter 后 GPU 利用率/显存/温度进 Prometheus，配 HPA 按卡排队深度扩容
- **接回 Karmada**: 项目 30 的联邦可以把训练 Job 分发到有真实 GPU 的远端集群——三个项目串成完整 AI 平台故事
