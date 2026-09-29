# mini-mart：Kubernetes 微服务开发动手系列

> `docs/microservices.md` 清单的落地代码库。10 个项目共同生长为一个迷你电商系统：商品（Python/FastAPI）、订单（Go）、库存（Python）、通知（Go 消费者）+ API 网关，全部跑在本机 kind 集群的 `mart` 命名空间里，每个项目给 mini-mart 贡献一块能力，项目 10 全链路压测收口。
> 术语：kind——用 Docker 容器模拟节点、本地拉起 K8s 集群的工具；namespace——集群内的逻辑隔离分组。

## Background

学微服务的常见路径是"一个概念一个 demo"：熔断在一个项目里、消息队列在另一个项目里，彼此不认识。demo 做完还是不会组装真实系统——真实系统的问题是"熔断要保护真实的跨服务调用、Saga 要补偿真实的订单库存"，孤例永远练不到组装。

mini-mart 反过来：所有模式都长在同一个电商上，后一篇在前一篇的系统上叠加。它从 `docs/microservices.md` 清单生长而来，10 个项目串成一条"从单服务上线到全链路压测"的完整路径。

## What

mini-mart 是一个跑在 kind 上的完整微服务系统：四个微服务（Go/Python 混合栈）+ API 网关 + Kafka + 双 PostgreSQL。

一句话心智模型：**10 个实验共同生长一个系统**——可以把这个系列想象成盖一栋楼；但和盖楼不同的是，每期"施工"都要保证已建成的部分照常营业（前面项目的验收持续可复跑）。

| 目录 | 职责 |
|---|---|
| `api/proto/mart/v1/` | Protobuf 契约（跨语言的单一事实来源） |
| `api/gen/` | 生成代码（Go module / Python），勿手改 |
| `services/` | 微服务代码，每个服务一个目录 |
| `deploy/` | K8s 清单，按服务分目录 |
| `scripts/` | NN_xxx.sh：每个项目一个演示+验收脚本 |
| `tests/` | k6 压测、混沌实验 |

## When to Use

典型场景：学完 labs 基础实验后，想在真实系统形态里练微服务模式；需要一个能照着搭的"Go + Python 双语言 + gRPC（跨语言的高性能 RPC 框架）+ Kafka（分布式消息队列）+ Saga"参考实现；团队想沉淀一套可回归验收的微服务脚手架。

Saga（分布式事务的补偿模式）的完整含义：每步正向操作配一个补偿操作，任一步失败就逆序执行补偿——How It Works 的下单链路有它的具体例子。

何时不用：只想快速理解单个概念（对应 labs 单篇更聚焦）；目标环境是云托管服务为主、不走自建 K8s（本系列的清单与脚本全部面向 kind）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 单概念 demo | 短平快、互不衔接 | 快速理解某个组件 |
| mini-mart（本系列） | 系统生长式、带验收脚本 | 学组装与工程化 |
| 生产级脚手架（go-zero 等） | 开箱即用 | 直接启动业务开发 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../labs/01_setup_env/README.md)）；本机 docker 可构建镜像。

```bash
cd mart
./scripts/01_product_k8s.sh all      # 构建部署商品服务并观察
./scripts/01_product_k8s.sh verify-rolling    # 验收①：滚动更新零中断
./scripts/01_product_k8s.sh verify-readiness  # 验收②：坏探针自动中止
./scripts/01_product_k8s.sh clean
```

成功判据：`verify-rolling` 收尾输出「非 2xx 响应 0」即滚动更新零中断（请求数等具体数字每次不同）；`verify-readiness` 演示坏探针被自动中止（以实际运行为准）。

诚实预期：项目 1 只部署 product 单服务（系统的第一块砖）；后续项目按序叠加，`clean` 清掉的是该项目引入的资源。

## How It Works

**下单链路**是整个系统的主线，同步 Saga + 异步事件两条通道配合：

1. 同步调用：请求带 JWT 进 Kong API 网关（认证/限流/按 header 灰度），经 Ingress（集群的七层入口路由）到 order（Go）；order 通过 gRPC 调 product 查价（带超时/熔断）、调 inventory 锁库存，失败走 Saga 补偿事务回滚订单。
2. 异步事件：订单落库后发 `order.created` 事件到 Kafka（KRaft 模式：用 Kafka 自带的共识机制替代 ZooKeeper 管理元数据），notification（Go 消费者）异步消费发通知。
3. 数据隔离：order 与 product 各自持有独立的 PostgreSQL——数据库按服务拆分是 Saga 的前提。

