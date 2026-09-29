# 05 · 金丝雀发布 Operator：状态机驱动发布

> 一个 `Canary` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 声明稳定/金丝雀两版镜像和 steps 权重序列（25% → 50% → 100%），Controller 编排两个 Deployment，按权重计算副本数比例模拟流量切分，以**状态机**（Progressing → Completed/Rollback）驱动整个发布流程。读完本篇，你将理解"发布进度落在 status"为什么是状态机的关键。注意：本实验 stable 缩容为已知待修项（诚实预期）。

## Background

手工金丝雀发布的流程是：改一部分副本到新版本 → 等一段时间看监控 → 没问题再放大比例 → 全量后清理旧版本。每个环节都靠人盯：发布到第几步存在人脑和聊天记录里，重启、换班、并行发布都会乱；回滚要手工把副本改回去，速度取决于发现问题的速度。

把发布序列写进 CR、把进度写进 status，发布就从"操作"变成"状态收敛"：任何人任何时候看 CR 都知道发布在哪一步，Controller 按序列自动推进，出问题回退一步权重即可。本实验用两个 Deployment 的副本比例模拟流量切分，重点在发布状态机本身。

## What

一个 `Canary` CR 长这样：

```yaml
apiVersion: delivery.example.com/v1
kind: Canary
metadata: { name: demo-canary }
spec:
  targetRef: demo-app          # 目标应用名（两套 Deployment 的命名前缀）
  stableImage: "nginx:1.25"    # 稳定版
  canaryImage: "nginx:1.27"    # 金丝雀版
  totalReplicas: 4
  steps:                       # 发布序列：25% → 50% → 100%
    - { weight: 25 }
    - { weight: 50 }
    - { weight: 100 }
```

创建 CR 后：金丝雀版按第一步权重接入 → 推进 step 流量比例变化 → 100% 即发布完成；任一步骤不健康可回滚到稳定版。一句话心智模型：**发布流程 = 状态机**——`status.currentStep` 是状态，Reconcile 是转移函数。

但和"流程引擎"不同的是，这里的状态转移是幂等重放的：Controller 重启后从 status 恢复，不会从头再放一遍。

## When to Use

典型场景：新版本先放 25% 观察错误率，再逐步放量；发布需要跨越多个时间窗（状态持久化后随时恢复）；需要"发布中防误删"的保护（Finalizer）。

何时不用：蓝绿发布场景（一次性切换，不需要渐进比例）；需要真流量按请求级切分（副本比例只是近似，见 Q2，生产接 mesh/Ingress 权重）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 手工改副本数 | 全靠人盯 | 临时验证 |
| Canary Operator（本实验） | 序列声明 + 状态机 + Finalizer | 学习发布自动化 |
| Argo Rollouts / Flagger | 指标驱动自动推进 | 生产渐进交付（labs/28） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用。

```bash
cd operators/05_canary_operator
make install && make run
kubectl apply -f config/samples/delivery_v1_canary.yaml
kubectl get canary demo-canary -w          # 观察 phase/step 推进
kubectl get deploy -w                      # 观察两套 Deployment 副本数此消彼长
```

诚实预期（已知限制）：当前版本 stable 的副本数在 step 推进时**未实际缩减**（只改了 status 报告）——生产实现需要每步同时 CreateOrPatch 两个 Deployment 的 replicas，并等待 canary Ready 后才缩减 stable，已在代码 TODO 标注。

这是本实验刻意留下的进阶练习：把"报告流量比例"补全成"真实流量比例"。

## How It Works

Reconcile 是一台小状态机，四步：读 `status.currentStep`；按 `steps[step].weight` 计算 `canaryReplicas = total × weight / 100`。

副本数不足 1 时保底 1（避免金丝雀永远 0 副本）；另一侧 `stableReplicas = total - canaryReplicas`。

随后 CreateOrPatch 两套 Deployment，并把当前阶段写入 status。

Finalizer 保证发布中不被误删。

```go
// 幂等补 Finalizer（发布中防误删）
if controllerutil.AddFinalizer(&canary, "delivery.example.com/finalizer") { ... }
// 权重 → 副本数换算（保底 1 副本）
canaryReplicas = total * weight / 100
if canaryReplicas < 1 { canaryReplicas = 1 }
stableReplicas := total - canaryReplicas
// CreateOrPatch 两套 Deployment（镜像来自 stableImage/canaryImage）
```

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR 创建后 stable + canary 两套 Deployment 出现 | ✅ |
| status 按 steps 报告当前权重与阶段 | ✅ |
| stable 缩减 | ⚠️ 待修（见"诚实预期"） |

## Pitfalls & Q&A

踩坑清单：

- stable 未实际缩减（已知待修项）：观察流量比例时以 status 报告为准，别假设 Deployment 副本已变化。
- 金丝雀权重 25% × total=2 副本算出 0：保底 1 副本逻辑必须有，否则金丝雀永远不接入。
- 发布中误删 CR：Finalizer 缺失时全栈直接消失——发布类 Operator 必须加。

**Q1: 金丝雀和蓝绿发布怎么选？**
金丝雀按比例渐进、回滚粒度细（回退一步权重即可），适合有监控反馈的持续发布；蓝绿是一次性切换、回滚快（切回旧环境）但资源双倍，适合变更少、验证窗口集中的场景。金丝雀是更通用的默认选择，蓝绿适合"要么全新要么全旧"的强一致性需求。

**Q2: 副本数比例等于流量比例吗？**

只是近似。本实验用副本数比例模拟流量切分（4 副本 25% = 1 个金丝雀 Pod），但 Service 的轮询分发并不严格按副本比例。

生产应接 Service Mesh 或 Ingress 权重做真流量切分（如 Istio VirtualService 的 weight，见 labs/13）——Operator 的价值在于把"何时推进到下一步"的发布状态机管起来，流量执行层可以换。

**Q3: 发布状态机为什么必须落在 status 里？**

Controller 是水平触发的，随时可能重启、重调度。进度只在内存里的话，重启后要么从头再放一遍（重复发布），要么卡死在中间。`status.currentStep` 让状态机持久化在 etcd 里，重启后读 status 恢复现场——spec 是用户给的期望，status 是流程自己的记忆。
