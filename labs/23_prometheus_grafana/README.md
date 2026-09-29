# 23 · Prometheus + Grafana：Operator 模式的声明式监控

> 没有监控的集群等于盲飞。本实验用 **kube-prometheus-stack** 一键部署 Prometheus Operator + Alertmanager + Grafana 全栈，再以示例应用演示 Operator 模式下的声明式监控：`ServiceMonitor` 定义抓取、`PrometheusRule` 定义告警、ConfigMap 标签驱动 Grafana 数据源加载——目标是让"集群和应用指标可视化展示"只需提交几个 CR。读完本篇，你将掌握 Pull 模型的语义、Operator 的渲染链路，以及 label 联动这个最大的坑。

## Background

监控一个动态集群曾有两种做法：手工维护 Prometheus 的抓取配置文件（prometheus.yml），每上线一个服务就加一段 targets；或者让服务自己往监控网关推数据（Push 模型），又要处理"谁在推、推丢了怎么办"。

前者在 Pod 随时生灭的 K8s 里根本跟不上——配置文件的更新速度追不上实例的变化速度；后者的推送方和接收方耦合，故障定位困难。

Prometheus 选择了 Pull（拉取）模型：监控端主动来抓应用暴露的 `/metrics` 端点。Operator 模式进一步把"改配置文件"变成"提交 CR"：监控配置成为声明式 API 的又一种消费者，跟着应用一起进 Git、走发布流程。

## What

| 组件/CR | 角色 |
|---------|------|
| Prometheus Operator | watch ServiceMonitor/PrometheusRule 等 CR，渲染抓取与告警配置 |
| ServiceMonitor（CR） | 声明"抓谁、多久抓一次" |
| PrometheusRule（CR） | 声明告警规则（alert）与录制规则（record） |
| Alertmanager | 告警分组、去重、路由通知 |
| Grafana | 查询 TSDB（时序数据库）渲染面板 |

一句话心智模型：**监控即代码**——加一个应用的监控 = 提交一个 ServiceMonitor，而不是改 prometheus.yml。但和"配置文件"不同的是，这份"配置"有自己的 controller 负责渲染与热加载，应用删了它的 CR，监控配置也一起消失，不会留死配置。

Prometheus 每 15 秒 Pull 一次 `/metrics`（文本协议），所有原始数据不出集群，出门的只有 Alertmanager 发出的通知。

## When to Use

典型场景：给新服务接监控（提交一个 ServiceMonitor）；给关键指标配告警（PrometheusRule + for 防抖）；给面板加速查询（record 预聚合规则）。

何时不用：需要日志和链路（Prometheus 只管指标——日志看 lab 24 的 EFK，链路看 lab 25 的 Jaeger）；一次性临时抓取排查（直接 `kubectl exec` + curl `/metrics` 更快）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| Push 网关 / StatsD | 应用主动推 | 短生命周期任务（Job 指标） |
| Prometheus + Operator | Pull + 声明式配置 | K8s 集群指标监控（标准选择） |
| 云厂商监控 | 托管免运维 | 不想自维护的全托管需求 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；helm 已安装。

```bash
cd labs/23_prometheus_grafana
./monitoring.sh install   # helm 安装 kube-prometheus-stack 全栈
./monitoring.sh deploy    # 部署示例应用 + ServiceMonitor + PrometheusRule + Grafana 数据源
./monitoring.sh verify    # Prometheus targets 就绪、告警触发、Grafana 面板可查
./monitoring.sh clean
```

ServiceMonitor——声明抓取目标：

```yaml
spec:
  selector: {matchLabels: {app: metrics-demo}}
  endpoints: [{port: http, interval: 15s}]
```

PrometheusRule——告警与录制规则（`manifests/monitoring.yaml`）：

```yaml
- alert: HighRequestLatency
  expr: histogram_quantile(0.99, rate(...[5m])) > 1
  for: 5m        # 持续5分钟才触发, 防抖动
- record: job:http_error_rate:5m   # 预聚合, 加速面板查询
```

应用侧最简的抓取开启方式是 annotation：

```yaml
prometheus.io/scrape: "true"   # 或 ServiceMonitor 声明
interval: 15s
```

## How It Works

**ServiceMonitor 的渲染链路**：SM 不直接配置 Prometheus，而是被 Operator watch——任何 SM 变化 → Operator 重新渲染全部抓取配置 → 生成 Secret → Prometheus 自动热加载。

你在 `verify` 步骤看到的 targets 出现，就是这条"CR → Secret → 热加载"链路的产物。

**label 联动是最大的坑**：SM 必须带 `release: prometheus` 标签才会被 Operator 的 serviceMonitorSelector 选中，否则永远不生效且**没有任何报错**——targets 列表里根本没有它，排查时毫无线索。

实验中直接关掉了 Helm 前缀过滤（`serviceMonitorSelectorNilUsesHelmValues=false`）。踩到"SM 建了但没抓取"，第一步就查 selector 标签。

**Pull 模型的语义**：Pull 意味着应用崩溃时 Prometheus 留着最后一次样本，而告警由 `up == 0` 表达——**采集与告警解耦**。抓取失败不是数据丢失，而是变成了一个可告警的信号。

**告警防抖与预聚合**：`for: 5m` 是告警防抖的关键——瞬时毛刺不叫人，持续劣化才升级。`record` 录制规则把昂贵的 rate 计算预聚合成新指标，Grafana 大面板查询直接读录制结果，避免实时聚合风暴。

## Pitfalls & Q&A

踩坑清单：

- SM 建了但 Prometheus 不抓：先查 serviceMonitorSelector 标签联动（见 How It Works），没有任何报错是它的特点。
- 告警狂叫：检查 `for` 字段是否遗漏，瞬时毛刺也会触发。
- Grafana 面板查询超时：用 record 预聚合替代实时聚合大范围数据。

**Q1: 单副本 Prometheus 的单点与数据保留怎么解决？**
双副本 + Thanos/Cortex 远端存储：副本间互为热备，长期数据落到对象存储，查询层（Thanos Query）自动去重。本地 TSDB 只承担短期高分辨率数据，这是生产监控的标准形态。

**Q2: 告警阈值总写不准怎么办？**
用 SLO 工作流替代手写阈值：Sloth 之类的工具从 SLO 清单（目标可用性/延迟）自动生成 burn-rate（错误预算消耗速率）告警规则——消耗预算的速度超过阈值才报警，比拍脑袋定"CPU > 80%"科学得多。

**Q3: 白盒指标看不见的问题怎么补？**
黑盒监控：Blackbox Exporter 从集群外部探测 DNS/证书/HTTP，回答"用户视角服务通不通"。白盒指标告诉你"内部为什么坏"，黑盒探测告诉你"外部是否已经坏"——两者互补。

**Q4: 监控的成本大头在哪？**

指标基数（cardinality）：每条 time series 都占内存和磁盘，一个高基数 label（如 user_id）能让 series 数爆炸。用 `topk` 审计 series 最多的指标，砍掉无用 label 和僵尸 series——cardinality 治理是监控成本控制的第一个抓手。