**可观测性横切所有服务**：OTel Collector（OpenTelemetry 的采集组件，接收各服务上报的遥测数据再统一转发）汇聚 traces/metrics/logs 到 Prometheus + Grafana 与 Jaeger，一次下单请求的完整链路可以在 trace 里逐跳定位（labs/25 是这套机制的原理篇）。项目 10 用 k6 压测 + Chaos Mesh 混沌实验验证以上全部机制在压力下依然成立。

每个项目一个 `scripts/NN_xxx.sh`（演示 + 验收一体）：

| # | 项目 | 脚本 | 状态 |
|:--|:--|:--|:--|
| 1 | Python 商品服务上 K8s（探针＝对容器的定期健康检查，失败则摘流量或重启；优雅关闭） | `scripts/01_product_k8s.sh` | ✅ |
| 2 | Go 订单服务 + 跨语言 gRPC | `scripts/02_order_grpc.sh` | ✅ |
| 3 | 配置与密钥的应用侧热加载 | `scripts/03_config_hotreload.sh` | ✅ |
| 4 | 弹性容错三件套（熔断/重试/超时） | `scripts/04_resilience.sh` | ✅ |
| 5 | 事件驱动 Kafka 异步解耦 | `scripts/05_kafka_events.sh` | ✅ |
| 6 | 数据库拆分与 Saga 补偿事务 | `scripts/06_saga_db.sh` | ✅ |
| 7 | OpenTelemetry 全链路埋点 | `scripts/07_otel_tracing.sh` | ✅ |
| 8 | API 网关（认证/限流/灰度） | `scripts/08_gateway.sh` | ✅ |
| 9 | CI/CD 与 GitOps 交付 | `scripts/09_cicd.sh` | ✅ |
| 10 | 全链路压测 + 混沌实验 | `scripts/10_load_chaos.sh` | ✅ |

环境约定：

- 集群：kind（本机单节点），命名空间 `mart`
- 镜像：本机 docker 构建 → `kind load` 进集群，不走 registry
- 宿主机访问：NodePort `30880` 起（30080 被别的 demo 占用），节点 IP 自动探测
- NodePort 分配：product http=30880, product grpc=30881, order http=30882
- 脚本兼容 macOS 自带 bash 3.2（避免 `$var` 后紧跟全角标点）

## Pitfalls & Q&A

踩坑清单：

- 跳序做项目：后置项目的验收依赖前置项目的资源，`clean` 掉前置会导致验收不通过。
- 共享代码（如 proto）改动后只验当前项目：跑 `regression.sh` 把全部项目验收串一遍，防止破坏前面项目。
- NodePort 用 30080：被仓库其他 demo 占用，本系列从 30880 起。

**Q1: 为什么每个服务一个独立目录 + 独立数据库，而不是共享一个库？**
数据库按服务拆分是微服务自治的底线：schema 变更不跨服务协调、故障不传染、Saga 补偿才有意义（各管各的事务）。共享数据库的"微服务"只是分布式的单体——服务拆了、数据耦合还在，任何一个表的变更都会波及所有服务。

**Q2: 项目之间是独立的还是必须按顺序做？**
强烈建议按顺序：每个项目在 `deploy/` 和 `services/` 里沉淀的产物是后续项目的依赖——项目 2 的 gRPC 契约依赖项目 1 的 product 服务，项目 4 的熔断保护项目 2 的调用，项目 6 的 Saga 建立在前五项的地基上。

单独挑着做某一项时，`clean` 掉前面的资源会导致验收不通过。

**Q3: 想只跑某个项目不跑全系统，可以吗？**
可以。每个 `NN_xxx.sh` 自带 `all` / 验收 / `clean` 子命令，按项目自举所需的最小依赖集（实测：项目 4 的脚本会自己 `kubectl apply` product 和 order 的清单）。`regression.sh` 则把全部验收串起来跑一遍——改了共享代码之后先跑它。
