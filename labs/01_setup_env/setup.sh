#!/usr/bin/env bash
# ============================================================
# 01_setup_env: 使用 kind 搭建本地 Kubernetes 学习环境
# 流程: 检查依赖 -> 生成集群配置(含 containerd 镜像源) -> 创建集群 -> 验证 -> 部署测试负载
# 用法: ./setup.sh [up|down|load]
#   up   完整搭建 (默认)
#   down 删除集群
#   load 离线兜底: 宿主机拉镜像再灌入节点 (镜像源不可用时用)
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

CLUSTER_NAME="k8s-learn"
CONFIG_FILE="manifests/kind-config.yaml"
TEST_IMAGE="nginx:alpine"
# 国内网络无法直连 registry-1.docker.io, 走镜像源拉取后灌入节点
MIRROR_PREFIX="docker.m.daocloud.io/library"

# ---------- 清理函数: 删除集群 ----------
teardown() {
    echo "========== Teardown =========="
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "[done] 集群 ${CLUSTER_NAME} 已删除"
}

# ---------- Step 1: 检查前置依赖 ----------
check_deps() {
    echo "========== Step 1: 检查前置依赖 =========="
    # kind 的节点本质是 Docker 容器, Docker 是硬依赖
    for cmd in docker kubectl kind; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "[error] 未找到 ${cmd}, 请先安装 (kind/kubectl 可运行 ../00_setup_kind/setup_kind.sh)" && exit 1
        fi
    done
    echo "docker  : $(docker  --version)"
    echo "kubectl : $(kubectl version --client -o yaml 2>/dev/null | grep 'gitVersion' | head -1 || kubectl version --client | head -1)"
    echo "kind    : $(kind   --version)"
    # Docker daemon 必须在运行状态
    docker info >/dev/null 2>&1 || { echo "[error] Docker daemon 未运行"; exit 1; }
}

# ---------- Step 2: 生成 kind 集群配置 ----------
gen_config() {
    echo "========== Step 2: 生成 ${CONFIG_FILE} =========="
    # containerdConfigPatches: 给节点内的 containerd 配国内镜像源。
    # 实测 kind 节点只有 docker.io 不可达(直连 TLS 超时); quay.io/ghcr.io/
    # gcr.io/registry.k8s.io 均可直连, 无需镜像源(反而拖慢)。配好 docker.io
    # 镜像源后 kubelet 可直接拉镜像, 摆脱 "宿主机 save -> ctr import"。
    # 个别仍不稳定的仓库(如 quay.io cert-manager), 用 scripts/load_images.sh 预载。
    cat > "${CONFIG_FILE}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://docker.m.daocloud.io"]
nodes:
  - role: control-plane   # 1 个控制面节点
  - role: worker          # 2 个工作节点
  - role: worker
EOF
    echo "[done] 配置已写入 ${CONFIG_FILE} (含 containerd 镜像源)"
}

# ---------- Step 3: 创建集群 ----------
create_cluster() {
    echo "========== Step 3: 创建集群 =========="
    # 已存在同名集群则先删除, 保证脚本可重复执行
    kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    kind create cluster --config "${CONFIG_FILE}" --wait 120s
    # kind 会自动把 kubectl 的当前 context 切到 kind-<name>
    kubectl config use-context "kind-${CLUSTER_NAME}"
}

# ---------- Step 4: 验证集群 ----------
verify() {
    echo "========== Step 4: 验证集群 =========="
    kubectl get nodes -o wide
    kubectl cluster-info
    # 等待所有节点 Ready (控制面组件启动需要几秒)
    kubectl wait --for=condition=Ready nodes --all --timeout=180s
}

# ---------- Step 5: 预加载测试镜像 (离线兜底, 平时无需执行) ----------
# 集群已通过 containerdConfigPatches 配好镜像源, kubelet 能直接拉取。
# 仅当镜像源不可用(如完全离线)才需要: 宿主机拉镜像 -> ctr import 灌入节点。
load_test_image() {
    echo "========== Step 5: 预加载测试镜像 ${TEST_IMAGE} =========="
    # 5.1 宿主机从镜像源拉取 (已存在则跳过)
    if ! docker image inspect "${TEST_IMAGE}" >/dev/null 2>&1; then
        echo "[pull] 从镜像源拉取 ${MIRROR_PREFIX}/${TEST_IMAGE} ..."
        docker pull "${MIRROR_PREFIX}/${TEST_IMAGE}"
        docker tag  "${MIRROR_PREFIX}/${TEST_IMAGE}" "${TEST_IMAGE}"
    fi
    # 5.2 导入所有 kind 节点。
    # 注意: kind load 对部分镜像源导出的 manifest 会报 digest not found,
    # 直接用 ctr images import 最稳 (不带 --all-platforms/--digests)。
    local nodes
    nodes=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
    for n in ${nodes}; do
        echo "[load] 导入节点 ${n}"
        docker save "${TEST_IMAGE}" | docker exec --privileged -i "${n}" ctr --namespace=k8s.io images import -
    done
}

# ---------- Step 6: 部署测试负载 ----------
deploy_test() {
    echo "========== Step 6: 部署 nginx 测试负载 =========="
    kubectl create deployment nginx --image="${TEST_IMAGE}"
    kubectl expose deployment nginx --port=80 --type=NodePort
    kubectl rollout status deployment/nginx --timeout=120s
    kubectl get pods,svc -l app=nginx
    echo "[done] 环境就绪, 访问方式: kubectl port-forward svc/nginx 8080:80"
}

# ---------- 主流程 ----------
case "${1:-up}" in
    up)   check_deps; gen_config; create_cluster; verify; load_test_image; deploy_test ;;
    down) teardown ;;
    load) load_test_image ;;   # 单独重载镜像 (集群已存在时)
    *)    echo "用法: $0 [up|down|load]"; exit 1 ;;
esac
