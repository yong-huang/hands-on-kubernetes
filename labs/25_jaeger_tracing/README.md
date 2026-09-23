# 25 · 分布式追踪：Jaeger 与 OpenTelemetry

> 指标告诉你"慢了"，日志告诉你"错了"，但跨三个服务的请求到底慢在哪一跳？本实验部署 Jaeger all-in-one，给三个真实微服务（front → order → payment，代码放 ConfigMap、镜像用 `python:3.12-slim`）接入 OTel SDK，span 经 OTLP 上报 Jaeger——让微服务调用链在 Jaeger UI 上以瀑布图完整呈现。

## What

一次请求是一个 **Trace**（全局唯一 trace-id），每次函数/HTTP 调用是一个 **Span**（记录开始时间、耗时、标签），Span 间以 parent-span-id 构成树。瀑布图上 span 的宽度就是自身耗时：

```text
svc-front  GET /            [============182ms==========]
  └ svc-order POST /order     [==150ms==]
      └ svc-payment /pay        [==95ms==]
          └ db INSERT             [=40ms=]
```

一眼看出 payment 里 db INSERT 占了 40ms，是这条慢请求的元凶。一句话心智模型：**给分布式调用栈拍 X 光**——每一跳的耗时、层级、标签都落在同一条 trace 上。

## Why

指标和日志都是单点视角：三个服务各自"正常"，请求却慢了 10 倍，问题就藏在跳与跳之间。追踪把"一次用户请求经过的所有服务、每一跳花了多久"串成一条完整证据链，性能瓶颈、失败传播、异常路由都能在一张瀑布图上定位——这是指标聚合和逐服务翻日志都做不到的。

## How

```bash
cd labs/25_jaeger_tracing
./jaeger_tracing.sh install   # 部署 Jaeger all-in-one（可选装 cert-manager + OTel Operator）
./jaeger_tracing.sh deploy    # 部署 front/order/payment 三服务（OTel SDK 接入）
./jaeger_tracing.sh trace     # 制造请求流量，生成完整 trace
./jaeger_tracing.sh ui        # port-forward 打开 Jaeger UI 查看瀑布图
./jaeger_tracing.sh clean
```

诚实预期：首次 `deploy` 需要拉取 python/cert-manager/operator 等镜像，init 容器还要把 OTel agent 拷进 Pod，冷启动几分钟属正常；`trace` 步骤前也要等前端流量线程跑几轮（脚本已内置 sleep）。

生产路径的自动注入只需给 Pod 打注解：

```yaml
annotations:
  instrumentation.opentelemetry.io/inject-python: "demo-instrumentation"
```

Jaeger 侧开放 OTLP 上报入口：

```yaml
env: [{name: COLLECTOR_OTLP_ENABLED, value: "true"}]
ports: [{name: otlp-grpc, containerPort: 4317}]
```

## Deep Dive

**Context 传播：链路得以延续的唯一前提**。分布式环境下没有魔法：上游把当前上下文编码进 HTTP 头，**下游必须透传**这个头再发起自己的出站调用，span 才能挂到同一棵树上：

```text
traceparent: 00-<trace-id>-<span-id>-01
```

本实验的 Python 服务里：入口用 `extract()` 从请求头恢复上下文挂 server span，出站 urllib 调用由 agent 自动建 client span 并透传 header。断链的典型症状是 Jaeger 里出现大量只有单 span 的孤儿 trace——十有八九是某层服务没透传 header。

**埋点两条路，殊途同归**：

- **Operator 自动注入（生产路径）**：Pod 打注解 + 一个 `Instrumentation` CR（依赖 OTel Operator，`install` 步骤会装 cert-manager 与固定版本的 operator）。operator 看到注解后给 Pod 加 init 容器，把 python agent 拷到 `/otel-auto-instrumentation` 并设置 `PYTHONPATH`，`sitecustomize` 随解释器启动自动初始化 TracerProvider，按 CR 的 `exporter.endpoint` 上报。应用代码零依赖安装，换语言（java/nodejs）只是换注解。
- **容器内自装 SDK（本实验路径）**：注入镜像托管在 ghcr.io（国内网络常不可达），因此三个服务在启动命令里 `pip install opentelemetry-sdk + otlp exporter`（走国内 pypi 镜像），并在 `server.py` 里显式完成注入路径自动做的三件事：初始化 TracerProvider（`Resource` 里的 `service.name` 决定 Jaeger 服务名）、设置 OTLP exporter（读 `OTEL_EXPORTER_OTLP_ENDPOINT`）、W3C traceparent 的 extract/inject。理解了后者也就看懂了前者。

**OTLP：统一的上报协议**：Jaeger 1.5x 原生开放 OTLP gRPC 入口（4317），CR 里的 `exporter.endpoint` 就指向它。OTel SDK → OTLP 已成为厂商中立的事实标准：换后端（Jaeger→Tempo）只需改 collector 的导出配置，应用零改动。SDK 批量异步上报，对业务延迟的影响通常在微秒级。

**采样：追踪的成本阀门**：本实验未配置采样——agent 默认 `parentbased_always_on`（全量），教学场景要保证每条请求都能在 UI 上看到。生产上全量追踪在高 QPS 下存储成本爆炸：头部采样（head sampling）在入口通过 `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + 采样率参数（常用 1%~10%）决定是否记录。

## Q&A

**Q1: 头部采样会丢掉出问题的请求，怎么办？**
配合尾部采样：OTel Collector 的 Tail Sampling Processor 按 status/duration/路由在收到完整 trace 后动态决策，错误请求与慢请求 100% 保留、正常请求按比例丢弃——排障时最需要的恰恰是那部分异常流量。

**Q2: trace 怎么和日志、剖析联动？**
Trace↔Log 关联：日志里打 trace-id、span 注入 log correlation 字段，Jaeger 点进 span 能跳日志。更进一步的性能剖析联动：eBPF Profiling（如 Pyroscope）按 span 时段抓火焰图，回答"这 40ms 具体耗在哪个函数"——指标（慢了）→ 追踪（哪一跳）→ 剖析（哪个函数）三级下钻。

**Q3: Jaeger 的存储怎么选？**
all-in-one 内存存储仅限实验。生产用 Elasticsearch（可复用 EFK 集群，见 lab 24）或 Tempo（对象存储成本最低）——选型主要看数据量与既有基础设施：已有 ES 用 ES，成本敏感或 Grafana 生态用 Tempo。
