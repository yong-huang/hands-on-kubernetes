#!/usr/bin/env bash
# =============================================================================
# kind + kubectl 安装脚本 (仅安装工具, 不创建集群 —— 集群在 01_setup_env 创建)
# 支持: macOS (brew 优先, 无 brew 时用 curl) / Linux (curl)
# 用法: ./setup_kind.sh [step]
#   不带参数依次执行: install -> verify
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

KIND_VERSION="v0.25.0"        # 无 brew 时的兜底版本
KUBECTL_VERSION="v1.31.0"

step() { echo; echo "=====> [$1] $2"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------- 1. 安装 kind -----------------------------
install_kind() {
    if have kind; then
        step "kind" "已安装, 跳过: $(kind version)"
        return
    fi
    step "kind" "安装 kind"
    if have brew; then
        brew install kind
    else
        # 官方二进制: 按平台选择 amd64/arm64
        ARCH="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
        OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
        curl -Lo ./kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${OS}-${ARCH}"
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    fi
}

# ----------------------------- 2. 安装 kubectl -----------------------------
install_kubectl() {
    if have kubectl; then
        step "kubectl" "已安装, 跳过: $(kubectl version --client 2>/dev/null | head -1 || kubectl version --client | head -1)"
        return
    fi
    step "kubectl" "安装 kubectl"
    if have brew; then
        brew install kubectl
    else
        ARCH="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
        OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
        chmod +x ./kubectl
        sudo mv ./kubectl /usr/local/bin/kubectl
    fi
}

# ----------------------------- 3. 验证 -----------------------------
do_verify() {
    step "verify" "验证安装结果"
    kind version
    kubectl version --client
    echo
    echo "工具就绪。下一步: cd ../01_setup_env && ./setup.sh up 创建学习集群"
}

# ----------------------------- 入口 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        install) install_kind; install_kubectl ;;
        verify)  do_verify ;;
        all)     install_kind; install_kubectl; do_verify ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: install | verify | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
