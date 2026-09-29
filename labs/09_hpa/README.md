# 09 · HPA：自动扩缩容的原理与实战

> 线上流量从来不是恒定的。HPA 把"扩缩容"交给控制器：持续观测 Pod 的 CPU/内存指标，与目标值比对后自动增减副本，让"实际利用率"向"目标利用率"持续收敛——声明式目标值 + 控制循环在伸缩场景的又一次应用。读完本篇，你将掌握核心公式、指标链路的前置条件，以及"缩容为什么那么慢"的设计原因。

## Background

流量有峰谷，副本数却只能二选一：按峰值配置，低谷时资源白费；按均值配置，峰值一来就过载。手工 `kubectl scale` 有三个具体问题：**人反应慢**（发现过载到敲完命令已过几分钟）、**无法 7x24 值守**（凌晨的流量毛刺没人管）、**不知道扩到几个**（拍脑袋定数字）。

HPA（Horizontal Pod Autoscaler，水平自动伸缩器）沿用了 K8s 的声明式思路：用户只声明目标利用率，副本数是控制循环的输出。它每 15 秒比较一次"实际利用率 vs 目标利用率"，按公式算出期望副本数并改写 Deployment——把"盯监控、做决策、敲命令"这条人工链路交给机器。

## What

HPA 按观测指标自动调整 Deployment / StatefulSet 的副本数。核心公式一行：

```
desiredReplicas = ceil( currentReplicas × currentMetricValue / desiredMetricValue )
```

例：目标 CPU 利用率 50%，当前 2 副本平均利用率 90% → `ceil(2 × 90 / 50) = 4`，扩到 4 个。一句话心智模型：**你只声明目标利用率，副本数是控制循环的输出**——可以把 HPA 想象成恒温器；

但与恒温器不同的是，它调节的"温度"（利用率）本身受副本数影响，所以是循环收敛而不是一次到位。

| 字段 | 作用 |
|---|---|
| `scaleTargetRef` | 扩缩容目标（Deployment 或 StatefulSet） |
| `minReplicas` / `maxReplicas` | 副本数上下限（硬顶防失控） |
| `metrics` | 观测哪些指标、目标值多少 |
| `behavior` | 扩/缩容的速度与稳定窗口 |

## When to Use

典型场景：web 服务白天高峰夜间低谷（CPU 指标伸缩）；消息消费者按队列长度扩容（自定义指标）；大促前设高 maxReplicas 兜住突发。

何时不用：负载与 CPU 无关的应用（如纯内存缓存，CPU 平稳但内存涨——改用内存指标或自定义指标）；副本启动需要几分钟的重应用（扩容来不及，考虑提前扩容或缩容保护）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 手工 scale | 靠人盯 | 一次性压测 |
| HPA（水平） | 调副本数 | 负载可水平分摊的无状态服务 |
| VPA（垂直） | 调单 Pod 的 requests/limits | 资源规格不明的新应用（见 Q1） |
| Cluster Autoscaler | 调节点数 | Pod 扩完节点装不下时（与 HPA 组合） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；metrics-server 多数集群默认不装，脚本会先装。

```bash
cd labs/09_hpa
./hpa.sh install   # 安装 metrics-server（HPA 指标来源）
./hpa.sh apply     # 部署 CPU 密集型应用 + HPA（autoscaling/v2，目标 CPU 50%）
./hpa.sh load      # 制造 CPU 负载，观察 TARGETS 冲高、副本 1→N
./hpa.sh watch     # 撤掉负载，观察 5 分钟稳定窗口后的慢缩容
./hpa.sh clean
```

成功判据：`load` 后 `kubectl get hpa` 的 TARGETS 列出现百分比并冲高（如远超 50%）、REPLICAS 随后增加；`watch` 阶段撤压后约 5 分钟内副本回落（实际数值以运行为准）。

诚实预期：压测后 `kubectl get hpa` 的 TARGETS 先冲高、REPLICAS 随后增加，中间隔一两个控制周期；撤压后副本要等约 5 分钟稳定窗口才开始回落——缩容慢是设计使然，不是卡住。

关键字段（`manifests/hpa.yaml`）：

