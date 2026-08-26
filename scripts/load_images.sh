#!/usr/bin/env bash
# ============================================================
# 通用镜像预载脚本: 解决节点内拉取 docker.io TLS 超时问题
# 流程: 宿主机从镜像源拉取 -> docker save | ctr import 灌入所有节点
# 用法: ./load_images.sh [image1 image2 ...]   (无参数时加载下面默认列表)
# ============================================================
set -euo pipefail

CLUSTER_NAME="k8s-learn"
MIRROR="docker.m.daocloud.io"

# 系列所有项目用到的镜像 (library/ 前缀可省)
DEFAULT_IMAGES=(
    nginx:alpine
    nginx:1.25
    nginx:1.25-alpine
    nginx:1.27
    busybox:1.36
    busybox:1.37
    perl:5.34
    mysql:8.0
    curlimages/curl:8.8.0
)

IMAGES=("$@")
[ ${#IMAGES[@]} -eq 0 ] && IMAGES=("${DEFAULT_IMAGES[@]}")

# 镜像源路径: nginx:1.25 -> docker.m.daocloud.io/library/nginx:1.25
#             curlimages/curl:8.8.0 -> docker.m.daocloud.io/curlimages/curl:8.8.0
#             registry.k8s.io/x/y -> k8s.m.daocloud.io/x/y (daocloud 专用 K8s 源)
mirror_ref() {
    local img="$1"
    if [[ "$img" == registry.k8s.io/* ]]; then
        echo "k8s.m.daocloud.io/${img#registry.k8s.io/}"
    elif [[ "$img" == */* ]]; then
        echo "${MIRROR}/${img}"
    else
        echo "${MIRROR}/library/${img}"
    fi
}

echo "==== 1. 宿主机拉取镜像 (镜像源 ${MIRROR}) ===="
for img in "${IMAGES[@]}"; do
    if docker image inspect "${img}" >/dev/null 2>&1; then
        echo "[skip] ${img} 已存在"
        continue
    fi
    ref="$(mirror_ref "${img}")"
    echo "[pull] ${ref}"
    if docker pull "${ref}"; then
        docker tag "${ref}" "${img}"
    else
        echo "[warn] ${img} 拉取失败, 跳过" >&2
    fi
done

echo "==== 2. 获取集群节点 ===="
NODES=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
[ -z "$NODES" ] && { echo "[error] 没有可用节点, 集群 ${CLUSTER_NAME} 是否在运行?"; exit 1; }
echo "节点: ${NODES}"

echo "==== 3. 导入镜像到所有节点 ===="
for img in "${IMAGES[@]}"; do
    docker image inspect "${img}" >/dev/null 2>&1 || continue
    echo "[load] ${img}"
    for n in ${NODES}; do
        docker save "${img}" | docker exec --privileged -i "${n}" \
            ctr --namespace=k8s.io images import - >/dev/null 2>&1 \
            && echo "  -> ${n} OK" || echo "  -> ${n} FAILED" >&2
    done
done

echo "==== 完成。提示: 非 latest 标签默认 imagePullPolicy=IfNotPresent, 节点有镜像即不会再拉 ===="
