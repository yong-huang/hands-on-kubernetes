# 25 · 分布式追踪：Jaeger 与 OpenTelemetry

> 指标告诉你"慢了"，日志告诉你"错了"，但跨三个服务的请求到底慢在哪一跳？本实验部署 Jaeger all-in-one，给三个真实微服务（front → order → payment，代码放 ConfigMap、镜像用 `python:3.12-slim`）接入 OTel（OpenTelemetry，下文缩写）SDK，span 经 OTLP 上报 Jaeger——让微服务调用链在 Jaeger UI 上以瀑布图完整呈现。读完本篇，你将读懂瀑布图、理解 context 传播为什么是链路的命门。

## Background

单机时代定位慢请求，看一个进程的调用栈就够了。微服务把一次用户请求拆成三个服务的多次调用：每个服务的指标都"正常"，请求却慢了 10 倍——问题藏在服务之间的跳转里，而指标是按服务聚合的，看不到"这一次请求"经历了什么；日志能翻到痕迹，但要人工在三个服务的日志之间对时间戳拼线索。

分布式追踪把"一次请求经过的所有服务、每一跳花了多久"串成一条完整证据链：入口生成全局 trace-id，每一跳记录为 span（带耗时与标签），跨服务传递时带上这个 id。Jaeger 负责收集与展示，瀑布图上一眼看出瓶颈在哪一跳。

## What

一次请求是一个 **Trace**（全局唯一 trace-id），每次函数/HTTP 调用是一个 **Span**（记录开始时间、耗时、标签），Span 间以 parent-span-id 构成树。瀑布图上 span 的宽度就是自身耗时：

```text
svc-front  GET /            [============182ms==========]
  └ svc-order POST /order     [==150ms==]
      └ svc-payment /pay        [==95ms==]
          └ db INSERT             [=40ms=]
```

一眼看出 payment 里 db INSERT 占了 40ms，是这条慢请求的元凶。一句话心智模型：**给分布式调用栈拍 X 光**——但和单机 profiler 不同的是，它横跨网络与进程边界，靠的是每个服务都遵守同一套传递约定（见 How It Works 的 context 传播）。

## When to Use

典型场景：多服务链路上"哪个服务拖慢了整体"的定位；一次失败请求的完整路径回放（错误发生在哪一跳、传了什么参数）；新上线服务的调用关系摸底。

何时不用：单服务内部的函数级性能剖析（用 profiler，追踪只有毫秒级 span 粒度）；QPS 极高且只需聚合视图（全量追踪成本高，配合采样，见 Q1）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 指标 + 日志人工对时间戳 | 免基建、靠人肉 | 一两个服务的简单系统 |
| Jaeger / Tempo 追踪 | 全链路证据链 | 微服务跨服务排障 |
| eBPF 剖析（Pyroscope） | 函数级火焰图 | 定位到跳之后还要下钻到函数 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

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

## How It Works

**Context 传播：链路得以延续的唯一前提**。分布式环境下没有魔法：上游把当前上下文编码进 HTTP 头，**下游必须透传**这个头再发起自己的出站调用，span 才能挂到同一棵树上：

```text
traceparent: 00-<trace-id>-<span-id>-01
```

本实验的 Python 服务里：入口用 `extract()` 从请求头恢复上下文挂 server span，出站 urllib 调用由 agent 自动建 client span 并透传 header。

断链的典型症状是 Jaeger 里出现大量只有单 span 的孤儿 trace——十有八九是某层服务没透传 header。

**埋点两条路，殊途同归**：

- **Operator 自动注入（生产路径）**：Pod 打注解 + 一个 `Instrumentation` CR（CR 即自定义资源，K8s 允许用户注册的新对象类型；依赖 OTel Operator，`install` 步骤会装 cert-manager——负责签发证书的集群组件——与固定版本的 operator）。
- operator 看到注解后给 Pod 加 init 容器，把 python agent 拷到 `/otel-auto-instrumentation` 并设置 `PYTHONPATH`，`sitecustomize` 随解释器启动自动初始化 TracerProvider，按 CR 的 `exporter.endpoint` 上报；应用代码零依赖安装，换语言（java/nodejs）只是换注解。
- **容器内自装 SDK（本实验路径）**：注入镜像托管在 ghcr.io（国内网络常不可达），因此三个服务在启动命令里 `pip install opentelemetry-sdk + otlp exporter`（走国内 pypi 镜像）。
- `server.py` 里显式完成注入路径自动做的三件事：初始化 TracerProvider（`Resource` 里的 `service.name` 决定 Jaeger 服务名）；设置 OTLP exporter（读 `OTEL_EXPORTER_OTLP_ENDPOINT`）；W3C traceparent 的 extract/inject。理解了后者也就看懂了前者。

**OTLP：统一的上报协议**：Jaeger 1.5x 原生开放 OTLP gRPC 入口（4317），CR 里的 `exporter.endpoint` 就指向它。

OTel SDK → OTLP 已成为厂商中立的事实标准：换后端（Jaeger→Tempo）只需改 collector 的导出配置，应用零改动。SDK 批量异步上报，对业务延迟的影响通常在微秒级。

**采样：追踪的成本阀门**：本实验未配置采样——agent 默认 `parentbased_always_on`（全量），教学场景要保证每条请求都能在 UI 上看到。

生产上全量追踪在高 QPS 下存储成本爆炸：头部采样（head sampling）在入口通过 `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + 采样率参数（常用 1%~10%）决定是否记录。

## Pitfalls & Q&A

踩坑清单：

- 瀑布图里全是孤儿 trace（单 span）：某层服务没透传 traceparent 头，逐层检查出站调用。
- 看不到任何 trace：先确认 agent 的 OTLP endpoint 指向 Jaeger 的 4317 端口。
- 冷启动误判为故障：首次部署几分钟属正常（见诚实预期）。

**Q1: 头部采样会丢掉出问题的请求，怎么办？**
配合尾部采样：OTel Collector 的 Tail Sampling Processor 按 status/duration/路由在收到完整 trace 后动态决策，错误请求与慢请求 100% 保留、正常请求按比例丢弃——排障时最需要的恰恰是那部分异常流量。

**Q2: trace 怎么和日志、剖析联动？**

Trace↔Log 关联：日志里打 trace-id、span 注入 log correlation 字段，Jaeger 点进 span 能跳日志（日志侧见 lab 24）。

更进一步的性能剖析联动：eBPF Profiling（如 Pyroscope）按 span 时段抓火焰图，回答"这 40ms 具体耗在哪个函数"——指标（慢了）→ 追踪（哪一跳）→ 剖析（哪个函数）三级下钻。

**Q3: Jaeger 的存储怎么选？**
all-in-one 内存存储仅限实验。生产用 Elasticsearch（可复用 EFK 集群，见 lab 24）或 Tempo（对象存储成本最低）——选型主要看数据量与既有基础设施：已有 ES 用 ES，成本敏感或 Grafana 生态用 Tempo。
