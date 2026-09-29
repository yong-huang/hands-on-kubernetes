# 09 · PyTorch 分布式训练 Operator：多 Pod 成员发现

> 编排 1 Master + N Worker 的分布式训练：Headless Service 提供 stable DNS，环境变量注入 MASTER_ADDR/MASTER_PORT/RANK/WORLD_SIZE，torchrun 据此完成成员发现与集合通信，训练完成后全部回收。读完本篇，你将理解分布式训练的"鸡生蛋"问题如何靠两件东西化解。

## Background

分布式训练的每个进程启动时都要回答两个问题："其他人在哪？"和"我是第几号？"——不知道就无法开始集合通信（collective communication，多进程同步交换数据的机制）。

手工搭这套拓扑要自己写 DNS 约定、算 RANK 序号、保证启动顺序，换个人跑就散架；进程规模一大（几十个 Worker），手工维护彻底不可行。

Operator 把这套约定固化成编排逻辑：用户声明 `workers: 2`，Controller 负责成员发现（Headless DNS）与身份分配（环境变量）——训练代码读标准约定变量即可，对编排方式一无所知。

## What

一个 `PyTorchJob` CR（Custom Resource：向 K8s API 注册的自定义资源对象）长这样：

```yaml
apiVersion: ai.example.com/v1
kind: PyTorchJob
metadata: { name: demo-ptjob }
spec:
  image: "pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime"
  command: ["python", "-c", "import torch; print(torch.__version__)"]
  workers: 2          # 1 Master + (workers-1) Worker
```

apply 后：Headless Service → Master Pod（rank 0）先起 → Worker Deployment 逐个加入 → 环境变量让所有进程互相发现 → 训练完成全部回收。

一句话心智模型：**分布式训练的"鸡生蛋"问题靠两件东西化解——Headless Service 给成员发现，环境变量给身份分配**。但和"写死一份 hosts 文件"不同的是，这套约定由 Controller 按声明动态生成，Worker 数量变了地址和序号自动跟着变。

| 注入物 | 作用 |
|---|---|
| Headless Service | DNS 直接返回全部 Pod IP，成员发现的基础 |
| MASTER_ADDR / MASTER_PORT | 指向 rendezvous（集合点）的 Master |
| RANK / WORLD_SIZE | "我是第几号 / 一共几号" |

## When to Use

典型场景：数据并行训练（每个 Worker 持一份数据分片，梯度集合通信同步）；需要弹性增减 Worker 数的实验环境；为算力平台补齐"多卡组网"这一层能力。

何时不用：单卡任务（operators/08 的单 Job 模式更简单）；需要容错弹性训练（Worker 挂了自动缩圈重训——那需要 etcd-backed rendezvous 与重试编排，本实验未覆盖）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 手工起容器 + hosts 文件 | 拓扑靠人 | 两三个进程的玩具 |
| PyTorchJob Operator（本实验） | 声明 Worker 数，自动组网 | 学习组网机制、单机多卡 |
| Kubeflow TrainingOperator | 多框架 + 弹性容错 | 生产级训练平台 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用。

```bash
cd operators/09_pytorch_operator
make install && make run
kubectl apply -f config/samples/ai_v1_pytorchjob.yaml
kubectl get pods -l app.kubernetes.io/framework=pytorch -w   # Master 先 Running，Worker 陆续加入
kubectl logs demo-ptjob-master                               # 看 torchrun 集合通信日志
```

诚实预期：Worker 不是同时就位的——Master 先 Running，Worker 逐个加入并在启动时等待集合；`kubectl logs` 里看到 rendezvous 成功（所有 RANK 到齐）才算组网完成。

## How It Works

Controller 编排四件套：

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

环境变量是 torchrun 的标准约定：`MASTER_ADDR` 指向 Master（Headless DNS 保证名字稳定）、`RANK` 标识进程序号、`WORLD_SIZE` 声明总成员数——训练代码读这几个变量即可完成初始化，对编排方式一无所知。

你在 `logs` 里看到的 rendezvous 成功日志，就是所有 RANK 按这套约定到齐的证据。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| Master 先起、Worker 陆续加入 | ✅ |
| Worker 环境变量正确指向 Master（MASTER_ADDR/RANK/WORLD_SIZE） | ✅ |
| 训练完成全部 Pod Succeeded 并回收 | ✅ |

## Pitfalls & Q&A

踩坑清单：

- 用普通 Service 做成员发现：VIP 随机转发，进程之间连不上指定对端——必须 Headless（labs/14）。
- WORLD_SIZE 与实际 Worker 数不一致：集合通信永远等不到全员，任务挂死在 rendezvous。
- Worker 数写在两处（CR 和 Deployment）：以 CR 为唯一事实源，Deployment 由 Controller 生成。

**Q1: 为什么 Headless Service 是分布式训练的标配？**

`clusterIP: None` 让 DNS 直接返回全部 Pod IP（见 labs/14），MPI/torchrun 这类需要"点对点互连"的框架靠它做成员发现——普通 Service 的 VIP 会随机转发，进程之间根本连不上指定对端。

**Q2: Worker 用 StatefulSet 还是 Deployment？**

需要稳定网络标识（RANK 绑定主机名、断线重连按名找对端）用 StatefulSet；无状态可互换的 Worker 用 Deployment 更简单——本项目选后者，因为每个 Worker 的 RANK 由环境变量显式分配，不依赖主机名。

生产框架（如 Kubeflow Training Operator）多为 StatefulSet 方案。

**Q3: 它和 operators/08 的 TrainingJob 是什么关系？**

AI 工作负载 Operator 的两条主线：单卡走扩展资源调度（operators/08，"给我一张卡"），多卡走多 Pod 编排 + 成员发现（本实验，"给我们组网"）。完整平台两者都要——先用单卡模式按卡排队，多卡任务再由本模式组网。
