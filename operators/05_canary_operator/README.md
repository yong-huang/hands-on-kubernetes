# Canary Operator（项目 5）

> 渐进式发布：一个 `Canary` CR 声明稳定/金丝雀两版镜像和 steps 权重序列，
> Controller 编排两个 Deployment 并通过共享 Service 的副本数比例模拟流量切分。

## 1. 架构总览

![Canary 发布](images/canary_flow.svg)

## 2. 快速开始

```bash
make install && make run
kubectl apply -f config/samples/delivery_v1_canary.yaml
kubectl get canary demo-canary -w
```

## 3. 已知限制（诚实预期）

当前版本 Controller 创建了 stable 和 canary 两个 Deployment，
但 stable 的副本数在 step 推进时未实际缩减（只改了 status 报告）。
生产实现需要：① 每步 CreateOrPatch 两个 Deployment 的 replicas；
② 等待 canary Ready 后才缩减 stable。已在代码 TODO 标注。

## 4. 文件结构

标准 kubebuilder 工程 + images/ 三件套。
