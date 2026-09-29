# 03 · Deployment：自愈、扩缩容与滚动更新

> 直接创建 Pod 有三个致命问题：无自愈、无扩缩容、无滚动更新。Deployment 用"声明期望状态 + 控制循环"一次性解决——这是理解 K8s 声明式设计的最佳入口。读完本篇，你将掌握三层 ownership、滚动更新的时序约束，以及回滚的真实原理。

## Background

在 Deployment 出现之前，用裸 Pod 跑服务是常态：节点宕机后 Pod 不会自动重建，值班人员半夜爬起来手工补；流量高峰来了，逐台 `docker run` 加副本；升级镜像只能删旧建新，服务中断几分钟。

这三个动作的共性是"人肉维持期望状态"。Kubernetes 的解法是把期望状态写成声明（几个副本、什么镜像），让一个常驻控制器持续把实际状态向期望状态收敛——这就是 Deployment。

它也是理解整个 K8s 声明式设计的入口：后续的 StatefulSet、DaemonSet 都复用同一套"声明 + 控制循环"模式。

## What

Deployment 是管理无状态应用（Pod 可随时销毁重建、不在本地保存必须持久化的数据）的上层控制器：你声明期望状态（几个副本、用什么镜像），控制器持续把实际状态向期望状态收敛。

一句话心智模型：**改 template = 触发滚动更新；undo = 把旧 RS 的模板拷回来再正向滚一次**。但和"一键回退按钮"不同的是，回滚也会完整走一遍发布流程，而不是瞬间切回去。

它不直接管 Pod，而是三层 ownership（"谁创建谁管理"的从属链）：

```
Deployment（应用版本管理：滚动更新、回滚）
├── ReplicaSet（副本管理：保证 Pod 数量，每个版本一个 RS）
└── Pod（真正干活的实例）
```

Pod 通过 `pod-template-hash` 标签区分自己属于哪个 RS；每次修改 Pod 模板（镜像、环境变量等）就**新建一个 RS**，并按 `maxSurge` / `maxUnavailable` 约束"扩新 RS、缩旧 RS"。更新策略两种：

| 策略 | 行为 | 服务中断 | 适用场景 |
|------|------|----------|----------|
| RollingUpdate（默认） | 新 RS 逐步扩容、旧 RS 逐步缩容 | 无 | 绝大多数无状态服务 |
| Recreate | 先杀掉全部旧 Pod，再创建新 Pod | 有 | 不允许多版本共存的应用（如新旧副本会争抢同一外部资源/数据卷） |

## When to Use

典型场景：web / API 这类无状态服务的日常发布与回滚；流量波动时水平扩缩容；节点故障后自动补齐副本。

何时不用：有状态应用（数据库、消息队列——Pod 需要稳定身份和独立存储，用 StatefulSet，见 lab 08）；每节点都要跑一个的守护进程（用 DaemonSet，见 lab 07）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 裸 Pod | 无自愈、无发布能力 | 一次性调试 |
| Deployment | 无身份副本 + 滚动更新 | 无状态服务（默认选择） |
| StatefulSet | 稳定身份 + 独立存储 | 有状态应用 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/03_deploy
./deploy.sh apply     # 创建（replicas=3, RollingUpdate），看三层结构
./deploy.sh scale     # 扩缩容 3 → 5 → 2 → 3
./deploy.sh update    # 滚动更新 nginx:1.25 → 1.26，对比新旧 RS
./deploy.sh rollback  # rollout undo（含 --to-revision 指定版本）
./deploy.sh pause     # 暂停/恢复发布（累积改动一次生效）
./deploy.sh clean     # 清理
./deploy.sh all       # 以上全跑（默认）
```

成功判据：`update` 后 `kubectl rollout status` 输出 successfully rolled out；`get rs` 里新旧 ReplicaSet 的 DESIRED 3/0 互换；`rollback` 后镜像回到 1.25（实际输出以运行为准）。

日常操作对应的 kubectl 命令：

```bash
kubectl rollout status deployment/nginx-rolling        # 盯着看发布进度
kubectl set image deployment/nginx-rolling nginx=nginx:1.26
kubectl rollout history deployment/nginx-rolling      # 查看修订版
kubectl rollout undo  deployment/nginx-rolling        # 回滚上一版
kubectl rollout undo  deployment/nginx-rolling --to-revision=2  # N 必须仍存在, 超过保留数的旧修订已被回收
kubectl rollout pause deployment/nginx-rolling        # 暂停（可累积多处改动）
kubectl rollout resume deployment/nginx-rolling       # 恢复后一次性发布
```

`manifests/deploy.yaml` 含两个 Deployment 示例（RollingUpdate vs Recreate）。关键字段：

```yaml
spec:
  replicas: 3                 # 期望副本数
  revisionHistoryLimit: 5     # 保留多少个旧 RS 供回滚
  minReadySeconds: 5          # Pod Ready 后至少活 5 秒才算"可用"
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1             # 最多超出期望副本数 1 个（先扩新再缩旧）
      maxUnavailable: 0       # 最多允许 0 个不可用（容量永不下降）
  selector:                   # 标签选择器，"认领"自己的 Pod，创建后不可改
    matchLabels:
      app: nginx-rolling
  template:                   # Pod 模板，改它 = 触发滚动更新
    ...
