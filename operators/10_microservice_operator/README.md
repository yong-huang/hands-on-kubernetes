# 端到端微服务 Operator（项目 10 · 毕业项目）

> 一个 `MicroService` CR 编排完整微服务栈：ConfigMap + Deployment + Service + Ingress。
> 融合 Reconcile 幂等 / OwnerReference 级联 / status 上报 / 声明式 API 全部核心模式。

## 1. 架构总览

一个 CR 创建 4 种资源，全部挂 OwnerReference 实现级联清理。

## 2. 快速开始

```bash
make install && make run
kubectl apply -f config/samples/platform_v1_microservice.yaml
kubectl get microservice,deploy,svc,ingress -l app.kubernetes.io/name=user-service
```

## 3. 验收

- ✅ CR 创建后 ConfigMap/Deployment/Service/Ingress 全自动出现
- ✅ 删 CR 级联清理全部子资源

## 4. 文件结构

标准 kubebuilder 工程 + images/ 三件套。
