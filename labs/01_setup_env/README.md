# 01 · 本地 Kubernetes 环境搭建：kind

> 用 kind 在本机 Docker 里拉起一个 **1 控制面 + 2 工作节点**的真实 Kubernetes 集群：`./setup.sh up` 一条命令建集群、验证、预载镜像、部署测试负载，`./setup.sh down` 一条命令删干净、零残留。

## What

kind（Kubernetes IN Docker）把若干个 Docker 容器当作 K8s 节点，用 kubeadm 在里面装出完整的控制面和 kubelet。一句话心智模型：**节点 = 容器**——`docker ps` 能直接看到这 3 个"节点"，`kind delete cluster` 就是删 3 个容器。

建成后的拓扑：kubectl 通过 `~/.kube/config` 里的 context（`kind-k8s-learn`）连向宿主机 Docker daemon（OrbStack 或 Docker Desktop 均可）；daemon 里跑着 3 个容器——1 个 control-plane（apiserver / etcd / scheduler / controller-manager，外加 CoreDNS Pod）和 2 个 worker（kubelet + containerd + kindnet，里面跑 nginx 测试 Pod）。

## Why

学 Kubernetes 最大的门槛不是概念，而是**环境**：云上集群要花钱，公司集群不敢乱搞。本地搭一套随时可删可重建的集群，错了就 `kind delete cluster` 重来，零成本。本地主流方案对比：

| 维度 | kind | minikube | k3s / k3d |
|------|------|----------|-----------|
| 实现方式 | Docker 容器当节点（kubeadm） | VM 或容器 | 轻量二进制 / 容器里装 k3s |
| 启动速度 | 快（3 节点约 1 分钟） | 慢（VM 开机） | 最快（约 30s） |
| 多节点 | 配置文件里多写几行 `role: worker` | `--nodes=N` | 支持 |
| 多集群并存 | `--name` 即可 | profile 机制 | 多实例 |
| 真实度 | 完整 kubeadm 集群 | 完整 | 裁剪版（默认 Flannel + Traefik，组件可裁可换） |
| 适用场景 | 学习 / CI / 多节点拓扑 | 单节点入门 | 边缘 / 低资源机器 |

本系列选 kind：它是 Kubernetes 官方跑自己 CI 的工具，多节点支持一行配置，行为与生产集群最接近——control-plane 与 worker 角色分离的拓扑能真实复现，后面实验里的调度、拓扑打散、节点维护才有戏可演。

## How

```bash
# 前置：docker / kubectl / kind 已安装（没有的话先跑 labs/00_setup_kind/setup_kind.sh）
cd labs/01_setup_env
./setup.sh up        # 六步一条龙：建集群 -> 验证 -> 预载镜像 -> 部署 nginx
kubectl get nodes    # 诚实预期：3 个节点 Ready 即成功
kubectl get pods,svc -l app=nginx   # 测试负载已就绪
./setup.sh down      # 删集群（所有实验做完再来跑这句）
```

访问测试 Service：`kubectl port-forward svc/nginx 8080:80`，浏览器打开 `http://localhost:8080`。

脚本整体跑在 `set -euo pipefail` 下，任何一步失败立刻退出；创建前会先 `kind delete` 同名集群，保证可重复执行——这也是本系列脚本的通用约定。

## Deep Dive

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

**Step 3 创建集群**——`--wait 120s` 让命令阻塞到控制面 Ready 才返回，后面的 kubectl 不会打空。kind 内部依次做了：拉节点镜像 → 启动 3 个容器 → 第一个容器里 `kubeadm init` → 其余 `kubeadm join` → 装默认 CNI（kindnet）→ 写 kubeconfig 并切换 context。

```bash
kind create cluster --config manifests/kind-config.yaml --wait 120s
kubectl config use-context kind-k8s-learn
```

**Step 4 验证**——`kubectl wait` 是比 `sleep` 优雅得多的等待原语：轮询直到条件满足，满足即返回，不浪费一秒。

```bash
kubectl get nodes -o wide
kubectl cluster-info
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```

**Step 5 containerd 镜像源（根治节点拉镜像超时）**——kind 节点内的 containerd 直连 `docker.io` 在国内会 TLS 超时。实测只有 docker.io 不可达，`quay.io` / `ghcr.io` / `gcr.io` / `registry.k8s.io` 均能直连，因此只需给 `docker.io` 配 daocloud 镜像源。集群一建好，kubelet 就能直接拉 docker.io 镜像，无需任何手工导入。配置写在 `kind-config.yaml` 的 `containerdConfigPatches`（由 `setup.sh` 自动生成）：

```yaml
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://docker.m.daocloud.io"]
```

验证：集群建好后 `kubectl create deployment nginx --image=nginx:alpine`，Pod 直接 Running——节点自己就把镜像拉下来了。

**Step 6 部署测试负载**——一条龙跑通 Deployment → Pod → Service。Pod 能调度到 worker 节点并 Ready，说明整个数据面（kubelet + containerd + kindnet）工作正常——集群不只是"起来了"，而是"能用了"。

```bash
kubectl create deployment nginx --image=nginx:alpine
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl rollout status deployment/nginx --timeout=120s
```

**清理**：`kind delete cluster --name k8s-learn`（等价 `./setup.sh down`）。

个别仍不稳定的仓库（如 quay.io 上的 cert-manager / argocd 镜像，即便有镜像源也可能时好时坏）：若节点拉取超时，用仓库根 `scripts/load_images.sh` 从宿主机预载（宿主机直连那些仓库通常可达）。离线兜底同理——宿主机拉 → `docker save` + `ctr images import` 灌入每个节点。

## Q&A

**Q1: 多套集群如何管理？**
kubeconfig 中一个集群对应一个 context。`kind create cluster --name a` / `--name b` 可并存，`kubectl config use-context` 切换；生产上常用 `kubectx` 工具，或用 `KUBECONFIG` 环境变量把不同环境的配置文件彻底分开。

**Q2: 集群创建失败的常见原因？**
① Docker daemon 未运行或版本过旧；② 拉节点镜像超时（国内网络，可给 kind 配镜像源或 `kind load` 预载节点镜像）；③ 端口冲突/残留同名集群——先 `kind delete cluster`；④ Docker 虚拟机内存给太小（3 节点建议 ≥4GB，Docker Desktop 在 Settings → Resources 调整，OrbStack 一般默认够用）；⑤ 代理劫持了 127.0.0.1 上的 API 端口。

**Q3: 为什么 Pod 一直 Pending？**
通常是没装 CNI 或资源不足。kind 默认装 kindnet；若配置了 `disableDefaultCNI: true` 需手动装 Calico/Flannel。`kubectl describe node` 看 Conditions、Taints 和容量即可定位。

**Q4: kind 里怎么访问 Service？**
NodePort 也无法直接从宿主机访问（节点在容器网络里，端口没映射到宿主机）。方案：`kubectl port-forward`（最简单，本实验用的就是它）、在 kind-config 里配 `extraPortMappings` 把宿主机端口映射到节点、或装 Ingress（kind 官方提供 ingress-ready 的节点镜像）。
