# 🛒 mini-mart：Kubernetes 微服务开发动手系列

`microservices.md` 清单的落地代码库。10 个项目共同生长为一个迷你电商系统：
商品（Python/FastAPI）、订单（Go）、库存（Python）、通知（Go 消费者）+ API 网关，
全部跑在本机 kind 集群的 `mart` 命名空间里。

## 系统架构

四个微服务（Go/Python 混合栈）+ API 网关 + Kafka + 双 PostgreSQL，全部运行在 kind 集群的 `mart` 命名空间：

![mini-mart 微服务架构](images/mart.architecture.svg)

**下单链路**（同步 Saga + 异步事件）：

![下单链路时序](images/checkout.sequence.svg)

> 🌐 **交互版**（可点击节点/连线、双主题、缩放搜索）：
> [系统架构图](images/mart.architecture.html) ·
> [下单链路时序图](images/checkout.sequence.html)
> （图源 JSON 同目录，archify showcase 质量校验通过）

## 目录结构

```
mart/
├── api/proto/mart/v1/   # Protobuf 契约（单一事实来源）
├── api/gen/             # 生成代码（Go module / Python），勿手改
├── services/            # 微服务代码，每个服务一个目录
├── deploy/              # K8s 清单，按服务分目录
├── scripts/             # NN_xxx.sh：每个项目一个演示+验收脚本
└── tests/               # k6 压测、混沌实验
```

## 项目进度

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

## 环境约定

- 集群：kind（本机单节点），命名空间 `mart`
- 镜像：本机 docker 构建 → `kind load` 进集群，不走 registry
- 宿主机访问：NodePort `30880` 起（30080 被别的 demo 占用），节点 IP 自动探测
- NodePort 分配：product http=30880, product grpc=30881, order http=30882
- 脚本兼容 macOS 自带 bash 3.2（避免 `$var` 后紧跟全角标点）

## 快速开始

```bash
cd mart
./scripts/01_product_k8s.sh all      # 构建部署商品服务并观察
./scripts/01_product_k8s.sh verify-rolling    # 验收①：滚动更新零中断
./scripts/01_product_k8s.sh verify-readiness  # 验收②：坏探针自动中止
./scripts/01_product_k8s.sh clean
```
