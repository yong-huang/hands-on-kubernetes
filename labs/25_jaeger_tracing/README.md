# 分布式追踪（Jaeger）

## 文件结构

```
25_jaeger_tracing/
├── README.md     # 本文档
├── jaeger_tracing.sh # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── jaeger_tracing.yaml  # 演示用的 K8s 清单
├── scripts/
│   └── gen_arch.py   # 架构图生成脚本 (python3 scripts/gen_arch.py)
└── images/
    └── jaeger_tracing_arch.png   # 架构图（gen_arch.py 生成）
```

## 项目概述

指标告诉你"慢了"，日志告诉你"错了"，但跨三个服务的请求到底慢在哪一跳？本项目（`jaeger_tracing.yaml` + `jaeger_tracing.sh`）部署 Jaeger all-in-one 并搭建 front → order → payment 三层微服务，演示 Trace/Span 模型与 W3C traceparent 头透传——目标是让微服务调用链在 Jaeger UI 上以瀑布图完整呈现。

---

## 核心机制解析

### 1. Trace 与 Span：给调用栈拍 X 光

```text
svc-front  GET /            [============182ms==========]
  └ svc-order POST /order     [==150ms==]
      └ svc-payment /pay        [==95ms==]
          └ db INSERT             [=40ms=]
```

一次请求是一个 **Trace**（全局唯一 trace-id），每次函数/HTTP 调用是一个 **Span**（记录开始时间、耗时、标签），Span 间以 parent-span-id 构成树。瀑布图上 span 的宽度就是自身耗时——一眼看出 payment 里 db INSERT 占了 40ms，是这条慢请求的元凶。

### 2. Context 传播：链路得以延续的唯一前提

```text
traceparent: 00-<trace-id>-<span-id>-01
```

分布式环境下没有魔法：上游把当前上下文编码进 HTTP 头，**下游必须透传**这个头再发起自己的出站调用，span 才能挂到同一棵树上。断链的典型症状是 Jaeger 里出现大量只有单 span 的孤儿 trace——十有八九是某层服务没透传 header。Istio 场景下 sidecar 会自动上报 span，但应用侧透传依然省不掉。

### 3. OTLP：统一的上报协议

```yaml
env: [{name: COLLECTOR_OTLP_ENABLED, value: "true"}]
ports: [{name: otlp-grpc, containerPort: 4317}]
```

Jaeger 原生协议（thrift）之外开放 OTLP 入口。OTel SDK → OTLP Collector 已成为厂商中立的事实标准：换后端（Jaeger→Tempo）只需改 collector 的导出配置，应用零改动。SDK 批量异步上报，对业务延迟的影响通常在微秒级。

### 4. 采样：追踪的成本阀门

```yaml
tracing:
  - randomSamplingPercentage: 10
```

全量追踪在高 QPS 下存储成本爆炸。头部采样（head sampling）在入口决定是否记录；生产常用 1%~10% 随机采样，配合错误请求 100% 保留的尾部采样（tail sampling）策略——排障时最需要的恰恰是被采样的那部分异常流量。

---

## 可视化分析

![jaeger](images/jaeger_tracing_arch.png)

上图两面板：
- **左图 Trace 瀑布图**：模拟一条 182ms 请求的 span 树，缩进表示父子层级、宽度表示耗时，虚线连接父子 span；payment 的 db INSERT 一眼可见为瓶颈段
- **右图 数据流**：client 生成 trace-id → 各服务建 span 并透传 header → OTLP gRPC 批量上报 → Collector 入库 → Query UI 检索；附 Istio 场景的采样率控制说明

---

## 工程延伸

- **尾部采样**: OTel Tail Sampling Processor 按 status/duration/路由动态决策，错误与慢请求全保
- **Trace↔Log 关联**: 日志里打 trace-id、span 注入 log correlation 字段，Jaeger 点进 span 能跳日志
- **存储选型**: all-in-one 内存存储仅限实验；生产用 Elasticsearch（复用 EFK 集群）或 Tempo（对象存储成本最低）
- **性能剖析联动**: eBPF Profiling（如 Pyroscope）按 span 时段抓火焰图，回答"这 40ms 具体耗在哪个函数"
