# 08 · StatefulSet：稳定标识、独立存储与有序编排

> Deployment 假设所有 Pod **可互换**——挂了随便起一个补上。这对无状态服务成立，对数据库、消息队列是灾难。StatefulSet 管的不是"数量"，而是"**谁是谁**"。读完本篇，你将理解"序号即身份"如何带来稳定的域名、存储与顺序，并用一套模拟 MySQL 主从亲眼验证。

## Background

用 Deployment 跑数据库会遇到三个无解的问题。第一是身份：Deployment 重建的 Pod 名带随机后缀（`web-7d9f6b-x2k9p`），MySQL 主库必须一直"是"主库，重建后身份就变了——谁来当主、从库连谁，全乱了。

第二是存储：每个实例要自己的数据目录，且重建后必须**重新挂回原来那块盘**，而 Deployment 的副本要么共享一个 PVC（PersistentVolumeClaim，持久卷申请单——Pod 用它向集群要一块可挂载的"盘"，互相踩数据），要么手工建 N 个。

第三是顺序：主库先就绪、从库再启动，缩容先删从库最后删主库——Deployment 的副本是并行、无序的。

这三个需求的共性是"实例有身份且身份承载语义"。StatefulSet 为此而生：稳定网络标识 + 每副本独立持久卷 + 有序的部署/扩缩容。

## What

StatefulSet 为有状态应用提供三大保证：**稳定的网络标识 + 每副本独立持久卷 + 有序的部署/扩缩容**。

一句话心智模型：**序号即身份**——Pod 名 `web-N` 固定，带来三样东西固定：域名固定（Headless Service）、存储固定（volumeClaimTemplates → `data-web-N`）、顺序固定（正序建、逆序删、更新从最大序号开始）。

但与"给 Pod 起个固定名字"不同的是，这三样固定是控制器保证并联动维护的：删掉 web-1，重建的同名 Pod 会自动绑回原来那块盘。

与 Deployment 的镜像面对照：

| 维度 | Deployment | StatefulSet |
|------|-----------|-------------|
| Pod 名 | 随机后缀，重建即变 | `web-0/1/2` 固定，重建不变 |
| Pod DNS | 无独立域名（VIP 随机转发） | `web-N.svc.ns.svc.cluster.local` |
| 需配 Service | 普通 Service（可选） | **必须 Headless Service**（`serviceName`） |
| 存储 | 共享 PVC 或手工 N 个 | volumeClaimTemplates 自动生成每副本 PVC |
| 创建顺序 | 并行、无序 | 正序 0→1→2（前一个 Ready 才下一个） |
| 删除顺序 | 无序 | 逆序 2→1→0 |
| 滚动更新 | 无序替换，maxSurge/maxUnavailable | 逆序（先最大序号），partition 金丝雀 |
| 删除后 PVC | — | **保留**，需手工清理 |
| 适用场景 | 无状态（web/API） | 数据库、MQ、分布式存储 |

## When to Use

典型场景：MySQL / PostgreSQL 主从集群（按名连主库、每实例独立盘）；Kafka / ZooKeeper 等需要稳定成员列表的中间件；需要"缩容再扩容数据还在"的任何服务。

