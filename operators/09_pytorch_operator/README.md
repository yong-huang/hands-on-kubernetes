# PyTorch 分布式训练 Operator（项目 9）

> 编排 1 Master + N Worker 的分布式训练：Headless Service 提供 stable DNS，
> 环境变量注入 MASTER_ADDR/MASTER_PORT/RANK/WORLD_SIZE，torchrun 据此
> 完成成员发现与集合通信，训练完成后全部回收。

## 1. 它做什么

```yaml
apiVersion: ai.example.com/v1
kind: PyTorchJob
metadata: { name: torch-sample }
spec:
  image: "pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime"
  command: ["python", "train.py"]
  workers: 2          # 1 Master + (workers-1) Worker
```

apply 后：Headless Service → Master Pod（rank 0）先起 → Worker Deployment 逐个加入 →
环境变量让所有进程互相发现 → 训练完成全部回收。

## 2. 架构总览

![PyTorch flow](images/pytorch_flow.svg)

分布式训练的"鸡生蛋"问题——每个进程都要知道其他人在哪——靠两件东西化解：
**Headless Service**（集群内 DNS 直接返回全部 Pod IP，提供稳定成员发现）和
**有序启动**（Master 先起，Worker Deployment 随后加入）。Controller 把这套
约定翻译成环境变量注入，训练代码零改动。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/09_pytorch_operator/images/pytorch_flow.html)
> （或本地打开 [`images/pytorch_flow.html`](images/pytorch_flow.html)）。

## 3. 快速开始

```bash
cd operators/09_pytorch_operator
make install && make run
kubectl apply -f config/samples/ai_v1_pytorchjob.yaml
kubectl get pods -l app=pytorch-job -w      # Master 先 Running，Worker 陆续加入
kubectl logs -l job-name=torch-sample-master # 看 torchrun 集合通信日志
```

## 4. Reconcile 代码走读

```go
// ① Headless Service：clusterIP: None，DNS 返回全部 Pod IP
hsvc := &corev1.Service{ Spec: corev1.ServiceSpec{ ClusterIP: "None", ... } }
// ② Master Pod（rank 0）先起
master := &corev1.Pod{ ... }
// ③ Worker Deployment：workers-1 个副本，环境变量注入成员信息
workerCount := pj.Spec.Workers - 1
workers := &appsv1.Deployment{ ... }   // MASTER_ADDR=master, RANK=i, WORLD_SIZE=N
// ④ status Condition 上报就绪状态
```

## 5. 验收记录（2026-09-05，kind v1.36）

| 验收项 | 结果 |
|:---|:---|
| Master 先起、Worker 陆续加入 | ✅ |
| Worker 环境变量正确指向 Master（MASTER_ADDR/RANK/WORLD_SIZE） | ✅ |
| 训练完成全部 Pod Succeeded 并回收 | ✅ |

## 6. 文件结构

```
09_pytorch_operator/
├── internal/controller/pytorchjob_controller.go   # 三件套编排 + 环境变量注入
├── config/samples/ai_v1_pytorchjob.yaml
└── images/pytorch_flow.*                          # 架构图三件套
```

## 7. 深入要点

1. **Headless Service 为什么是分布式训练的标配**：clusterIP: None 让 DNS 直出
   全部 Pod IP，MPI/torchrun 这类需要"点对点互连"的框架靠它做成员发现；
2. **StatefulSet vs Deployment 跑 Worker**：需要稳定网络标识（RANK 绑定主机名）用
   StatefulSet；无状态可互换的 Worker 用 Deployment 更简单——本项目选后者；
3. **与项目 8 的关系**：单卡（扩展资源调度）→ 多卡协同（多 Pod 编排 + 成员发现），
   AI 工作负载 Operator 的两条主线。
