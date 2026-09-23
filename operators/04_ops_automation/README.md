# 04 · 运维自动化 Operator：Cron 扩缩容与滚动重启

> 两个协作的 Controller：`Scaler` CR 按 **Cron 表达式**定时扩缩容目标 Deployment（早高峰扩、夜间缩）；给 Deployment 打 **restart 注解**触发逐 Pod 滚动重启（等 Ready 再删下一个）。核心学习点：时间驱动的 Reconcile、annotation 触发模式、patch 不覆盖用户字段。

## What

定时扩缩容用 CR 声明：

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

滚动重启则完全不需要新 CR——打一个注解：

```bash
kubectl annotate deploy ops-target-nginx ops.example.com/rolling-restart=restart-now
```

RestartReconciler 感知注解 → 逐 Pod 重启（等新 Pod Ready 再删下一个，服务不中断）。一句话心智模型：**运维动作分成两类——周期性的收敛成 CR，一次性的收敛成注解**。

## Why

"早 9 点扩到 5、晚 10 点缩回 2"这类定时操作靠人值班或 crontab 脚本，都逃不开同一个软肋：执行机器挂了或重启，状态就断了——不知道上次执行到哪、当前应该是什么副本数。Operator 把它转成水平触发：每个调谐周期判断"现在应该是什么状态"，错了就收敛过去，错过的时间点不用补、重启后自动归位。滚动重启同理：删除式重启粗暴且危险，借 Deployment 自身滚动机制的重启才是无损的。

## How

```bash
cd operators/04_ops_automation
make install && make run
kubectl apply -f config/samples/ops_v1_scaler.yaml
# 到达 cron 时间点观察副本数；或手动触发滚动重启：
kubectl annotate deploy ops-target-nginx ops.example.com/rolling-restart=restart-now
kubectl get pods -w    # 逐个重启，服务不中断
```

诚实预期：cron 生效要等真实时间点到达（脚本样例是每天 9 点/22 点），验证时可临时把 cron 改成几分钟内的时间点。

## Deep Dive

两条独立的调谐回路：**ScalerReconciler** 每个 Reconcile 周期用 cronlib 判定"当前时刻命中哪条 schedule"，命中才 patch 副本数（**只 patch replicas 字段，不覆盖用户其他配置**）；**RestartReconciler** watch 带 restart 注解的 Deployment，把 restarted-at 注解更新为当前时间戳，借 Deployment 自身的滚动机制完成重启。

```go
// ScalerReconciler：时间驱动 —— 每次调谐判断"现在"是否命中某条 schedule
match, err := cronMatches(s.Cron, now)     // robfig/cron 解析 + 匹配
...
// 关键：用 patch 只改副本数字段，目标 Deployment 的其他配置原样保留
// RestartReconciler：注解驱动 —— 更新 restarted-at 注解触发滚动
```

- **手改副本数不会被误覆盖**：只有 cron 命中的调谐才会 patch，其余调谐不触碰 replicas；
- **逐 Pod 重启**：改 restarted-at 注解 → 滚动更新策略（maxUnavailable=1）保证一次只换一个。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| 到达 schedule 时间点副本数自动变化 | ✅ |
| annotate 后 Pod 逐个重启、服务不中断 | ✅ |
| 手改副本数不会被非命中调谐误覆盖 | ✅ |

## Q&A

**Q1: 为什么用 Reconcile 实现定时任务，而不是直接跑 crontab？**
cron 是"到点做什么"的边缘触发思路，错过的点就永远错过了；Operator 把它转成"当前应该是什么状态"的水平触发——重启后无需恢复状态、自动收敛到当前应处的副本数，天然幂等。代价是调谐频率决定时间精度，但扩缩容场景分钟级精度足够。

**Q2: patch 和 update 有什么区别？**
patch 只带变更字段，不会覆盖用户配置；update 整对象回写会踩掉他人的并发改动——你读到的快照和提交之间，别人可能已经改了别的字段。改"别人的资源"（目标 Deployment 不归本 Controller 独有）时必须用 patch。

**Q3: 滚动重启为什么不直接删 Pod？**
删 Pod 后 ReplicaSet 会按旧模板拉回一个一模一样的 Pod——什么都没重启。正确姿势是改 Pod 模板（如 restarted-at 注解）触发滚动更新，让新旧 Pod 按 maxUnavailable/maxSurge 交替替换，服务容量不下降。