何时不用：无身份诉求的普通服务（StatefulSet 的有序性会让发布变慢）；仅仅是"想挂个盘"的无状态副本（Deployment 挂同一个卷即可）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| Deployment + PVC | 副本无身份，共享或手工建卷 | 无状态 + 只读共享数据 |
| StatefulSet | 序号即身份，VCT 每副本独立卷 | 有状态、身份承载语义 |
| Operator（如 MySQL Operator） | 领域运维自动化 | 需要备份/故障转移等运维能力时（见 operators/02） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/08_statefulset
./statefulset.sh apply    # 创建并 watch 有序创建：web-0 Ready 前不会有 web-1
./statefulset.sh dns      # nslookup 验证每个 Pod 的稳定域名
./statefulset.sh pvc      # 查看 volumeClaimTemplates 生成的 data-web-0/1/2
./statefulset.sh stable   # 删掉 web-1：同名复活、重挂同一个 PVC
./statefulset.sh scale    # 扩到 5（正序）再缩回 3（逆序），观察 PVC 保留
./statefulset.sh clean    # 删 StatefulSet 后需手工删 PVC
```

成功判据：`apply` 时 web-0 完全 Ready 后才出现 web-1（严格串行）；`stable` 步骤删掉 web-1 后同名 Pod 重建并重新绑定 `data-web-1`；`clean` 后 `kubectl get pvc` 仍能看到 `data-web-*`（设计如此）。具体输出以实际运行为准。

诚实预期：`apply` 时会看到严格串行的创建节奏（web-0 完全 Ready 后才出现 web-1）；`clean` 之后 `kubectl get pvc` 仍能看到 `data-web-*`——这是设计如此，不是没删干净。

## How It Works

**稳定网络标识：Headless Service + Pod DNS**：StatefulSet 必须配一个 `clusterIP: None` 的 Headless Service（通过 `serviceName` 关联）。

普通 Service 的 VIP（虚拟 IP：所有副本共享的一个入口地址）由 kube-proxy（每个节点上把 Service 地址转发到 Pod 的组件）随机转发，你**无法指定连哪一个**；Headless 不分配 VIP，DNS 为每个 Pod 注册独立 A 记录：

```
web-0.mysql-h.default.svc.cluster.local   -> web-0 的 Pod IP
web-1.mysql-h.default.svc.cluster.local   -> web-1 的 Pod IP
```

域名构成是 `<Pod名>.<Service名>.<命名空间>.svc.cluster.local`。Pod 重建后哪怕 IP 变了，域名不变——从库靠它稳定连主库，客户端才能"按名"连主库写、连从库读。

**独立存储：volumeClaimTemplates**：Deployment 的 Pod 模板只能引用现成的 PVC（所有副本共享）；

StatefulSet 在模板外声明 **PVC 模板**，控制器为每个 Pod 生成专属 PVC（`PVC 名 = <模板名>-<Pod名>`，即 `data-web-0 / data-web-1 / data-web-2`）。PVC 生命周期：

- Pod 删除重建后，**重新绑定同名 PVC**，拿回原来的数据——"稳定持久化标识"
- 缩容只删 Pod，**PVC 保留**；再扩容回来，新的 web-2 复用 data-web-2 里的旧数据
- **删除 StatefulSet 本身也不删 PVC**，必须手工 `kubectl delete pvc`——宁可麻烦也不丢数据

演示细节：initContainer 与主容器都通过 `subPath` 挂同一 PVC 的不同子目录（`mysql/` 放数据、`prev/` 模拟上一成员数据），否则 MySQL 检测到目录非空会拒绝初始化。

**有序性**：默认 `podManagementPolicy: OrderedReady` 下——

- **创建/扩容**：按序号正序（0→1→2），web-0 Ready 之前不创建 web-1——保证从库启动时主库已就绪。initContainer 天然串行（成功一个才跑下一个），与 OrderedReady 正好组成"链式依赖"：web-N 启动前从 `web-(N-1)` 克隆数据（模拟 MySQL 从库冷初始化）
- **缩容/删除**：按序号逆序（2→1→0），先删从库、最后删主库；被删副本的 PVC 保留
- **滚动更新**：同样从最大序号开始（先 web-2 最后 web-0），与 Deployment 相反；`updateStrategy.rollingUpdate.partition` 可做金丝雀——`partition=2` 只发 web-2，验证后降为 0 全量。比 Deployment 的 maxSurge 粒度粗，但身份可控

`Parallel` 策略可以像 Deployment 一样并行创建/删除，适合副本无依赖的场景，但**不影响滚动更新仍然逆序**。

## Pitfalls & Q&A

踩坑清单：

- 删 StatefulSet 后 PVC 残留是设计行为，清理要手工 `kubectl delete pvc`。
- MySQL 数据目录非空拒绝初始化：多个容器共享一个 PVC 时必须用 subPath 分子目录。
- 忘配 Headless Service：Pod 域名不生成，"按名连主库"直接失效。

**Q1: 缩容再扩容，新 Pod 拿到旧成员的数据——这是 feature 还是坑？**

两者都是，取决于你是否预期它。当 feature 用：从库冷初始化可以直接"扩容回来"复用旧数据，省掉一次全量克隆；当坑防：如果你以为扩容得到的是"干净的新成员"，旧数据里的残留状态（比如还记着旧主库的复制位点）会带来隐蔽故障。需要干净成员时，扩容前先 `kubectl delete pvc data-web-N`。

**Q2: 什么时候看似需要 StatefulSet、其实 Deployment 就够？**

判断标准是"身份是否承载语义"：只有当应用要**按名寻址特定实例**（主从、选主）、或**数据必须跟着身份走**（每实例独立盘且重建要挂回原盘）时才需要 StatefulSet。仅仅是"想挂个盘"的无状态副本（比如共享只读模型文件），Deployment 挂同一个 PVC/卷即可，不必引入有序管理的复杂度。
