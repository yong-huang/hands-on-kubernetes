# 05 · 金丝雀发布 Operator：状态机驱动发布

> 一个 `Canary` CR 声明稳定/金丝雀两版镜像和 steps 权重序列（25% → 50% → 100%），Controller 编排两个 Deployment，按权重计算副本数比例模拟流量切分，以**状态机**（Progressing → Completed/Rollback）驱动整个发布流程。

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

创建 CR 后：金丝雀版按第一步权重接入 → 推进 step 流量比例变化 → 100% 即发布完成；任一步骤不健康可回滚到稳定版。一句话心智模型：**发布流程 = 状态机**——`status.currentStep` 是状态，Reconcile 是转移函数，Controller 重启也不丢进度。

## Why

手工金丝雀要盯着时间点改副本数、记住发布到第几步、出问题手工切回——发布进度存在人脑和聊天记录里，重启、换班、并行发布都会乱。把发布序列写进 CR、把进度写进 status，发布就从"操作"变成"状态收敛"：任何人任何时候看 CR 都知道发布在哪一步，Controller 挂了重启后从 status 恢复继续推进。

## How

```bash
cd operators/05_canary_operator
make install && make run
kubectl apply -f config/samples/delivery_v1_canary.yaml
kubectl get canary demo-canary -w          # 观察 phase/step 推进
kubectl get deploy -w                      # 观察两套 Deployment 副本数此消彼长
```

## Deep Dive

Reconcile 是一台小状态机：读 `status.currentStep` → 按 `steps[step].weight` 计算 `canaryReplicas = total × weight / 100`（不足 1 时保底 1，避免金丝雀永远 0 副本）、`stableReplicas = total - canaryReplicas` → CreateOrPatch 两套 Deployment → status 上报当前阶段。Finalizer 保证发布中不被误删。

```go
// 幂等补 Finalizer（发布中防误删）
if controllerutil.AddFinalizer(&canary, "delivery.example.com/finalizer") { ... }
// 权重 → 副本数换算（保底 1 副本）
canaryReplicas = total * weight / 100
if canaryReplicas < 1 { canaryReplicas = 1 }
stableReplicas := total - canaryReplicas
// CreateOrPatch 两套 Deployment（镜像来自 stableImage/canaryImage）
```

**已知限制（诚实预期）**：当前版本 stable 的副本数在 step 推进时**未实际缩减**（只改了 status 报告）。生产实现需要：① 每步 CreateOrPatch 两个 Deployment 的 replicas；② 等待 canary Ready 后才缩减 stable。已在代码 TODO 标注——这也是本项目的进阶练习：把"报告流量比例"补全成"真实流量比例"。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR 创建后 stable + canary 两套 Deployment 出现 | ✅ |
| status 按 steps 报告当前权重与阶段 | ✅ |
| stable 缩减 | ⚠️ 待修（见上"已知限制"） |

## Q&A

**Q1: 金丝雀和蓝绿发布怎么选？**
金丝雀按比例渐进、回滚粒度细（回退一步权重即可），适合有监控反馈的持续发布；蓝绿是一次性切换、回滚快（切回旧环境）但资源双倍，适合变更少、验证窗口集中的场景。金丝雀是更通用的默认选择，蓝绿适合"要么全新要么全旧"的强一致性需求。

**Q2: 副本数比例等于流量比例吗？**
只是近似。本实验用副本数比例模拟流量切分（4 副本 25% = 1 个金丝雀 Pod），但 Service 的轮询分发并不严格按副本比例。生产应接 Service Mesh 或 Ingress 权重做真流量切分（如 Istio VirtualService 的 weight，见 lab 13）——Operator 的价值在于把"何时推进到下一步"的发布状态机管起来，流量执行层可以换。

**Q3: 发布状态机为什么必须落在 status 里？**
Controller 是水平触发的，随时可能重启、重调度。进度只在内存里的话，重启后要么从头再放一遍（重复发布），要么卡死在中间。`status.currentStep` 让状态机持久化在 etcd 里，重启后读 status 恢复现场——spec 是用户给的期望，status 是流程自己的记忆。
