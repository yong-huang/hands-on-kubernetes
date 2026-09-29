# 01 · 本地 Kubernetes 环境搭建：kind

> 用 kind 在本机 Docker 里拉起一个 **1 控制面 + 2 工作节点**的真实 Kubernetes 集群：`./setup.sh up` 一条命令建集群、验证、预载镜像、部署测试负载，`./setup.sh down` 一条命令删干净、零残留。读完本篇，你将拥有后续所有实验共用的这套集群，并理解"节点 = 容器"这个贯穿全系列的模型。

## Background

学 Kubernetes 最大的门槛不是概念，而是环境。在 kind 出现之前，常见的做法有三种：在云上开托管集群（按小时计费，不敢随意实验）；用公司共享集群（权限受限，删错对象就是事故）；用 minikube 在虚拟机里起单节点（开机慢、多节点支持弱）。

这些做法共同的痛点是"实验成本高"：集群坏了恢复慢，学习最需要的"反复试错"变成了奢侈品。kind 的思路是把节点降级为普通 Docker 容器——它是 Kubernetes 官方 CI 自己在用的工具，删集群就是删容器，零残留。

国内网络还有第二层障碍：节点内直连 docker.io 拉镜像会超时，本实验的脚本用 containerd 镜像源从根上解决。

## What

kind（Kubernetes IN Docker）把若干个 Docker 容器当作 K8s 节点，用 kubeadm 在里面装出完整的控制面和 kubelet。

一句话心智模型：**节点 = 容器**——`docker ps` 能直接看到这 3 个"节点"，`kind delete cluster` 就是删 3 个容器。

但和普通容器不同的是，这些容器之间组成了真正的主从关系：1 个 control-plane（控制面节点，跑 apiserver / etcd / scheduler / controller-manager，外加 CoreDNS Pod）负责"决策"，

2 个 worker（工作节点，跑 kubelet + containerd + kindnet）负责"干活"。

| 组件 | 位置 | 职责 |
|---|---|---|
| apiserver / etcd 等 | control-plane 容器 | 集群决策与状态存储 |
| kubelet / containerd | 每个 worker 容器 | 按"决策"启动真实容器 |
| kindnet | 每个 worker 容器 | Pod 之间通信的网络插件（CNI） |

## When to Use

典型场景：本地学习与实验（随时删建）；CI 里并行跑多套隔离集群；需要多节点拓扑做调度类实验（本系列 lab 10 的打散、lab 09 的扩缩都依赖它）。

何时不用：承载真实业务（kind 不是生产发行版）；机器资源紧张到跑不动 3 个节点容器（3 节点建议 Docker 虚拟机内存 ≥4GB）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| minikube | VM 或容器，`--nodes=N` 支持多节点 | 需要 VM 级隔离或 addons 生态 |
| k3s / k3d | 轻量二进制，约 30s 启动，组件可裁剪 | 边缘、低资源机器 |
| kind | 完整 kubeadm（K8s 官方建集群工具）集群、多节点一行配置 | 学习 / CI / 多节点拓扑（本系列选择） |

## Quick Start

前置条件：docker / kubectl / kind 已安装（没有的话先跑 [labs/00_setup_kind](../00_setup_kind/README.md) 的脚本）。

```bash
cd labs/01_setup_env
./setup.sh up        # 六步一条龙：建集群 -> 验证 -> 预载镜像 -> 部署 nginx
kubectl get nodes    # 诚实预期：3 个节点 Ready 即成功
kubectl get pods,svc -l app=nginx   # 测试负载已就绪
./setup.sh down      # 删集群（所有实验做完再来跑这句）
```

成功判据：`kubectl get nodes` 列出 3 个节点且 STATUS 全为 Ready；`kubectl get pods` 里 nginx Pod 为 Running——看到这两点即环境可用（具体节点名/IP 以实际运行为准）。

访问测试 Service：`kubectl port-forward svc/nginx 8080:80`，浏览器打开 `http://localhost:8080`。

脚本整体跑在 `set -euo pipefail` 下，任何一步失败立刻退出；创建前会先 `kind delete` 同名集群，保证可重复执行——这也是本系列脚本的通用约定。

## How It Works

`setup.sh` 六步的关键代码与机制：

**Step 1 前置检查**——kind 硬依赖 Docker daemon（节点就是容器）；用 `docker info` 而不是 `docker version` 探活，因为它真正反映 daemon 是否可用。

