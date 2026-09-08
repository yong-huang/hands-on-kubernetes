#!/usr/bin/env bash
# ============================================================
# 通用镜像预载脚本: 解决节点内拉取 docker.io TLS 超时问题
# 流程: 宿主机从镜像源拉取 -> docker save | ctr import 灌入所有节点
#       -> 逐节点校验, 有缺失则以非零码退出
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
    nginx:1.26
    nginx:1.27
    busybox:1.36
    busybox:1.37
    perl:5.34
    mysql:8.0
    curlimages/curl:8.8.0
)

IMAGES=("$@")
[ ${#IMAGES[@]} -eq 0 ] && IMAGES=("${DEFAULT_IMAGES[@]}")

# ---- docker context 自适应 -------------------------------
# kind 集群跑在哪个 daemon 里 (OrbStack / Docker Desktop / colima ...),
# 就用哪个 context 操作; 当前 context 看不到集群容器时自动探测 orbstack
SEED_NODE="${CLUSTER_NAME}-control-plane"
DOCKER=(docker)
if ! docker ps --format '{{.Names}}' | grep -qx "${SEED_NODE}"; then
    if docker --context orbstack ps --format '{{.Names}}' 2>/dev/null | grep -qx "${SEED_NODE}"; then
        DOCKER=(docker --context orbstack)
        echo "[info] 当前 docker context 看不到集群, 已自动切换到 orbstack context"
    else
        echo "[error] 当前 docker context 与 orbstack 里都找不到集群 ${CLUSTER_NAME}, 请先创建" >&2
        exit 1
    fi
fi

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

# ctr 内的完整引用: nginx:1.25 -> docker.io/library/nginx:1.25
cri_ref() {
    local img="$1"
    if [[ "$img" == */* ]]; then
        echo "docker.io/${img}"
    else
        echo "docker.io/library/${img}"
    fi
}

FAILED=()

echo "==== 1. 宿主机拉取镜像 (镜像源 ${MIRROR}) ===="
for img in "${IMAGES[@]}"; do
    if "${DOCKER[@]}" image inspect "${img}" >/dev/null 2>&1; then
        echo "[skip] ${img} 已存在"
        continue
    fi
    ref="$(mirror_ref "${img}")"
    echo "[pull] ${ref}"
    if "${DOCKER[@]}" pull -q "${ref}"; then
        "${DOCKER[@]}" tag "${ref}" "${img}"
    else
        echo "[warn] ${img} 拉取失败" >&2
        FAILED+=("${img}")
    fi
done

echo "==== 2. 获取集群节点 ===="
NODES=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
[ -z "$NODES" ] && { echo "[error] 没有可用节点, 集群 ${CLUSTER_NAME} 是否在运行?"; exit 1; }
echo "节点: ${NODES}"

echo "==== 3. 导入镜像到所有节点 ===="
for img in "${IMAGES[@]}"; do
    "${DOCKER[@]}" image inspect "${img}" >/dev/null 2>&1 || continue
    echo "[load] ${img}"
    for n in ${NODES}; do
        "${DOCKER[@]}" save "${img}" | "${DOCKER[@]}" exec --privileged -i "${n}" \
            ctr --namespace=k8s.io images import - >/dev/null 2>&1 \
            && echo "  -> ${n} OK" || { echo "  -> ${n} FAILED" >&2; FAILED+=("${img}@${n}"); }
    done
done

echo "==== 4. 逐节点校验 ===="
MISSING=()
for n in ${NODES}; do
    refs=$("${DOCKER[@]}" exec "${n}" ctr --namespace=k8s.io images list -q 2>/dev/null)
    for img in "${IMAGES[@]}"; do
        grep -qx "$(cri_ref "${img}")" <<<"$refs" || MISSING+=("${img}@${n}")
    done
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[error] 以下镜像在节点上缺失:" >&2
    printf '  %s\n' "${MISSING[@]}" >&2
    exit 1
fi
echo "全部镜像在所有节点就绪"

# 宿主机拉取失败但镜像已在节点上的情况不算失败 (例如之前已灌过)
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "[warn] 宿主机拉取/导入失败过: ${FAILED[*]} (节点已齐全则无碍)" >&2
fi
