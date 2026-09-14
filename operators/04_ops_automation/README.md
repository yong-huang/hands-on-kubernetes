# 运维自动化 Operator（项目 4）

> 两个协作的 Controller：`Scaler` CR 按 **Cron 表达式**定时扩缩容目标 Deployment
>（早高峰扩、夜间缩）；给 Deployment 打 **restart 注解**触发逐 Pod 滚动重启（等 Ready 再删下一个）。
> 核心学习点：时间驱动的 Reconcile、annotation 触发模式、patch 不覆盖用户字段。

## 1. 它做什么

```yaml
apiVersion: ops.example.com/v1
kind: Scaler
metadata: { name: ops-sample }
spec:
  targetName: ops-target-nginx     # 目标 Deployment
  schedules:
    - cron: "0 9 * * *"            # 早 9 点
      replicas: 5                  #   扩到 5
    - cron: "0 22 * * *"           # 晚 10 点
      replicas: 2                  #   缩回 2
```

滚动重启则完全不需要新 CR：`kubectl annotate deploy ops-target-nginx ops.example.com/rolling-restart=restart-now`
→ RestartReconciler 感知注解 → 逐 Pod 重启（等新 Pod Ready 再删下一个，服务不中断）。

## 2. 架构总览

![ops flow](images/ops_flow.svg)

两条独立的调谐回路：ScalerReconciler 每个 Reconcile 周期用 cronlib 判定"当前时刻命中哪条
schedule"，命中才 patch 副本数（**只 patch replicas 字段，不覆盖用户其他配置**）；
RestartReconciler watch 带 restart 注解的 Deployment，把 restarted-at 注解更新为当前时间戳，
借 Deployment 自身的滚动机制完成重启。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/04_ops_automation/images/ops_flow.html)
> （或本地打开 [`images/ops_flow.html`](images/ops_flow.html)）。

## 3. 快速开始

```bash
cd operators/04_ops_automation
make install && make run
kubectl apply -f config/samples/ops_v1_scaler.yaml
# 到达 cron 时间点观察副本数；或手动触发滚动重启：
kubectl annotate deploy ops-target-nginx ops.example.com/rolling-restart=restart-now
kubectl get pods -w    # 逐个重启，服务不中断
```

## 4. Reconcile 代码走读

```go
// ScalerReconciler：时间驱动 —— 每次调谐判断"现在"是否命中某条 schedule
match, err := cronMatches(s.Cron, now)     // robfig/cron 解析 + 匹配
...
// 关键：用 patch 只改副本数字段，目标 Deployment 的其他配置原样保留
// RestartReconciler：注解驱动 —— 更新 restarted-at 注解触发滚动
```

- **为什么用 Reconcile 而不是定时任务**：水平触发模型天然容忍错过的时间点（重启后自动收敛到
  当前应处状态），无需持久化"上次执行时间"；
- **手改副本数不会被误覆盖**：只有 cron 命中的调谐才会 patch，其余调谐不触碰 replicas；
- **逐 Pod 重启**：改 restarted-at 注解 → 滚动更新策略（maxUnavailable=1）保证一次只换一个。

## 5. 验收记录（2026-09-05，kind v1.36）

| 验收项 | 结果 |
|:---|:---|
| 到达 schedule 时间点副本数自动变化 | ✅ |
| annotate 后 Pod 逐个重启、服务不中断 | ✅ |
| 手改副本数不会被非命中调谐误覆盖 | ✅ |

## 6. 文件结构

```
04_ops_automation/
├── internal/controller/
│   ├── scaler_controller.go     # Cron 判定 + 副本 patch
│   └── restart_controller.go    # 注解感知 + 滚动重启
├── config/samples/ops_v1_scaler.yaml
└── images/ops_flow.*            # 架构图三件套
```

## 7. 深入要点

1. **时间驱动 vs 水平触发**：cron 是"到点做什么"的边缘触发思路，Operator 把它转成
   "当前应该是什么状态"的水平触发，天然幂等且抗重启丢状态；
2. **patch vs update**：patch 只带变更字段不会覆盖用户配置；update 整对象回写会踩掉他人改动；
3. **滚动重启的正确姿势**：不要删 Pod（RS 会拉回旧 Pod），而是改 Pod 模板触发滚动。
