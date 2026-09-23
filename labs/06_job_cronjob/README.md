# 06 · Job 与 CronJob：会结束的工作

> Deployment 假设 Pod 应该永远活着，挂了就重建；但有一大类工作**天生要结束**——跑完就该退出，而且要"论成败"。Job / CronJob 就是为它们设计的。

## What

**Job** 创建一个或多个 Pod，保证指定数量的 Pod **成功结束**（exit 0）；**CronJob** 按 cron 表达式周期性地创建 Job——真正干活的还是 Job，它只是调度器。一句话心智模型：**Deployment 以"存活"论成败，Job 以"退出码"论成败**。

Job 的语义由三个字段共同决定：

| 字段 | 含义 | 示例 |
|------|------|------|
| `completions` | 需要成功完成的 Pod 总数（总任务量） | 6 = 一共要跑成 6 个 |
| `parallelism` | 同一时刻最多并行的 Pod 数（并发度） | 2 = 每批最多 2 个同时跑 |
| `backoffLimit` | 累计失败重试上限，超过则 Job 标记 Failed | 4 = 最多容忍 4 个失败 Pod |

三种典型组合：

- **completions=1, parallelism=1**：最简单的一次性任务（本例 pi）
- **completions=N, parallelism=M**：工作队列模式，N 个任务 M 个 worker 分批消费（本例 work-queue）
- **不写 completions, 只写 parallelism=N**：只保证"成功 1 个"，N 个并行赛跑，谁先成功谁定结果（并行求解/竞速）

CronJob 关键在 `concurrencyPolicy`——上一次的 Job 还没跑完，新调度点又到了怎么办：

| 策略 | 行为 | 适用场景 |
|------|------|----------|
| Allow（默认） | 新旧 Job 并发执行 | 任务轻量、互不干扰 |
| Forbid | 跳过本次调度 | 任务可能耗时超过周期（如备份），绝不允许重叠 |
| Replace | 杀掉正在跑的旧 Job，用新的替代 | 只关心最新一次结果 |

## Why

批处理任务（转码 100 个视频、跑一次数据清洗）和定时任务（每小时备份、每天报表）用 Deployment 跑有两个致命问题：任务进程正常退出（exit 0）会被当成"崩溃"，Deployment 无脑重启容器，任务陷入死循环；且没有"成功/失败"的概念——副本数永远是 3，但你永远不知道任务跑完没有。

Job 把"任务跑完了吗"变成一等公民：K8s 替你数成功数、控制并发、按退避重试、超时强杀，CronJob 再加上"到点自动触发"。

## How

```bash
cd labs/06_job_cronjob
./job_cronjob.sh apply      # 一次性 Job（算 pi）+ 工作队列 Job + CronJob 定时备份
./job_cronjob.sh parallel   # 观察 work-queue：completions=6 × parallelism=2 分批跑
./job_cronjob.sh cronjob    # 手动触发一次 CronJob：kubectl create job --from=...
./job_cronjob.sh failure    # 必失败 Job：观察 backoff 与最终 Failed
./job_cronjob.sh suspend    # 挂起 / 恢复 CronJob
./job_cronjob.sh clean
```

关键字段（`manifests/job_cronjob.yaml`）：

```yaml
# Job 侧：
spec:
  completions: 6              # 需要成功完成的 Pod 总数
  parallelism: 2              # 同时最多 2 个 Pod 并行
  backoffLimit: 6             # 累计 6 次失败后放弃, Job -> Failed
  activeDeadlineSeconds: 300  # 整体超时死线, 优先于重试
  template:
    spec:
      restartPolicy: Never    # 只能是 Never / OnFailure, 不能用 Always

# CronJob 侧：
spec:
  schedule: "0 * * * *"           # 每小时整点 (时区通常为 UTC)
  concurrencyPolicy: Forbid       # 上一轮没跑完则跳过本次
  startingDeadlineSeconds: 300    # 错过调度点 300 秒内可补启动
  successfulJobsHistoryLimit: 3   # 保留最近 3 个成功 Job
  failedJobsHistoryLimit: 1       # 保留最近 1 个失败 Job
  suspend: false                  # true = 暂停后续所有调度
  jobTemplate:                    # 每次 tick 按此模板创建 Job
    spec: { ... }                 # 结构与普通 Job 的 spec 相同
```

## Deep Dive

**restartPolicy：Never vs OnFailure**：Job 的 Pod 模板里 `restartPolicy` 只允许 `Never` 或 `OnFailure`（Deployment 默认的 `Always` 对 Job 非法——Job 的语义就是靠"Pod 结束"来判断成败的），失败处理路径完全不同：

- **Never**：容器一失败，整个 Pod 标记 Failed，**Job 新建一个 Pod** 重试；失败 Pod 保留现场，方便 `kubectl describe` 排查
- **OnFailure**：**在同一个 Pod 里重启容器**，RESTARTS +1，不产生新的 Failed Pod

经验法则：任务**可重入/幂等**用 OnFailure 省资源；想**保留失败现场**（core dump、错误日志）或不可安全原地重跑，用 Never。两者都受 backoffLimit 约束。

**重试与死线**：重试按**指数退避**（10s → 20s → 40s…）；`activeDeadlineSeconds` 给 Job 整体设"死线"，超时强制终止——它优先于 backoffLimit，任务可能还没重试完就被判超时。

**CronJob 的调度语义**：schedule 是标准五段 cron（分 时 日 月 周），注意**时区取决于控制器所在时区，通常 UTC**。`startingDeadlineSeconds` 决定"错过调度点多久内还能补启动"——控制器宕机恢复后可能连错好几个 tick，期限内逐个补跑（可能连补多次），超期直接跳过；补跑时若上一轮还在跑，按 `concurrencyPolicy` 处理。所以"至少一次触发"是常态，**任务必须幂等**。`successfulJobsHistoryLimit` / `failedJobsHistoryLimit` 控制保留多少历史 Job 供查日志。

踩坑清单：

- Job 的 Pod **退出码 0 才算成功**；exit 非 0 都会触发重试
- `kubectl scale job` 只能临时调大 parallelism，**不能改 completions**
- Job 完成后 Pod 默认保留（可看日志），但 Job 对象堆积会占用 etcd——用 `ttlSecondsAfterFinished` 或历史上限清理
- CronJob 的 tick 是分钟级精度，控制器恢复后可能**连续补跑**错过的 tick，任务必须幂等

## Q&A

**Q1: Job / CronJob / Deployment / StatefulSet / DaemonSet 怎么选？**
按生命周期判断：跑完即退且要论成败用 Job；周期性触发用 CronJob；永不结束、要自愈和持续可用的无状态服务用 Deployment；有状态用 StatefulSet（lab 08）；每节点跑一个的守护进程用 DaemonSet（lab 07）。

**Q2: 如何"暂停"一个 CronJob 而不丢配置？**
不删对象，`suspend: true`——暂停后续所有调度但保留配置和历史，改回 `false` 恢复；已在运行的 Job 不受影响。临时手动触发一次则用 `kubectl create job --from=cronjob/X`。
