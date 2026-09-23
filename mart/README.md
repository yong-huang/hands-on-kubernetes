# mini-mart：Kubernetes 微服务开发动手系列

> `docs/microservices.md` 清单的落地代码库。10 个项目共同生长为一个迷你电商系统：商品（Python/FastAPI）、订单（Go）、库存（Python）、通知（Go 消费者）+ API 网关，全部跑在本机 kind 集群的 `mart` 命名空间里——每个项目给 mini-mart 贡献一块能力，项目 10 全链路压测收口。

## What

mini-mart 是一个跑在 kind 上的完整微服务系统：四个微服务（Go/Python 混合栈）+ API 网关 + Kafka + 双 PostgreSQL。一句话心智模型：**10 个实验共同生长一个系统**——不是 10 个孤例，而是每篇给同一个电商加一块拼图：项目 1、2 铺服务和跨语言 gRPC 通信，3-6 补核心模式（热加载、弹性容错、事件驱动、Saga），7-9 接线可观测与交付，10 压测收口。

代码布局（`api/proto` 是跨语言契约的单一事实来源，`api/gen` 生成勿手改）：

```
mart/
├── api/proto/mart/v1/   # Protobuf 契约
├── api/gen/             # 生成代码（Go module / Python）
├── services/            # 微服务代码，每个服务一个目录
├── deploy/              # K8s 清单，按服务分目录
├── scripts/             # NN_xxx.sh：每个项目一个演示+验收脚本
└── tests/               # k6 压测、混沌实验
```

## Why

学微服务最容易犯的错是"每个概念各写一个 hello world"——熔断在一个项目里、消息队列在另一个项目里，彼此不认识，最后还是不会组装真实系统。mini-mart 反过来：所有模式都长在同一个电商上，后一篇在前一篇的系统上叠加，熔断保护的就是真实的 order → product 调用，Saga 补偿的就是真实的订单库存。全部本机 kind 可跑、零云依赖（项目 9 默认 GitHub Actions 免费额度，附离线 fallback），Go + Python 双语言栈覆盖跨语言协作的真实摩擦。

## How

```bash
cd mart
./scripts/01_product_k8s.sh all      # 构建部署商品服务并观察
./scripts/01_product_k8s.sh verify-rolling    # 验收①：滚动更新零中断
./scripts/01_product_k8s.sh verify-readiness  # 验收②：坏探针自动中止
./scripts/01_product_k8s.sh clean
```

每个项目一个 `scripts/NN_xxx.sh`（演示 + 验收一体）：

| # | 项目 | 脚本 | 状态 |
|:--|:--|:--|:--|
| 1 | Python 商品服务上 K8s（探针/优雅关闭） | `scripts/01_product_k8s.sh` | ✅ |
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

## Deep Dive

**下单链路**是整个系统的主线，同步 Saga + 异步事件两条通道配合：请求带 JWT 进 Kong API 网关（认证/限流/按 header 灰度），经 Ingress 路由到 order（Go）；order 通过 gRPC 同步调用 product（查价，带超时/熔断）和 inventory（锁库存，失败走 Saga 补偿事务回滚订单）；订单落库后发 `order.created` 事件到 Kafka（KRaft），notification（Go 消费者）异步消费发通知。order 与 product 各自持有独立的 PostgreSQL——数据库按服务拆分是 Saga 的前提。

**可观测性横切所有服务**：OTel Collector 汇聚 traces/metrics/logs 到 Prometheus + Grafana 与 Jaeger，一次下单请求的完整链路可以在 trace 里逐跳定位（见 lab 07 与 hands-on-kubernetes 的 lab 25）。项目 10 用 k6 压测 + Chaos Mesh 混沌实验验证以上全部机制在压力下依然成立。

## Q&A

**Q1: 为什么每个服务一个独立目录 + 独立数据库，而不是共享一个库？**
数据库按服务拆分是微服务自治的底线：schema 变更不跨服务协调、故障不传染、Saga 补偿才有意义（各管各的事务）。共享数据库的"微服务"只是分布式的单体——服务拆了、数据耦合还在，任何一个表的变更都会波及所有服务。

**Q2: 项目之间是独立的还是必须按顺序做？**
强烈建议按顺序：每个项目在 `deploy/` 和 `services/` 里沉淀的产物是后续项目的依赖——项目 2 的 gRPC 契约依赖项目 1 的 product 服务，项目 4 的熔断保护项目 2 的调用，项目 6 的 Saga 建立在前五项的地基上。单独挑着做某一项时，`clean` 掉前面的资源会导致验收不通过。

**Q3: 想只跑某个项目不跑全系统，可以吗？**
可以。每个 `NN_xxx.sh` 自带 `all` / 验收 / `clean` 子命令，按项目自举所需的最小依赖集（如项目 4 会顺带部署 product + order）。`regression.sh` 则把全部验收串起来跑一遍——改了共享代码（如 proto）之后先跑它，防止破坏前面项目的验收。
