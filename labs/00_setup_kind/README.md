# 00 · 工具准备：安装 kind 与 kubectl

> 本实验把本机工具准备好：kind 用 Docker 容器模拟 K8s 节点，一分钟拉起一套可反复销毁的本地集群；kubectl 是与集群对话的命令行客户端。这两件工具是整个系列的底座。

## What

- **kind**（Kubernetes IN Docker）：把若干个 Docker 容器当作 K8s 节点，在上面跑一套真实的控制面和 kubelet。一句话心智模型：**集群即容器，删了重建零成本**。
- **kubectl**：K8s 的命令行客户端，所有实验里"创建、观察、排查"都通过它完成。

## Why

学 K8s 需要一个随时能搞坏、搞坏能秒重建的集群。云上集群慢且花钱，minikube 单节点虚拟机重；kind 直接复用本机 Docker，多节点集群几十秒起步，实验之间互不污染——这也是它在 CI 里成为事实标准的原因。前提只有一个：Docker 本身要先装好（Docker Desktop 或 Docker Engine），因为 kind 的节点就是容器。

## How

```bash
cd labs/00_setup_kind
./setup_kind.sh          # 安装 kind + kubectl 并验证
./setup_kind.sh verify   # 只验证版本
```

安装完成的验证输出：

```console
$ kind version
kind v0.25.0 go1.24.1 darwin/arm64
$ kubectl version --client
Client Version: v1.31.0
```

工具就绪后，进入 [01_setup_env](../01_setup_env/README.md) 创建学习集群。

## Deep Dive

脚本对安装路径做了优先级决策，且可重复执行（已装的工具自动跳过）：

| 场景 | 安装方式 |
|---|---|
| macOS 有 Homebrew | `brew install kind kubectl`（脚本检测到 brew 自动走这条路） |
| 无 brew（Linux / 裸 macOS） | 从 GitHub Releases / dl.k8s.io 下载官方二进制，`sudo` 移入 `/usr/local/bin`；兜底版本在脚本头部的 `KIND_VERSION` / `KUBECTL_VERSION` 定义 |

国内网络的两个坑：GitHub / dl.k8s.io 下载慢，可自行把脚本里的 URL 换成镜像代理；Docker 本体没装的话 kind 起不来，先装 Docker Desktop 或 Docker Engine。

## Q&A

**Q：为什么不直接用 minikube 或 Docker Desktop 自带的 K8s？**
都能用，但 kind 的优势在本系列里是刚需：节点是普通容器，`kind delete cluster` 后秒级重建，多节点拓扑（后面测调度、亲和性会用到）配置就是一份 YAML。Docker Desktop 自带的 K8s 是单节点黑盒，坏了修复成本高；minikube 走虚拟机，启动慢、资源占用大。
