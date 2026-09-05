# ops-automation Operator（项目 4）

> 定时扩缩容 + 滚动重启：Controller 每 30s 检查 Cron 规则匹配当前时间并调整目标
> Deployment 副本数；另支持注解触发逐 Pod 滚动重启——两个最常用的运维动作。

## 1. 架构总览

![ops flow](images/ops_flow.svg)

## 2. 快速开始

```bash
make install && make run
# 另终端
kubectl create deployment ops-target-nginx --image=nginx:alpine --replicas=3
kubectl apply -f config/samples/ops_v1_scaler.yaml
# 等 cron 触发，观察副本数变化
kubectl annotate deployment ops-target-nginx ops.example.com/rolling-restart=true
```

## 3. 文件结构

```
04_ops_automation/
├── README.md
├── main.go → cmd/main.go
├── api/v1/
├── internal/controller/    # scaler + restart 双控制器
├── config/
└── images/（三件套）
```