```bash
for cmd in docker kubectl kind; do
    command -v "${cmd}" >/dev/null 2>&1 || { echo "missing ${cmd}"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Docker daemon not running"; exit 1; }
```

**Step 2 生成集群配置**——多节点只是多写几行 `role: worker`，这是 kind 相对 minikube 最大的便利：

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: k8s-learn
nodes:
  - role: control-plane   # 1 个控制面节点
  - role: worker          # 2 个工作节点
  - role: worker
```

**Step 3 创建集群**——`--wait 120s` 让命令阻塞到控制面 Ready 才返回，后面的 kubectl 不会打空。

kind 内部依次做了：拉节点镜像 → 启动 3 个容器 → 第一个容器里 `kubeadm init` → 其余 `kubeadm join` → 装默认 CNI（kindnet）→ 写 kubeconfig 并切换 context。

```bash
kind create cluster --config manifests/kind-config.yaml --wait 120s
kubectl config use-context kind-k8s-learn
```

**Step 4 验证**——`kubectl wait` 是比 `sleep` 更可靠的等待方式：轮询直到条件满足才返回，不浪费一秒。

```bash
kubectl get nodes -o wide
kubectl cluster-info
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```

**Step 5 containerd 镜像源（根治节点拉镜像超时）**——kind 节点内的 containerd（节点里真正下载镜像的组件）直连 `docker.io` 在国内会 TLS 超时。

实测只有 docker.io 不可达，`quay.io` / `ghcr.io` / `gcr.io` / `registry.k8s.io` 均能直连，因此只需给 `docker.io` 配 daocloud 镜像源。

集群一建好，kubelet 就能直接拉 docker.io 镜像，无需任何手工导入。配置写在 `kind-config.yaml` 的 `containerdConfigPatches`（由 `setup.sh` 自动生成）：

```yaml
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://docker.m.daocloud.io"]
```

验证：集群建好后 `kubectl create deployment nginx --image=nginx:alpine`，Pod 直接 Running——节点自己就把镜像拉下来了。你在 Quick Start 里看到的"测试负载能就绪"，依赖的正是这一步。

**Step 6 部署测试负载**——一条龙跑通 Deployment → Pod → Service。Pod 能调度到 worker 节点并 Ready，说明整个数据面（kubelet + containerd + kindnet）工作正常——集群不只是"起来了"，而是"能用了"。

```bash
kubectl create deployment nginx --image=nginx:alpine
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl rollout status deployment/nginx --timeout=120s
```

**清理**：`kind delete cluster --name k8s-learn`（等价 `./setup.sh down`）。

个别仍不稳定的仓库（如 quay.io 上的 cert-manager / argocd 镜像，即便有镜像源也可能时好时坏）：若节点拉取超时，用仓库根 `scripts/load_images.sh` 从宿主机预载（宿主机直连那些仓库通常可达）。

离线兜底同理——宿主机拉 → `docker save` + `ctr images import` 灌入每个节点。

## Pitfalls & Q&A

踩坑清单：

- Docker 虚拟机内存给太小：3 节点建议 ≥4GB，Docker Desktop 在 Settings → Resources 调整，OrbStack 一般默认够用。
- 端口冲突或残留同名集群：先 `kind delete cluster` 再建。
- 代理软件劫持了 `127.0.0.1` 上的 API 端口：临时关代理或配置直连规则。

**Q1: 多套集群如何管理？**

kubeconfig 中一个集群对应一个 context（"连哪个集群、用哪个身份"的配置段）。`kind create cluster --name a` / `--name b` 可并存，`kubectl config use-context` 切换；

生产上常用 `kubectx` 工具，或用 `KUBECONFIG` 环境变量把不同环境的配置文件彻底分开。

**Q2: 为什么 Pod 一直 Pending？**

通常是没装 CNI 或资源不足。kind 默认装 kindnet；若配置了 `disableDefaultCNI: true` 需手动装 Calico/Flannel。`kubectl describe node` 看 Conditions、Taints 和容量即可定位。

**Q3: kind 里怎么访问 Service？**

NodePort 也无法直接从宿主机访问（节点在容器网络里，端口没映射到宿主机）。

方案：`kubectl port-forward`（最简单，本实验用的就是它）、在 kind-config 里配 `extraPortMappings` 把宿主机端口映射到节点、或装 Ingress（kind 官方提供 ingress-ready 的节点镜像）。
