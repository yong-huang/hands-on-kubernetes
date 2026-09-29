# 00 · 工具准备：安装 kind 与 kubectl

> 本实验把本机工具准备好：kind 用 Docker 容器模拟 K8s（Kubernetes 的缩写，下同）节点，一分钟拉起一套可反复销毁的本地集群；kubectl 是与集群对话的命令行客户端。读完本篇，你将装好这两件工具并验证版本，具备跑通整个系列的最低环境。

## Background

在 K8s 上做任何实验之前，先要有一个集群。以前的选择都不便宜：云上托管集群按小时计费，搞坏了重建要等；minikube 依赖虚拟机，开机慢、占内存；公司里的共享集群不敢乱敲命令——删错一个对象就是事故。

另一个前置问题是版本混乱。kubectl 与集群有版本兼容窗口，手工从官网下载二进制时经常装到不匹配的版本，排查半天才发现是工具本身的问题。

kind 正是为此而生——它是 Kubernetes 官方 CI 自己在用的工具，把"造一套集群"的成本压到"造几个容器"。系列第一步就是把"装什么、怎么装、怎么验证"固化成一个可重复执行的脚本。

## What

本实验安装两件工具：

- **kind**（Kubernetes IN Docker）：把若干个 Docker 容器当作 K8s 节点，在里面跑真实的控制面组件（控制面 = K8s 的管理与决策组件层，负责调度决策与状态维护）。一句话心智模型：**集群即容器**——但和普通容器不同的是，这些容器里装着完整的 Kubernetes，删掉重建的代价只是几秒。
- **kubectl**：K8s 的命令行客户端，后续所有实验的"创建、观察、排查"都通过它完成。可以把 kubectl 想象成集群的遥控器；但和电视遥控器不同的是，它发给谁由 kubeconfig 文件里的 context 决定，切换集群就是切换配置。

| 工具 | 角色 |
|---|---|
| kind | 提供集群本体（节点 = 容器） |
| kubectl | 操作集群的客户端 |
| Docker | kind 的运行前提（节点就是容器） |

## When to Use

这套本地方案适合的场景：学 K8s 需要随时搞坏、搞坏秒重建的集群；CI 里要并行跑多套隔离环境；想在本机模拟多节点拓扑。

不适合的场景：承载真实业务（kind 是学习与测试工具，不是发行版）；需要模拟真实操作系统层故障（节点是容器，内核与宿主机共享）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| minikube | 默认跑在虚拟机里，启动慢但隔离更彻底 | 需要 VM 级隔离或 addons 生态 |
| k3d / k3s | 轻量二进制，最快（约 30s） | 低资源机器、边缘场景 |
| kind | 容器当节点的完整 kubeadm（K8s 官方建集群工具）集群 | 学习 / CI / 多节点拓扑（本系列选择） |

## Quick Start

前置条件：Docker 已安装且 daemon 在运行（Docker Desktop 或 Docker Engine），kind 的节点就是 Docker 容器。

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

诚实预期：国内网络下载 GitHub Releases 与 dl.k8s.io 可能很慢，属于网络问题而非脚本故障；工具已安装时脚本会跳过，可重复执行。

工具就绪后，进入 [01_setup_env](../01_setup_env/README.md) 创建学习集群。

## How It Works

脚本对安装路径做了优先级决策，核心是"能用包管理器就不手工下载"：

| 场景 | 安装方式 |
|---|---|
| macOS 有 Homebrew | `brew install kind kubectl`（脚本检测到 brew 自动走这条路） |
| 无 brew（Linux / 裸 macOS） | 从 GitHub Releases / dl.k8s.io 下载官方二进制，`sudo` 移入 `/usr/local/bin`；兜底版本在脚本头部的 `KIND_VERSION` / `KUBECTL_VERSION` 定义 |

包管理器路径的优势是升级与卸载都归 brew 管；二进制路径的优势是不依赖任何包管理器，两条路径兜底版本一致，保证实验行为可复现。

脚本可重复执行的原因：每一步安装前先检查目标是否已存在（`command -v` 探测），已安装则跳过——所以重复运行不会覆盖已有版本。

## Pitfalls & Q&A

踩坑清单：

- Docker daemon 没启动：`setup_kind.sh verify` 能过（只查客户端版本），但后续集群起不来。判断方法：`docker info` 报错就是 daemon 未运行。
- 国内网络下载超时：可自行把脚本里的 URL 换成镜像代理；Docker 本体没装的话 kind 起不来，先装 Docker Desktop 或 Docker Engine。
- `sudo` 移动二进制后命令找不到：检查 `/usr/local/bin` 是否在 `PATH` 里（`echo $PATH`）。

**Q：为什么不直接用 minikube 或 Docker Desktop 自带的 K8s？**

都能用，但 kind 的优势在本系列里是刚需：节点是普通容器，`kind delete cluster` 后秒级重建，多节点拓扑（后面测调度、亲和性会用到）配置就是一份 YAML。Docker Desktop 自带的 K8s 是单节点黑盒，坏了修复成本高；minikube 走虚拟机，启动慢、资源占用大。