```

## How It Works

**滚动更新的时序约束**：以 `replicas=3, maxSurge=1, maxUnavailable=0`、nginx 1.25 → 1.26 为例，任意时刻新旧 Pod 总数被约束在 `[replicas - maxUnavailable, replicas + maxSurge]` 区间内：

```
t0: v1 v1 v1          稳态：3 个旧 Pod
t1: v2 v1 v1 v1       maxSurge=1：先多建 1 个新 Pod（总数 4）
t2: v2 v1 v1          新 Pod Ready 后，杀掉 1 个旧 Pod（总数 3）
t3: v2 v2 v1 v1       再 surge 1 个新 Pod（总数 4）……循环
t4: v2 v2 v2          完成：新 RS desired=3，旧 RS desired=0
```

两个参数是"更新速度 vs 可用容量"的折中：maxSurge 越大更新越快（并行度高）但多占资源；maxUnavailable 越大更新越快但更新期间容量下降。极端对比：`maxSurge=0, maxUnavailable=1` 省资源但容量先降后升；

`maxSurge=1, maxUnavailable=0` 容量永不下降但更新稍慢。

**rollout history / undo 的原理**：Deployment 的"历史版本"就是那些**被缩容到 0 但没删除的旧 ReplicaSet**（保留数量由 `revisionHistoryLimit` 控制，默认 10，本实验设为 5）。

`kubectl rollout undo` 把上一个 RS 的 Pod 模板拷回 Deployment spec，再触发一次正常的滚动更新——你在 `rollback` 步骤看到的版本切换，就是这条"拷模板再正向滚"的路径。三个易错点：

- 修订版号**只增不减**——undo 并不是把指针拨回去，而是产生一个携带旧模板的**新**修订；
- 超出保留数的旧修订会被回收——所以脚本/CI 里别写死 `--to-revision=2`，应动态查询现存修订；
- `--record` 已废弃，CHANGE-CAUSE 应在更新前用 `kubectl annotate deployment/x kubernetes.io/change-cause="..."` 声明（新 RS 创建时拷贝该注解）。

## Pitfalls & Q&A

踩坑清单：

- **selector 创建后不可修改**，且必须匹配 `template.labels`。
- `maxSurge` / `maxUnavailable` 可写数字或百分比（默认 25%/25%），二者不能同时为 0。
- `readinessProbe` 是滚动更新的安全阀：新 Pod 未 Ready 就不会有旧 Pod 被杀。
- 没有 requests/limits 的 Pod 属于 BestEffort QoS（K8s 的服务质量等级：没有 requests/limits 的 Pod 优先级最低），资源紧张时最先被驱逐。

**Q1: maxSurge / maxUnavailable 生产上怎么选？**

按"容量敏感度"决策：面向用户的无状态服务求稳，用 `maxSurge=1, maxUnavailable=0`（容量永不下降，代价是多占一个副本的资源）；

批处理或资源紧张的内部服务可用 `maxSurge=0, maxUnavailable=1`（省资源，代价是发布期间容量先降后升）。无论怎么配，都要配 readinessProbe——否则"Ready"没有语义，两个参数的约束形同虚设。

**Q2: Deployment 不能管理哪类工作负载？**

有状态应用。Deployment 的 Pod 是无身份的（名字随机、可互相替换、无稳定存储和网络标识），有状态应用应该用 **StatefulSet**（稳定 hostname、有序启停、每副本独立 PV，见 lab 08）；此外守护进程类用 DaemonSet（lab 07）、单次任务用 Job（lab 06）。
