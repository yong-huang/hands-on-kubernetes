# mini-mart 全链路压测与混沌实验报告

- 日期：2026-09-13 10:47
- 环境：本机 kind 单节点（OrbStack VM，与宿主机共享 CPU）
- 链路：GET /products/p1 + POST /orders（gRPC 查价 -> Saga 跨库 -> Kafka 事件）

## SLO 表

| 指标 | SLO | 基线(200rps×5m) | 混沌(100rps×3m, 杀 product) |
|:---|:---|:---|:---|
