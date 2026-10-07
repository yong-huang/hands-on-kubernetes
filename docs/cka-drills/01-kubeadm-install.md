# CKA 开工包 · 项目 1：kubeadm 从零安装集群（lima 真机版）

> 对应清单：`docs/cka.md` 项目 1 ｜ 环境：lima VM `cka-vm`（Ubuntu 24.04，4C/8G/40G，kubeadm v1.33.13）｜ 实测日期：2026-10-07
> **killercoda 的完整替代**：真 systemd、真 kubeadm、全流程可重置（`kubeadm reset` + `limactl delete`）。
> 先闭卷自做，再对照。

## ✅ 实测全流程（含全部踩坑）

```bash
# 0. VM 准备（宿主机，约 5 分钟，镜像已缓存则更快）
brew install lima
limactl create --plain --name cka-vm --cpus 4 --memory 8 --disk 40 template://ubuntu-24.04
limactl start cka-vm                    # ⚠️ 必须 --plain：默认模板装 nerdctl 走 GitHub（被墙）
limactl shell cka-vm                    # 用户名继承宿主（hyhit），不是 ubuntu！

# 1. 节点前置（swap/内核/containerd/pkgs.k8s.io），见 kubeadm-prereq 要点：
sudo swapoff -a; modprobe overlay br_netfilter; sysctl net.ipv4.ip_forward=1
# containerd config default 后必须改：SystemdCgroup = true
# apt 源: pkgs.k8s.io/core:/stable:/v1.33/deb（宿主机实测 302 可达）
apt-get install -y containerd kubelet kubeadm kubectl && apt-mark hold kubelet kubeadm kubectl

# 2. kubeadm init
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config

# 3. CNI（flannel；yaml 从 gh-proxy 拉，镜像 VM 直拉 ghcr.io 实测可达）
curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml" -o /tmp/kube-flannel.yml
kubectl apply -f /tmp/kube-flannel.yml
# ~2 分钟后节点 Ready；busybox Pod 能拿到 Pod IP 即数据面通
```

## ⚠️ 五大踩坑（每个都是 30 分钟级，照抄可绕）

1. **lima 默认模板装 nerdctl 走 GitHub → i/o timeout**：用 `--plain` 模式（纯 VM，运行时自己装）。
2. **VM 内直拉 registry.k8s.io 卡死**：控制面 7 个镜像在**宿主机** `docker pull`（慢通）→ `docker save` → `limactl cp` → `ctr -n k8s.io images import`。⚠️ 宿主机 kind 节点里验证过的 `crictl images` 在 lima VM 是**没装这个二进制**，静默失败——用 `ctr -n k8s.io images list`。
3. **sandbox 镜像 tag 不匹配（kubeadm init 卡 wait-control-plane）**：containerd 2.2.x 默认 `sandbox_image = registry.k8s.io/pause:3.10.1`，kubeadm 只导入 3.10 → 沙箱创建失败、静态 pod 全部起不来。修法：`sed -i 's|pause:3.10.1|pause:3.10|' /etc/containerd/config.toml && systemctl restart containerd`。**journalctl 里的 "failed to get sandbox image" 是判据。**
4. **etcd 镜像是 distroless**（无 `sh`）：`kubectl exec etcd-pod -- sh -c "..."` 直接挂——直接 exec `etcdctl` 二进制（ETCDCTL_API=3 已是默认）。
5. **lima VM 会自己停**（闲置）：`limactl start cka-vm` 秒级恢复，VM 内 /tmp 会被清——重要文件放 $HOME。

## 🎓 对照考纲（本题覆盖点）

- kubeadm init 的前置检查链：swap→内核→runtime（SystemdCgroup）→kubelet 起来等 manifest
- 控制面组件全部以静态 pod 形式出现：`/etc/kubernetes/manifests/` 四件套
- kubeconfig 三件套（admin.conf 是 kubernetes-admin@lima-cka-vm）
- join token 输出（本项目单机，worker join 留作扩展）
- CNI 是节点 Ready 的前提：NotReady 事件的 network plugin is not ready

## 🧹 重练

```bash
limactl shell cka-vm -- sudo kubeadm reset -f   # 软重置（VM 内重跑 init）
limactl delete -f cka-vm && limactl create --plain ...  # 硬重置（重新导镜像）
```
