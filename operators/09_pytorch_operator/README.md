# PyTorch 分布式训练 Operator（项目 9）

> 编排 1 Master + N Worker 的分布式训练：Headless Service 成员发现，环境变量注入
> MASTER_ADDR/MASTER_PORT/RANK/WORLD_SIZE，训练完成后自动回收。

## 1. 架构总览

Master Pod（rank 0）先启动 → Worker Deployment 逐个加入 → torchrun 通过
MASTER_ADDR 互相发现并同步。Headless Service 提供稳定 DNS。

## 2. 快速开始

```bash
make install && make run
kubectl apply -f config/samples/ai_v1_pytorchjob.yaml
kubectl get pytorchjob,pods,deploy,svc -l app.kubernetes.io/framework=pytorch
```

## 3. 文件结构

标准 kubebuilder 工程 + images/ 三件套。