```yaml
spec:
  scaleTargetRef:               # 扩缩容目标（Deployment 或 StatefulSet）
    kind: Deployment
    name: cpu-stress-app
  minReplicas: 1                # 副本下限
  maxReplicas: 10               # 硬顶，防止指标异常导致失控扩容
  metrics:
    - type: Resource            # Pod 资源指标（metrics-server 提供）
      resource:
        name: cpu
        target:
          type: Utilization     # 利用率 %；也支持 AverageValue（绝对值）
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # 缩容稳定窗口 5 分钟
```

## How It Works

**控制环**是一条闭环：压测负载让 Pods 用量升高，kubelet（节点上的容器管理组件，内含 cAdvisor 采集器）采集用量，metrics-server（集群级指标聚合组件）把用量聚合成 Metrics API。

HPA 控制器按公式算出期望副本，改写 Deployment 的 `scale.replicas`，增删 Pod——新用量再反馈回指标层。

你在 `load` 步骤看到的 TARGETS 冲高随后副本增加，就来自这条链。公式细节：

- **利用率是所有就绪 Pod 的平均值**，不是单 Pod 最大值
- 多条 metrics（CPU、内存、自定义）各自算一个 desired，**取最大值**（宁多扩）
- 扩容有 `tolerance`（默认 ±10%）：结果在带内不动，防指标微抖引起 flapping
- 缩容时分子按"缩完还剩几个 Pod"重新校验，保证缩完不立刻超载

**behavior：为什么扩容快、缩容慢**：

| 配置 | 默认 | 本例 | 目的 |
|------|------|------|------|
| scaleUp.stabilizationWindowSeconds | 0s | 0s | 扩容要快，立即执行 |
| scaleUp.policies | 15s 内 +100% 或 +4 Pod | 同左 | 限制单次幅度，防止指标异常炸到 maxReplicas |
| scaleDown.stabilizationWindowSeconds | 300s | 300s | **缩容前需连续 5 分钟低负载** |
| scaleDown.policies | 15s 内 -25% 或 -1 Pod | 同左 | 缩容步子要小 |

缩容慢是刻意设计：刚缩掉的 Pod 说没就没，流量回升时重新调度、拉镜像、预热要几十秒；而"多留几个 Pod 几分钟"成本很低。这是经典的**扩容快、缩容慢**的非对称折中。

**指标链路与前置条件**：`Resource` 类型的 CPU/内存指标由 metrics-server 提供，装完 `kubectl top` 才能用。

**必须设置 `resources.requests`**：CPU 利用率 = 实际用量 / `requests.cpu`——requests 是百分比计算的分母，没有它，TARGETS 列一直显示 `<unknown>`，HPA 永远不会动作。

## Pitfalls & Q&A

踩坑清单：

- Pod 未设 `resources.requests` → TARGETS 显示 `<unknown>`，HPA 不工作。
- kind/minikube 里 metrics-server 需加 `--kubelet-insecure-tls`（kubelet 证书无 CA 签名）。
- 同时配 CPU 和内存指标时，**内存目标设高些（如 60%）**：内存不随请求结束回落，易误触发。
- 手动 `kubectl scale` 会被 HPA 在下个周期覆盖（HPA 才是期望副本数的属主）。

**Q1: HPA / VPA / Cluster Autoscaler 什么关系？**

三者正交：HPA 调副本数（水平）；VPA 调单 Pod 的 requests/limits（垂直，重启生效）；Cluster Autoscaler 调节点数。VPA 与 HPA 同用会冲突（两者都想改同一批 Pod 的资源口径，VPA 还会驱逐 Pod 干扰 HPA 的指标）；

常见生产组合是 HPA + Cluster Autoscaler——Pod 扩多了节点装不下，CA 自动加节点。

**Q2: 业务指标（QPS、队列长度）怎么接入 HPA？**

Resource 类型只有 CPU/内存，业务指标要走自定义指标：Prometheus Adapter 把 Prometheus 查询注册为 `custom.metrics.k8s.io`（Pods 类型按 Pod 平均）或 `external.metrics.k8s.io`（集群级外部指标）；

KEDA 更省事，可以直接以任意 Prometheus 查询/Kafka Lag 为信号源驱动扩缩。选型判断：已在用 Prometheus 且指标简单用 Adapter；要多信号源、缩容到零用 KEDA。
