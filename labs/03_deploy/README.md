# 03 · Deployment：自愈、扩缩容与滚动更新

> 直接创建 Pod 有三个致命问题：无自愈、无扩缩容、无滚动更新。Deployment 用"声明期望状态 + 控制循环"一次性解决——这是理解 K8s 声明式设计的最佳入口。

## What

Deployment 是管理无状态应用的上层控制器：你声明期望状态（几个副本、用什么镜像），控制器持续把实际状态向期望状态收敛。一句话心智模型：**改 template = 触发滚动更新；undo = 把旧 RS 的模板拷回来再正向滚一次。**

它不直接管 Pod，而是三层 ownership：

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

## Why

直接创建 Pod 的三个问题：节点宕机后 Pod 不会自动重建（无自愈）、流量高峰时无法快速加副本（无扩缩容）、升级镜像只能删旧建新、服务会中断（无滚动更新）。

Deployment 对症下药：**自愈**——Pod 挂了自动重建，节点故障后在别的节点补齐副本；**扩缩容**——改一个数字（replicas）即可水平伸缩；**滚动更新与回滚**——逐个替换 Pod 完成升级，出问题一键回滚。没有它，这三件事都要靠人肉脚本和值班半夜爬起来处理。

## How

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

## Deep Dive

**滚动更新的时序约束**：以 `replicas=3, maxSurge=1, maxUnavailable=0`、nginx 1.25 → 1.26 为例，任意时刻新旧 Pod 总数被约束在 `[replicas - maxUnavailable, replicas + maxSurge]` 区间内：

```
t0: v1 v1 v1          稳态：3 个旧 Pod
t1: v2 v1 v1 v1       maxSurge=1：先多建 1 个新 Pod（总数 4）
t2: v2 v1 v1          新 Pod Ready 后，杀掉 1 个旧 Pod（总数 3）
t3: v2 v2 v1 v1       再 surge 1 个新 Pod（总数 4）……循环
t4: v2 v2 v2          完成：新 RS desired=3，旧 RS desired=0
```

两个参数是"更新速度 vs 可用容量"的折中：maxSurge 越大更新越快（并行度高）但多占资源；maxUnavailable 越大更新越快但更新期间容量下降。极端对比：`maxSurge=0, maxUnavailable=1` 省资源但容量先降后升；`maxSurge=1, maxUnavailable=0` 容量永不下降但更新稍慢。

**rollout history / undo 的原理**：Deployment 的"历史版本"就是那些**被缩容到 0 但没删除的旧 ReplicaSet**（保留数量由 `revisionHistoryLimit` 控制，默认 10，本实验设为 5）。`kubectl rollout undo` 把上一个 RS 的 Pod 模板拷回 Deployment spec，再触发一次正常的滚动更新——**回滚本质上也是一次滚动更新**。三个易错点：

- 修订版号**只增不减**——undo 并不是把指针拨回去，而是产生一个携带旧模板的**新**修订；
- 超出保留数的旧修订会被回收——所以脚本/CI 里别写死 `--to-revision=2`，应动态查询现存修订；
- `--record` 已废弃，CHANGE-CAUSE 应在更新前用 `kubectl annotate deployment/x kubernetes.io/change-cause="..."` 声明（新 RS 创建时拷贝该注解）。

踩坑清单：

- **selector 创建后不可修改**，且必须匹配 `template.labels`
- `maxSurge` / `maxUnavailable` 可写数字或百分比（默认 25%/25%），二者不能同时为 0
- `readinessProbe` 是滚动更新的安全阀：新 Pod 未 Ready 就不会有旧 Pod 被杀
- 没有 requests/limits 的 Pod 属于 BestEffort QoS，资源紧张时最先被驱逐

## Q&A

**Q1: maxSurge / maxUnavailable 生产上怎么选？**
按"容量敏感度"决策：面向用户的无状态服务求稳，用 `maxSurge=1, maxUnavailable=0`（容量永不下降，代价是多占一个副本的资源）；批处理或资源紧张的内部服务可用 `maxSurge=0, maxUnavailable=1`（省资源，代价是发布期间容量先降后升）。无论怎么配，都要配 readinessProbe——否则"Ready"没有语义，两个参数的约束形同虚设。

**Q2: Deployment 不能管理哪类工作负载？**
有状态应用。Deployment 的 Pod 是无身份的（名字随机、可互相替换、无稳定存储和网络标识），有状态应用应该用 **StatefulSet**（稳定 hostname、有序启停、每副本独立 PV，见 lab 08）；此外守护进程类用 DaemonSet（lab 07）、单次任务用 Job（lab 06）。
