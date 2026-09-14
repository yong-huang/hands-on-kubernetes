#!/usr/bin/env bash
# ============================================================
# 统一的 kind 集群创建脚本: 创建时自动注入 containerd 镜像源
#
# 为什么需要它: kind 节点内的 containerd 直连 docker.io 在国内会
# TLS 超时(实测只有 docker.io 不可达; quay.io/ghcr.io/gcr.io/
# registry.k8s.io 均可直连)。因此只对 docker.io 配 daocloud 镜像源,
# kubelet 可以直接拉 docker.io 镜像, 无需走 "宿主机 save -> ctr import"。
#
# 注意: 个别仓库(如 quay.io 的 cert-manager/argocd)即使有镜像源也可能
# 不稳定, 若节点拉取超时, 用 scripts/load_images.sh 从宿主机预载即可。
#
# 用法: ./kind-cluster.sh <name> [控制面数] [工作节点数]
#   示例: ./kind-cluster.sh k8s-learn 1 2
#         ./kind-cluster.sh member-us  1 1
# ============================================================
set -euo pipefail

NAME="${1:?用法: ./kind-cluster.sh <name> [cp] [worker]}"
CP="${2:-1}"
WORKERS="${3:-2}"

CONFIG="$(mktemp)"
trap 'rm -f "$CONFIG"' EXIT

{
    echo "kind: Cluster"
    echo "apiVersion: kind.x-k8s.io/v1alpha4"
    echo "name: ${NAME}"
    echo "containerdConfigPatches:"
    echo "  - |-"
    echo "    [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"docker.io\"]"
    echo "      endpoint = [\"https://docker.m.daocloud.io\"]"
    echo "nodes:"
    for ((i=1;i<=CP;i++)); do
        r="worker"; [ "$i" -eq 1 ] && r="control-plane"
        echo "  - role: ${r}"
    done
    for ((i=1;i<=WORKERS;i++)); do
        echo "  - role: worker"
    done
} > "$CONFIG"

echo "[create] kind 集群 ${NAME} (cp=${CP} worker=${WORKERS}, 已配 containerd 镜像源)"
kind delete cluster --name "${NAME}" >/dev/null 2>&1 || true
kind create cluster --name "${NAME}" --config "$CONFIG" --wait 180s