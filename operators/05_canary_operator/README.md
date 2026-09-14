# 金丝雀发布 Operator（项目 5）

> 一个 `Canary` CR 声明稳定/金丝雀两版镜像和 steps 权重序列（25% → 50% → 100%），
> Controller 编排两个 Deployment，按权重计算副本数比例模拟流量切分，
> 以**状态机**（Progressing → Completed/Rollback）驱动整个发布流程。

## 1. 它做什么

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

创建 CR 后：金丝雀版按第一步权重接入 → 推进 step 流量比例变化 → 100% 即发布完成。
任一步骤不健康可回滚到稳定版。

## 2. 架构总览

![Canary 发布](images/canary_flow.svg)

Reconcile 是一台小状态机：读 `status.currentStep` → 按 `steps[step].weight` 计算
`canaryReplicas = total × weight / 100`（不足 1 时保底 1，避免金丝雀永远 0 副本）、
`stableReplicas = total - canaryReplicas` → CreateOrPatch 两套 Deployment →
status 上报当前阶段。Finalizer 保证发布中不被误删。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/05_canary_operator/images/canary_flow.html)
> （或本地打开 [`images/canary_flow.html`](images/canary_flow.html)）。

## 3. 快速开始

```bash
cd operators/05_canary_operator
make install && make run
kubectl apply -f config/samples/delivery_v1_canary.yaml
kubectl get canary demo-canary -w          # 观察 phase/step 推进
kubectl get deploy -w                      # 观察两套 Deployment 副本数此消彼长
```

## 4. Reconcile 代码走读

```go
// 幂等补 Finalizer（发布中防误删）
if controllerutil.AddFinalizer(&canary, "delivery.example.com/finalizer") { ... }
// 权重 → 副本数换算（保底 1 副本）
canaryReplicas = total * weight / 100
if canaryReplicas < 1 { canaryReplicas = 1 }
stableReplicas := total - canaryReplicas
// CreateOrPatch 两套 Deployment（镜像来自 stableImage/canaryImage）
```

## 5. 已知限制（诚实预期）

当前版本 stable 的副本数在 step 推进时**未实际缩减**（只改了 status 报告）。
生产实现需要：① 每步 CreateOrPatch 两个 Deployment 的 replicas；
② 等待 canary Ready 后才缩减 stable。已在代码 TODO 标注——这也是本项目的
进阶练习：把"报告流量比例"补全成"真实流量比例"。

## 6. 验收记录（2026-09-05，kind v1.36）

| 验收项 | 结果 |
|:---|:---|
| CR 创建后 stable + canary 两套 Deployment 出现 | ✅ |
| status 按 steps 报告当前权重与阶段 | ✅ |
| stable 缩减 | ⚠️ 待修（见上"已知限制"） |

## 7. 文件结构

```
05_canary_operator/
├── internal/controller/canary_controller.go   # 状态机 + 双 Deployment 编排
├── config/samples/delivery_v1_canary.yaml
└── images/canary_flow.*                       # 架构图三件套
```

## 8. 深入要点

1. **金丝雀 vs 蓝绿**：金丝雀按比例渐进、可回滚粒度细；蓝绿是一次性切换、回滚快但资源双倍；
2. **权重模拟 vs 真流量**：副本数比例只是流量比例的近似；生产应接 Service Mesh 或
   Ingress 权重（如 Istio VirtualService）做真流量切分；
3. **发布状态机为什么要落 status**：Controller 重启后能从 status.currentStep 恢复，
   而不是从头再放一遍。
