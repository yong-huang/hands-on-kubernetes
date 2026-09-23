# 03 · Redis 主从 Operator：多副本拓扑编排

> 第一个**多副本拓扑** Operator：一个 `RedisCluster` CR 声明从库数量，Controller 编排 1 主（Deployment，可写）+ N 从（StatefulSet，启动即 replicaof 主库），主写从读、扩缩容全自动——主从复制不写一行配置文件。

## What

一个 `RedisCluster` CR 长这样：

```yaml
apiVersion: cache.example.com/v1
kind: RedisCluster
metadata: { name: redis-demo }
spec:
  replicas: 2              # 从库数量（主库固定 1）
  image: redis:7-alpine
```

apply 后：master Deployment + master Service + replicas StatefulSet 自动出现；从库启动命令自带 `--replicaof redis-demo-master 6379`，连上主库自动全量同步。一句话心智模型：**拓扑即 CR**——主从关系不是配置出来的，是 Controller 声明出来的，`INFO replication` 里 `master_link_status:up` 就是复制健康的直接证据。

## Why

手工搭 Redis 主从要维护配置文件里的 `replicaof` 地址、逐个启动从库、扩容时再改一遍——拓扑信息散落在每个节点的配置里，改一次主库地址就要动所有从库。Operator 把拓扑收进一个 CR：从库的启动命令由 Controller 按 CR 动态生成（配置跟镜像走，拓扑跟 Controller 走），扩缩从库变成改一个数字。

## How

```bash
cd operators/03_redis_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller
kubectl apply -f config/samples/cache_v1_rediscluster.yaml
```

主写从读验证：

```bash
kubectl exec deploy/redis-demo-master -- redis-cli SET hands-on k8s-operator
kubectl exec redis-demo-replicas-0 -- redis-cli GET hands-on      # → "k8s-operator"
kubectl exec redis-demo-replicas-0 -- redis-cli INFO replication | grep -E "role|master_link"
```

扩从库：

```bash
kubectl patch rediscluster redis-demo --type merge -p '{"spec":{"replicas":2}}'
```

## Deep Dive

Controller 编排主从拓扑：master Deployment（可写）+ replicas StatefulSet（N 个只读从库）。从库通过 master Service 找到主库完成 `psync` 全量 + 增量同步。

三个子资源同一 CreateOrPatch 模式，关键差异在从库的启动命令——拓扑信息由 Controller 注入：

```go
Command: []string{
    "redis-server",
    "--replicaof", rc.Name + "-master." + rc.Namespace + ".svc.cluster.local", "6379",
    "--replica-read-only", "yes",
},
```

- 主库与从库是**两个独立工作负载**：master 用 Deployment（单副本，固定 1），replicas 用 StatefulSet（有序扩缩、稳定序号）；
- Owns() 三路订阅：master Deployment / master Service / replicas STS 任一被手改都会触发调谐拉回（实测：scale STS 3→自动回 2）。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR → master Deployment/Service + replicas STS 自动出现 | ✅ |
| 主写从读：SET master → GET replica 返回同值 | ✅ |
| INFO replication：role:slave · master_link_status:up | ✅ |
| CR replicas 1→2，新从库自动加入并同步同一键 | ✅ |
| 手改 STS 副本=3，Owns 触发自动拉回 2 | ✅ |
| 删 CR 级联清理（master Service 漏挂 ownerRef 的 bug 已修） | ✅ |

## Q&A

**Q1: 为什么主库用 Deployment、从库用 StatefulSet？**
主库单副本、无身份需求，Deployment 够用；从库用 STS 是为了稳定序号 + 有序扩缩——虽然本例从库无持久化，但拓扑上"每个从库有身份"为后续加持久化、读 VIP 留了口子。

**Q2: replicaof 为什么写在启动命令而不是配置文件里？**
容器最佳实践——配置跟镜像走，拓扑跟 Controller 走。写死在 ConfigMap/镜像里的 `replicaof` 地址在 CR 改名、换 namespace 时全部失效；启动命令由 Controller 在 Reconcile 时按 CR 动态生成，主库地址永远正确。

**Q3: 从库可以随便缩容吗？主库呢？**
未开持久化的从库是纯内存副本，缩容即丢弃，主库还在数据就在——随便缩。主库不行：单点缩掉就是服务中断，缩容/删除前必须先做故障转移（本项目未覆盖，生产用 Sentinel 或 Redis Cluster 补齐这一层）。
