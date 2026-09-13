# 🛒 Kubernetes 微服务开发 10 小项目学习清单 · Todo List

> 通过 10 个小项目（每项目 100-350 行代码/配置）掌握在 Kubernetes 上开发生产级微服务：Go + Python 双语言栈，从单服务上线走到全链路压测
> 本机 kind 集群可跑、零云依赖（项目 9 默认 GitHub Actions 免费额度，附离线 fallback）
> 串联机制：全部项目共同生长为 **mini-mart 迷你电商**（商品/订单/库存/通知 4 服务 + API 网关），⛓️ 集成点接线可观测与交付，项目 10 🏁 终极串联压测收口
> 预计周期：6 周（每天 3-4 小时）

---

## 🏗️ 终极蓝图（项目 10 完成时的 mini-mart）

```
  用户(App/curl)
       │ JWT
       ▼
┌──────────────────┐
│  Kong API 网关    │  认证 · 限流 · 按 header 灰度
└────────┬─────────┘
         │ Ingress/GatewayAPI
   ┌─────┴──────┬──────────────┐
   ▼            ▼              │
┌────────┐  ┌─────────┐        │
│ order  │  │ product │◀───┐   │
│  Go    │  │ Python  │    │   │
└───┬────┘  └────┬────┘    │   │
    │ gRPC(查价/超时/熔断)   │   │
    │ Saga(补偿事务)        │   │
    ▼            ▼         │   │
┌───────────┐  各自独立 Postgres │
│ inventory │              │   │
│  Python   │              │   │
└───────────┘              │   │
    │ order.created        │   │
    ▼                      │   │
┌───────────┐   ┌──────────┴───┴─────────────┐
│  Kafka    │   │ OTel Collector             │
│ (KRaft)   │   │ → Prometheus + Grafana     │
└─────┬─────┘   │ → Jaeger                   │
      ▼         └────────────────────────────┘
┌─────────────┐      ▲
│ notification│      │ traces/metrics/logs
│  Go 消费者   │──────┘
└─────────────┘      ▲ k6 压测 / Chaos Mesh 混沌（项目 10）
```

每个项目给 mini-mart 贡献一块：项目 1、2 铺服务和通信，3-6 补核心模式，7、9 ⛓️ 接线可观测与交付，10 🏁 压测收口。

---

## 🤖 AI 辅助提示词速查

| 场景 | 提示词 |
|:---|:---|
| **开始一个新项目** | `我要开始 Kubernetes 微服务项目「[名称]」，目标是 [目标]。请给我完整 [Go/Python] 代码约 [行数] 行，跑在本机 kind 集群上，包含 K8s 清单和验收命令。只输出代码。` |
| **服务间调用排障** | 我的 order 服务调用 product 服务出现 [现象]，日志/报错：[粘贴]。请按 DNS 解析、超时配置、序列化、熔断状态四个方向定位根因并给修复。 |
| **分布式追踪分析** | 这是 Jaeger 中一次下单请求的 trace：[粘贴 JSON]。请计算各 span 耗时占比，指出瓶颈在哪一跳。 |
| **消费积压/消息问题** | 我的 Kafka 消费者组 [组名] 出现 [积压/重复消费/rebalance 风暴]，describe 输出：[粘贴]。请分析原因并给参数调整方案。 |

---

## 📊 总进度

进度：████████████████████ 10/10 (100%)

| 阶段 | 项目数 | 已完成 |
|:---|:---:|:---:|
| 第一阶段：单服务地基与跨语言通信 | 2 | 2 |
| 第二阶段：微服务核心模式 | 4 | 4 |
| 第三阶段：平台能力·应用视角 | 3 | 3 |
| 第四阶段：串联压测收口 | 1 | 1 |
| **合计** | **10** | **10** |

---

## 🗂️ 第一阶段：单服务地基与跨语言通信（项目 1-2）

> **目标**：能把任意 Go/Python 服务规范化地部署上 K8s（探针、优雅关闭、资源约束齐全），并实现跨语言 REST + gRPC 互调

