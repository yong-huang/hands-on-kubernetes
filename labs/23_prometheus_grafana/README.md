# Prometheus + Grafana 监控

## 1. 文件结构

```
23_prometheus_grafana/
├── README.md              # 本文档
├── monitoring.sh          # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── monitoring.yaml    # 演示用的 K8s 清单
└── images/
    ├── monitoring_flow.architecture.json  # 图源（Typed JSON IR）
    ├── monitoring_flow.html               # 交互版架构图
    └── monitoring_flow.svg                # 双主题矢量版（本文档 §5 内嵌）
```

## 2. 项目概述

没有监控的集群等于盲飞。本项目（`monitoring.yaml` + `monitoring.sh`）用 **kube-prometheus-stack** 一键部署 Prometheus Operator + Alertmanager + Grafana 全栈，再以示例应用演示 Operator 模式下的声明式监控：`ServiceMonitor` 定义抓取、`PrometheusRule` 定义告警、ConfigMap 标签驱动 Grafana 数据源加载——目标是让"集群和应用指标可视化展示"只需提交几个 CR。

---

## 3. 核心机制解析

### 1. Pull 模型：指标留在集群内

```yaml
prometheus.io/scrape: "true"   # 或 ServiceMonitor 声明
interval: 15s
```

Prometheus 每 15 秒拉取一次 `/metrics`（文本协议）。Pull 模型意味着应用崩溃时 Prometheus 留着最后一次样本，而告警由 `up == 0` 表达——**采集与告警解耦**。所有原始数据不出集群，出门的只有 Alertmanager 发出的通知。

### 2. ServiceMonitor：Operator 的核心抽象

```yaml
spec:
  selector: {matchLabels: {app: metrics-demo}}
  endpoints: [{port: http, interval: 15s}]
```

它不直接配置 Prometheus，而是被 Operator watch：任何 SM 变化 → Operator 重新渲染全部抓取配置 → 生成 Secret → Prometheus 自动热加载。这就是"监控即代码"——加一个应用的监控 = 提交一个 SM，而不是改 prometheus.yml。

**最大的坑**是 label 联动：SM 必须带 `release: prometheus` 标签才会被 operator 的 serviceMonitorSelector 选中，否则永远不生效且没有任何报错。实验中我们直接关掉了 Helm 前缀过滤（`serviceMonitorSelectorNilUsesHelmValues=false`）。

### 3. PrometheusRule：告警也是 CRD

```yaml
- alert: HighRequestLatency
  expr: histogram_quantile(0.99, rate(...[5m])) > 1
  for: 5m        # 持续5分钟才触发, 防抖动
- record: job:http_error_rate:5m   # 预聚合, 加速面板查询
```

`for: 5m` 是告警防抖的关键——瞬时毛刺不叫人，持续劣化才升级。`record` 录制规则把昂贵的 rate 计算预聚合成新指标，Grafana 大面板查询直接读录制结果，避免实时聚合风暴。

---

## 4. 可视化

![监控双线](images/monitoring_flow.svg)

图中上行是**指标数据流**：应用暴露 /metrics → Prometheus 每 15s Pull 进 TSDB → Grafana 查询渲染；告警分支经 Alertmanager 分组去重后通知值班——出门的只有通知，原始数据不出集群。下行是 **Operator 声明式配置**：ServiceMonitor / PrometheusRule 被 Operator watch → 渲染成 Secret → Prometheus 热加载，"加一个应用的监控"= 提交一个 CR。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/23_prometheus_grafana/images/monitoring_flow.html)（或本地打开 [`images/monitoring_flow.html`](images/monitoring_flow.html)）。

---

## 5. 工程延伸

- **多副本 Prometheus**: 双副本 + Thanos/Cortex 远端存储，解决单点与长期保留
- **SLO 工作流**: 用 Sloth 从 SLO 清单生成 burn-rate 告警规则，替代手写阈值
- **黑盒监控**: Blackbox Exporter 探测 DNS/证书/HTTP，补齐"白盒指标看不见"的外部视角
- **成本控制**: 指标基数(cardinality)是最大成本项——用 `topk` 审计高基数 label，砍掉无用 series