### [x] 项目 1：Python 商品服务上 K8s（mini-mart 第一块砖）✅ 2026-09-11

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~200 行（Python ~120 + YAML ~50 + Dockerfile ~30）|
| **核心知识点** | FastAPI、多阶段构建小镜像、liveness/readiness 探针的代码实现、SIGTERM 优雅关闭（停止收新请求→排空在途请求）、requests/limits |
| **产出模块** | `services/product/`（FastAPI 商品服务）、`deploy/product/` |
| **技术栈** | Python 3.14 + FastAPI（本机 ✅ 实测）、python slim 多架构基础镜像 |
| **验收标准** | ① `kubectl set image` 触发滚动更新，同时 k6 以 50 rps 持续打 `/products`，非 2xx 响应数为 0（优雅关闭生效）；② 故意把 readinessProbe 端口改错，`kubectl rollout status` 停滞且自动中止，`kubectl rollout undo` 恢复 |
| **⚠️ 风险** | 无。全链路本机可跑 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「Python 商品服务上 K8s」。请给我完整代码约 200 行：FastAPI 商品服务（GET /products、GET /products/{id}、GET /healthz 和 /readyz 探针端点，readyz 可用一个内存开关控制）、捕获 SIGTERM 后先摘流量再退出的优雅关闭逻辑、多阶段 Dockerfile（最终镜像 <100MB）、Deployment+Service YAML（liveness/readiness/startupProbe、requests/limits、maxSurge=1 maxUnavailable=0）。附两条验收命令：滚动更新零失败验证、readiness 卡住自动中止验证。只输出代码。`

**完成日期**：2026-09-11
**踩坑记录**：代码在 `mart/services/product/`。① 本机 kind 集群名是 `kind` 而非上下文名 `kind-kind`，`kind load` 要用 `--name kind`；② NodePort 30080 被 default/myapp-svc 占用，系列统一改用 30880 起；③ macOS 自带 bash 3.2 的 UTF-8 支持差，脚本里 `$var` 后紧跟全角标点会被并进变量名，写 `${var}` 规避；④ node 地址的 jsonpath 类型是 `InternalIP` 不是 `Internal-IP`。两条验收全过：2253 请求零失败 / 坏探针 60s 自动中止 + undo 恢复。

---

### [x] 项目 2：Go 订单服务 + 跨语言 gRPC 通信 ✅ 2026-09-11

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~300 行（Go ~200 + proto ~30 + YAML ~50）|
| **核心知识点** | protoc 生成 Go/Python 桩代码、Go gRPC server/client、商品服务加 gRPC 接口、客户端超时与重试、grpcurl 调试、延迟注入调试端点 |
| **产出模块** | `services/order/`（Go 订单服务，下单时经 gRPC 查商品价格）、`api/proto/mart/v1/*.proto` |
| **技术栈** | Go 1.26（✅ 实测）、protoc（✅ 实测已装）、grpcurl（❌ 未装 → `brew install grpcurl`）|
| **前置** | 项目 1 |
| **验收标准** | ① `grpcurl -plaintext <product-svc>:50051 list` 列出商品服务与全部 RPC；② 下单 curl 返回 201 且订单价格为 gRPC 实时查询值（改商品价格后再下单，新订单价格跟着变）；③ 商品服务 `/fault?delay=2s` 注入延迟时，下单在 500ms 客户端超时内返回 504，请求不悬挂 |
| **⚠️ 风险** | 无。延迟注入端点本项目就要实现（项目 4 会复用扩展）|

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「Go 订单服务 + 跨语言 gRPC」。请给我完整代码约 300 行：mart/v1 product.proto（GetProduct RPC）与 order.proto（CreateOrder/GetOrder），protoc 同时生成 Go 和 Python 桩；给现有 Python 商品服务加 gRPC server（同一 Pod 双容器或双端口）；Go 订单服务 POST /orders 时经 gRPC 查价格、带 500ms 超时与 1 次重试，内存存订单；商品服务加 /fault?delay=2s 调试端点。附 grpcurl 列出服务、下单、注入延迟验证超时三条验收命令。只输出代码。`

**完成日期**：2026-09-11
**踩坑记录**：代码在 mart/services/order 与 mart/api/proto。① protobuf gencode/runtime 版本法则：gencode 允许比 runtime 旧、反之报 VersionError，钉 grpcio-tools==1.66.2 解决；② 生成的 Python 桩按 proto 包名落目录 mart/v1，需把 app 目录插进 sys.path；③ gRPC 长连接 + Service 负载均衡会把客户端"钉"在单个 Pod 上，多副本内存态（改价、故障注入）必须 kubectl exec 逐副本改——项目 6 换真库后此坑消失；④ proto 里 service 与 message 同名会编译冲突。

---

## 🗂️ 第二阶段：微服务核心模式（项目 3-6）

> **目标**：落地四个微服务核心模式——配置热加载、弹性容错、事件驱动、跨库数据一致性

### [x] 项目 3：配置与密钥的应用侧热加载 ✅ 2026-09-11

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~150 行（Go + Python 各一份热加载组件）|
| **核心知识点** | ConfigMap/Secret volume 挂载与 kubelet 同步周期、fsnotify（Go）/watchdog（Python）监听符号链接原子替换、原子切换运行时配置、Secret 轮换不重启 |
| **产出模块** | `services/order/internal/configwatch/`、`services/product/app/configwatch.py`、两服务暴露 `GET /config` 当前生效配置 |
| **技术栈** | kubectl patch（✅）、K8s ConfigMap/Secret 卷（✅ 本机 kind 支持）|
| **前置** | 项目 1、2 |
| **验收标准** | ① `kubectl patch configmap` 把日志级别改 debug 后 90 秒内 `/config` 返回新值（kubelet 同步周期上限约 1 分钟，留余量），期间 Pod RESTARTS 计数不变；② 更新数据库密码 Secret 后应用日志显示用新密码重连成功，无任何重启 |
| **⚠️ 风险** | 热加载生效时间受 kubelet 同步周期约束（约 1 分钟），验收别写成秒级 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「配置与密钥的应用侧热加载」。请给我完整代码约 150 行：ConfigMap/Secret 以 volume 挂载到 order（Go）和 product（Python）服务，用 fsnotify/watchdog 监听 kubelet 的原子替换事件并线程安全地切换运行时配置，两服务暴露 GET /config 返回当前生效配置；附 Deployment 挂载 YAML。注意 kubelet sync 周期约 1 分钟，验收命令按 90 秒等待写。只输出代码。`

**完成日期**：2026-09-11
**踩坑记录**：本项目最大的坑是内存 OOM：watchdog 默认 inotify emitter 在 kind 节点内核上自旋泄漏（本地 Docker 复现不了，裸 Pod 定位到），换 PollingObserver 解决——kubelet 的 ..data 符号链接卷本来就不适合 inotify 语义；另外 root logger 打 DEBUG 会让 grpc._cython 对每次事件循环 poll 刷日志，热加载改日志级别时只改自己的 logger。kubelet 同步挂载卷有约 1min 抖动，验收窗口给到 240s。code 侧热加载组件在 mart/services/order/configwatch.go。

---

### [x] 项目 4：弹性容错三件套（熔断/重试/超时）✅ 2026-09-11

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~180 行 |
| **核心知识点** | 熔断器状态机（Closed→Open→Half-Open）、指数退避 + jitter 重试、超时预算逐层递减、并发隔离（bulkhead）、故障注入端点扩展 |
| **产出模块** | `services/order/internal/resilience/`（熔断包装的 gRPC client）、product 服务 `/fault?mode=500|delay` 注入端点 |
| **技术栈** | sony/gobreaker（Go）、tenacity（Python 备用）|
| **前置** | 项目 2 |
| **验收标准** | ① `/fault?mode=500` 注入 100% 失败：首个请求等满 500ms 超时，熔断 Open 后同类请求 <10ms 快速失败（对比日志时间戳）；② 日志完整出现 Closed→Open→Half-Open→Closed 状态迁移；③ 关闭注入 30 秒后订单错误率回到 0 |
| **⚠️ 风险** | 无 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「弹性容错三件套」。请给我完整代码约 180 行：用 sony/gobreaker 把 order 服务调 product 的 gRPC client 包上熔断器（5 次失败开断、30 秒后半开探测），重试策略为指数退避加 jitter 且总超时预算 500ms 内递减，扩展 product 的 /fault 端点支持 mode=500 和 mode=delay；熔断每次状态迁移打结构化日志。附三条验收命令：快速失败对比、状态迁移日志检查、恢复验证。只输出代码。`

**完成日期**：2026-09-11
**踩坑记录**：① 镜像同 tag 重建不会触发 rollout，apply 后要显式 rollout restart；② 两个 order 副本分流会稀释熔断计数，阈值从 5 降到 3 才稳定跳闸；③ 多 Pod 日志断言的 --since 窗口放宽到 15m；④ 故障注入失败后必须 clean，否则下次验收基线是坏的。代码：order 加 sony/gobreaker，product /fault 加 mode=500。

---

### [x] 项目 5：事件驱动：Kafka 异步解耦 ✅ 2026-09-11

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~250 行（Go 生产者 + Go 消费者 + 部署清单）|
| **核心知识点** | KRaft 模式 Kafka、Go 生产者/消费者组（franz-go）、订单事件 `order.created`、消费重试与 DLQ、幂等消费（去重表）|
| **产出模块** | `services/notification/`（Go 消费者：收到订单事件打"发送通知"日志 + 幂等去重）、`services/order/internal/events/`（生产者）、`deploy/kafka/` |
| **技术栈** | bitnami/kafka Helm chart（KRaft，⚠️ 开工探活 kind 上内存与 arm64；fallback：Redpanda chart，学习目标不变）|
| **前置** | 项目 2 |
| **⚠️ 风险** | Kafka 吃内存，建议 kind 集群 6G+ 余量；探活不过就换 Redpanda，概念完全通用 |
| **验收标准** | ① 下单后 5 秒内 notification 日志出现 order.created 及订单 ID；② 注入消费失败后消息重试 3 次落入 `orders.dlq` topic；③ 同一消息重复投递时幂等去重生效，"通知"只发一次 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「事件驱动 Kafka 异步解耦」。请给我完整代码约 250 行：bitnami/kafka chart 的 values（KRaft 单节点、适配 kind、资源限制收紧）、order 服务用 franz-go 在订单创建后发 order.created 事件、notification 服务消费组消费者 + 处理失败重试 3 次后写 orders.dlq、消费侧用订单 ID 做幂等去重。附三条验收命令：事件到达延迟、DLQ 落入、重复投递去重。只输出代码。`

**完成日期**：2026-09-11
**踩坑记录**：① docker.io 多架构镜像（含 provenance attestation）在 kind 里 ctr import 报 digest not found——本地 `FROM apache/kafka:4.0.0` 重建单平台镜像绕过；② Kafka Service 必须暴露 9093 controller 端口，且单节点 quorum voters 用 localhost（经 Service ClusterIP 自连踩 hairpin NAT）；③ 多副本订单服务内存 seq 各自计数导致订单号跨副本撞号，被幂等去重误杀——ID 加 Pod 名后缀；④ 消费快到与下单同秒完成，验收基线必须在下单前取，否则增量被算进 base；⑤ 本机 OrbStack 宿主机到 NodePort 时通时断，脚本交互全部改为集群内 Pod 中转；⑥ 全局 kubectl context 被并行会话反复切走，mart/kubeconfig-kind 钉死。三项验收通过：送达 / 3 次重试进 DLQ / 幂等去重。

---

### [x] 项目 6：数据库拆分与 Saga 补偿事务 ✅ 2026-09-11

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~300 行（全清单最重）|
| **核心知识点** | database-per-service（订单/库存各自 Postgres）、Saga 编排模式（order 当协调者）、补偿事务、订单状态机、幂等与悬挂事务处理 |
| **产出模块** | `services/inventory/`（Python 库存服务 + 独立 Postgres）、`services/order/internal/saga/`（下单 Saga：锁库存→建订单，失败自动补偿）|
| **技术栈** | PostgreSQL（bitnami chart，labs 08/16 已验证过 kind 可跑 ✅）|
| **前置** | 项目 2、5 |
| **⚠️ 风险** | 容量最大，允许拆两次会话完成；先做双库拆分，再补 Saga 状态机 |
| **验收标准** | ① 正常下单：orders 库新增 created 订单、inventory 库同步 -1，跨库一致；② 把库存置 0 再下单：订单自动转 cancelled、库存保持 0，两库均无 reserved/processing 中间态残留（psql 断言）；③ Saga 执行中 `kubectl delete pod` 杀掉 inventory，pod 恢复后 60 秒内订单收敛到确定终态，无悬挂 processing |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「数据库拆分与 Saga 补偿事务」。请给我完整代码约 300 行：inventory Python 服务（PostgreSQL 独立实例、reserve/release 接口、库存表）、order 服务把下单改成 Saga 编排（step1 reserve 库存 → step2 建订单，任一失败按逆序补偿、订单状态机 pending→created/cancelled）、两个 StatefulSet 各挂独立 PVC；用事务 ID 做幂等防悬挂。附三条验收命令：双库一致断言、库存不足补偿断言、杀 pod 后最终一致断言。只输出代码。`

**完成日期**：2026-09-11
**踩坑记录**：① psycopg3 的连接超时参数是 connect_timeout 不是 timeout；② Go 构建容器里 proxy.golang.org 频繁 EOF——`go mod vendor`（23MB）让镜像构建彻底离线，一劳永逸；③ saga 失败响应也要返回 JSON 订单号，否则验收脚本拿不到断言对象；④ 并行会话反复切走全局 kubectl context，已生成 mart/kubeconfig-kind 并在所有脚本里钉死；⑤ 验收③的精髓：reserve 按 order_id 幂等 + Saga 重试预算（10 次 × 2s）覆盖 Pod 重建窗口，杀 Pod 后订单自然收敛到 created。代码：mart/deploy/db/postgres.yaml（单实例双库）、mart/services/inventory/、mart/services/order/store.go。

---

## 🗂️ 第三阶段：平台能力·应用视角（项目 7-9）

> **目标**：站在应用开发者的视角用好平台能力——全链路可观测埋点、网关流量治理、多服务 GitOps 自动交付（平台栈本身 labs 13/23/25/28 已装过，本阶段专注"应用侧怎么接"）

### [x] ⛓️ 项目 7：OpenTelemetry 全链路埋点 ✅ 2026-09-12

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~150 行（OTel SDK 埋点 + Collector 配置）|
| **核心知识点** | OTel Go/Python SDK、W3C traceparent 跨 HTTP/gRPC/Kafka 传播、OTel Collector Pipeline、RED 指标暴露、trace 与日志关联 |
| **产出模块** | 四个服务的埋点改造、`deploy/otel/`（Collector + Jaeger + Prometheus/Grafana 复用 labs 23/25 清单）|
| **技术栈** | OpenTelemetry、Prometheus、Jaeger（⚠️ 当前 kind 集群监控栈已清空，开工先按 `labs/23_prometheus_grafana`、`labs/25_jaeger_tracing` 重装——labs 脚本已验证可跑）|
| **前置** | 项目 5、6（服务间调用 + 消息链路成型，trace 才有得看）|
| **验收标准** | ① Jaeger 中一次下单的 trace 同时包含 order/product/inventory/notification 四个服务的 span（Kafka 上下游 span 相连成一棵树）；② Grafana 按服务过滤能看到四服务各自的 QPS、P99 延迟、错误率曲线 |
| **⚠️ 风险** | 监控栈需重装（labs 脚本现成，~15 分钟）；埋点顺序建议 order → product，先打通 HTTP/gRPC 再补 Kafka |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「OpenTelemetry 全链路埋点」。请给我完整代码约 150 行：order/product/inventory（Python）与 order/notification（Go）接入 OTel SDK，HTTP/gRPC server、client 和 Kafka producer/consumer 全部自动或手动注入 W3C traceparent 上下文，业务关键路径加自定义 span，各服务暴露 /metrics 供 Prometheus 抓取，OTel Collector 配置 traces→Jaeger、metrics→Prometheus。附两条验收命令：Jaeger 四服务 span 树断言、Grafana RED 指标查询。只输出代码。`

**完成日期**：2026-09-12
**踩坑记录**：① Python otel-exporter-prometheus 的 reader API 版本间漂移（无 .registry），Python 侧 RED 改用 prometheus_client 直装中间件更稳；② Go otelhttp 新 semconv 指标名是 http_server_request_duration_seconds_*（老名 milliseconds），看板与验收用正则双名兼容；③ otelgrpc 客户端新版本只传播不产 span，product 的 gRPC server span 需手动 propagate.extract + start_as_current_span；④ kind load 不覆盖节点上已存在的同名 tag——同 tag 重建镜像必须先 crictl rmi 再 load（今天所有"镜像没生效"都是它）；⑤ OrbStack 重启会杀掉 Kafka broker 状态并让内存 seq 归零——订单 ID 现带 epoch 分量，Kafka PVC 可按需重置；⑥ Jaeger 查询要按 operation 过滤，探针 span 每两秒一条会刷满 limit。验收：traceID 串联 order/product/inventory/notification 四服务、Prometheus 四服务指标、Grafana 看板装载。

---

### [x] 项目 8：API 网关：认证、限流、灰度 ✅ 2026-09-12

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~120 行（网关配置 + 测试脚本为主）|
| **核心知识点** | Kong Ingress Controller、JWT 认证插件、rate-limiting 插件、按 header 的灰度流量切分、网关层 vs 应用层职责边界 |
| **产出模块** | `deploy/gateway/`（Kong 部署 + 认证/限流/灰度路由配置）、product 服务加版本头 `X-Version` |
| **技术栈** | Kong（⚠️ 开工探活 kind + arm64；fallback：APISIX chart；再降级：已装的 ingress-nginx + 注解限流，砍 JWT 项，学习目标保留限流与灰度）|
| **前置** | 项目 1、2 |
| **验收标准** | ① 无 token 访问商品接口返回 401，带合法 JWT 返回 200；② 限流 5 r/s 时连发第 6 个请求返回 429；③ 带 `X-Canary: true` 的请求 100% 命中 v2（响应头 `X-Version: v2`），不带 header 连打 100 次 100% 命中 v1 |
| **⚠️ 风险** | Kong 全家桶在 kind 上偏重，装 CRD-only 模式即可；灰度是网关层流量切分，与 kubernetes_operator.md 项目 5 的 Operator 版金丝雀机制不同、不冲突 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「API 网关认证限流灰度」。请给我完整配置约 120 行：Kong Ingress Controller 装到 kind（资源限制收紧）、商品路由挂 JWT 认证插件（附生成测试 RSA token 的小脚本）、rate-limiting 插件 5 r/s、部署 product v2 Deployment（响应头 X-Version: v2）并配置按 X-Canary header 100% 切 v2、无 header 全走 v1 的灰度路由。附三条验收命令：401/200 对比、429 触发、灰度命中断言。只输出代码。`

**完成日期**：2026-09-12
**踩坑记录**：① Kong 太重且当天网络反复抽风，改用已装的 ingress-nginx 原生能力：auth-url 外部授权（自写 auth 服务验 JWT）+ limit-rps 限流 + canary-by-header 灰度，三个验收点全部达成且教学价值不减；② canary ingress 会与基线合并生成 location 并吃掉基线的限流注解——限流注解两边都要写；③ limit-rps 默认自带 burst=25 nodelay，12 连发打不穿，验收要用 40 连发；④ ingress-nginx 控制器断连 API 后会用旧配置僵跑（日志时间戳停在过去），删 Pod 重连才生效；⑤ 控制器 Pod DNS 被 OrbStack 重启弄坏，auth-url 改用 auth Service 固定 ClusterIP 直连绕过。代码：mart/services/auth/、mart/deploy/gateway/、mart/deploy/auth/。

---

### [x] ⛓️ 项目 9：微服务 CI/CD 与 GitOps 交付 ✅ 2026-09-12

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~150 行（GitHub Actions workflow + ArgoCD Application 清单）|
| **核心知识点** | monorepo 路径过滤（只构建改动过的服务）、matrix 多镜像构建、ArgoCD app-of-apps、镜像 tag 写回 manifest、git revert 即回滚 |
| **产出模块** | `.github/workflows/build-deploy.yml`、`deploy/argocd/`（root app + 四服务 app）、四服务的 kustomize overlay |
| **技术栈** | GitHub Actions 免费额度（公共仓库不限/私有 2000 分钟月）；离线 fallback：本地构建脚本 + `kind load docker-image` + ArgoCD |
| **前置** | 项目 1-6（四个服务成型后才谈得上多服务交付）|
| **验收标准** | ① push 只改 product 的 commit：Actions 仅构建 product 镜像（其余服务显示 skipped），ArgoCD 自动 Sync 后线上 curl 到新版本号；② `git revert` 该 commit 后 10 分钟内线上回到旧版本；③ ArgoCD 中 4 个 Application 全部 Synced + Healthy |
| **⚠️ 风险** | 仓库需推到 GitHub（免费额度够用）；完全离线走 fallback 脚本，验收断言不变 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「微服务 CI/CD 与 GitOps 交付」。请给我完整配置约 150 行：GitHub Actions workflow 用 paths 过滤实现只构建改动服务（matrix 循环 order/product/inventory/notification，构建并推 GHCR，改写对应 kustomize 镜像 tag 后 push 触发 ArgoCD）、ArgoCD app-of-apps 结构（1 root + 4 服务 Application，syncPolicy 自动）。附三条验收命令：定向构建断言、revert 回滚计时、ArgoCD 状态检查；另给一份完全离线的本地构建 fallback 脚本。只输出代码。`

**完成日期**：2026-09-12
**踩坑记录**：① 全局 kubectl context 被并行会话漂移，helm install 把 ArgoCD 装到了 orbstack 集群——helm 也必须带 --kubeconfig（已加入脚本铁律）；② 无 GitHub remote，走清单预案的离线形态：git daemon（主机 9418）+ ArgoCD 经 OrbStack 的 host.internal 直达主机拉仓库；CI 由 09 脚本扮演（git diff 只构建改动服务），GitHub Actions 工作流已写好备用（.github/workflows/build-deploy.yml）；③ 4 个 Application 平铺（未用 app-of-apps）已覆盖验收。验收：4/4 Synced、定向构建+自动交付 0.5.0、git revert 自动回滚。

---

## 🗂️ 第四阶段：串联压测收口（项目 10）

> **目标**：把 mini-mart 当一个生产系统来验收——定义 SLO、压出瓶颈、注入故障验证韧性，产出压测报告

### [x] 🏁 项目 10：终极串联：全链路压测 + 混沌实验 ✅ 2026-09-12（错误率 SLO 达标；p99 在共享宿主机未达 300ms，瓶颈分析与优化已入报告）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~150 行（k6 场景脚本 + Chaos Mesh 实验 YAML）|
| **核心知识点** | k6 场景设计（ramp/step/恒压）、SLO 定义（p99/错误率）、Chaos Mesh pod-kill 与 network-delay 实验、瓶颈分析方法、压测报告写作 |
| **产出模块** | `tests/load/`（k6 下单全链路脚本）、`tests/chaos/`（实验 YAML）、`docs/load-test-report.md` |
| **技术栈** | k6（✅ 实测已装）、Chaos Mesh（⚠️ 开工探活 kind + arm64；fallback：手动 `kubectl delete pod` + 复用项目 4 的 /fault 延迟注入，实验结论等价）|
| **前置** | 项目 1-9 全部 |
| **验收标准** | ① 基线：k6 200 rps 持续 5 分钟跑完整下单流，p99 < 300ms 且错误率 < 0.1%；② 韧性：Chaos Mesh 杀掉 product 单副本期间整体错误率 < 1%，pod 自愈后指标回到基线；③ `docs/load-test-report.md` 落盘，含 SLO 表、瓶颈分析与下一步优化项 |
| **⚠️ 风险** | p99 目标达不到就当发现宝了——把瓶颈（如 Kafka 首次连接、Postgres 连接池）写进报告本身就是这个项目的产出 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 微服务项目「全链路压测 + 混沌实验」。请给我完整代码约 150 行：k6 脚本模拟"查商品→下单"全链路（恒压 200 rps、ramp 阶段找拐点）、Chaos Mesh 实验 YAML（pod-kill product、network-delay 注入 order→product）、一份压测报告模板（SLO 表：p99/错误率/吞吐，实验记录，瓶颈分析栏）。附三条验收命令：基线压测、故障注入期间错误率统计、报告文件检查。只输出代码。`

**完成日期**：2026-09-12
**踩坑记录**：混沌实验的最大教训是删除策略：--force --grace-period=0 强杀会绕过优雅关闭造成 conntrack 黑洞（60s 请求超时风暴、错误率破 1%），改回优雅删除（SIGTERM+preStop+摘流）后 36002 请求零失败、max=164ms。基线调优三连：order 2→4 副本×1core、inventory 1→3×1core（reserve 超时烧满 50s 重试预算是 max=55s 的真凶）、Kafka 发布改异步（同步等待 5s 是长尾源）——avg 从 2.25s 压到 45-127ms、错误率全程 0%。p99<300ms 在共享宿主机上未达（DNS/宿主机停顿尾延迟），归因与优化清单在 docs/load-test-report.md。Chaos Mesh 未安装（清单允许的 fallback：手动删 Pod，实验结论等价）。

**选做攻坚（不占名额）**：给四个服务注入 Istio sidecar，开启 mTLS + AuthorizationPolicy（只允许 order 调 product），观察 sidecar 对 gRPC 长连接的影响。istioctl 1.30.3 ✅ 已装，istiod 部署参考 `labs/13_service_mesh`。

---

## 📅 周计划

| 周次 | 内容 | 项目数 |
|:---|:---|:---:|
| **第 1 周** | 项目 1-2（服务上线 + 跨语言 gRPC）| 2 |
| **第 2 周** | 项目 3-4（配置热加载 + 容错三件套）| 2 |
| **第 3 周** | 项目 5-6（Kafka 事件驱动 + Saga，全清单最重的一周）| 2 |
| **第 4 周** | 项目 7（OTel 埋点，含监控栈重装）| 1 |
| **第 5 周** | 项目 8-9（网关治理 + GitOps 交付）| 2 |
| **第 6 周** | 项目 10（压测 + 混沌 + 报告收口）+ 选做 Istio | 1 |

## 🏆 里程碑

- [x] **完成项目 1-2** → 单服务交付能力：任意 Go/Python 服务规范化上 K8s 并跨语言互调
- [x] **完成项目 3-6** → 核心模式能力：热配置、熔断容错、事件驱动、跨库最终一致四大模式全部落地
- [x] **完成项目 7-9** → 平台工程能力：全链路可观测、网关流量治理、多服务 GitOps 自动交付
- [x] **全部完成** → mini-mart 完整系统：200 rps 错误率 0% + 混沌零失败 + 压测报告（docs/load-test-report.md），可作为 kubernetes_operator.md 项目 10 的管理对象

## 📝 每日日志

| 日期 | 项目 | 耗时 | 收获 | 踩坑 |
|:---|:---|:---:|:---|:---|
| | | | | |

## 🔧 环境配置

```bash
# 0. 已就绪（2026-09-11 实测）
# docker 29.4.0 ✅   kind v0.32.0 ✅   kubectl v1.33.9 ✅   helm v4.2.2 ✅
# go 1.26.5 ✅       python 3.14.7 ✅  k6 ✅               protoc ✅
# istioctl 1.30.3 ✅（仅选做项目用）
# 当前 kind 集群（kind-kind）：仅 ingress-nginx + local-path-storage；监控栈已清空，项目 7 开工时按 labs/23、labs/25 重装

# 1. 需安装（一次性）
brew install grpcurl                        # 项目 2：gRPC 调试与验收
# Python 依赖按服务建 venv：fastapi uvicorn grpcio grpcio-tools watchdog pyjwt
# Go 依赖随项目 go mod tidy：google.golang.org/grpc github.com/sony/gobreaker github.com/twmb/franz-go

# 2. 每项目开工前
kubectl config current-context              # 应输出 kind-kind
kubectl get nodes                           # 全部 Ready
docker info > /dev/null && echo docker-ok
kubectl top nodes 2>/dev/null || true       # 关注内存余量，项目 5/8 前尤其要查
```

## ⚠️ 与已有清单的关系

| 已有清单 | 关系 |
|:---|:---|
| kubernetes.md 项目 5（ConfigMap & Secret）| 项目 3 是应用侧进阶：那边学怎么挂，这边学应用怎么热加载不重启 |
| kubernetes.md 项目 9（HPA）| 本清单项目 10 压测时可联动开启，验证自动扩容对 p99 的改善，选做 |
| kubernetes.md 项目 11（Ingress）| 项目 8 的前置认知；本清单直接上网关层（JWT/限流/灰度），不再重复裸 Ingress |
| kubernetes.md 项目 13（Istio 入门）| 本清单"选做攻坚"的进阶对象，istiod 部署直接复用 labs/13 脚本 |
| kubernetes.md 项目 23/25（Prometheus、Jaeger）| 项目 7 复用其安装脚本（当前集群需重装），本清单专注应用侧 OTel 埋点，不重学装栈 |
| kubernetes.md 项目 28（GitOps/ArgoCD）| 项目 9 从单应用升级为多服务 monorepo + app-of-apps |
| kubernetes.md 项目 31 / kubernetes_operator.md 全线 | 无重叠：那边写控制器管资源，本清单写应用本身 |
| kubernetes_operator.md 项目 5（金丝雀 Operator）| 机制不同不冲突：那边 Operator 控发布流程，本项目 8 是网关层流量切分 |
| kubernetes_operator.md 项目 10（端到端微服务 Operator）| 正向依赖：本清单产出的 mini-mart 即其管理对象，两清单在此打通 |

## 🧪 平台组件实测速查表

| 组件 | 用在 | 实测结论 |
|:---|:---|:---|
| docker / kind / kubectl / helm | 全部 | ✅ 2026-09-11 本机实测已装，kind 集群在跑 |
| go 1.26 / python 3.14 / k6 / protoc | 全部 | ✅ 本机实测已装 |
| grpcurl | 项目 2 | ❌ 未装 → `brew install grpcurl`（已列入环境配置）|
| bitnami/kafka（KRaft）| 项目 5 | ⚠️ 待验证：开工探活 arm64 + 内存；fallback Redpanda |
| PostgreSQL（bitnami）| 项目 6 | ✅ labs 08/16 验证过 kind 可跑 |
| 监控栈（Prometheus/Jaeger/OTel Collector）| 项目 7 | ⚠️ 当前集群未装，按 labs/23、labs/25 脚本重装（脚本已验证）|
| Kong Ingress Controller | 项目 8 | ⚠️ 待验证：fallback APISIX → ingress-nginx（已装）+ 注解限流 |
| GitHub Actions 免费额度 | 项目 9 | ⚠️ 需仓库推 GitHub；离线 fallback 本地脚本 + kind load |
| Chaos Mesh | 项目 10 | ⚠️ 待验证：fallback 手动 delete pod + /fault 延迟注入 |
