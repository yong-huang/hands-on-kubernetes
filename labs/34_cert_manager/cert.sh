#!/usr/bin/env bash
# =============================================================================
# 34_cert_manager 演示脚本:
#   install(cert-manager) -> deploy(两级 Issuer + Certificate) -> verify(openssl) -> clean
# 用法: ./cert.sh [install|deploy|verify|rotate|clean|all]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

CM_VER="v1.16.2"
CM_URL="https://github.com/cert-manager/cert-manager/releases/download/${CM_VER}/cert-manager.yaml"
CM_LOCAL="manifests/cert-manager.yaml"

step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装 cert-manager -----------------------------
do_install() {
    step "install" "安装 cert-manager ${CM_VER} (quay.io 直连, kind 集群可用)"
    if kubectl get namespace cert-manager &>/dev/null; then
        echo "cert-manager 已存在, 跳过安装"
    elif [ -s "${CM_LOCAL}" ] && head -1 "${CM_LOCAL}" | grep -q apiVersion; then
        kubectl apply -f "${CM_LOCAL}"
    else
        kubectl apply -f "${CM_URL}" \
          || { echo "下载失败: 手动下载 ${CM_URL} 存为 ${CM_LOCAL} 后重试"; exit 1; }
    fi
    kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
    kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
    kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
}

# ----------------------------- 2. 两级签发 + 业务证书 -----------------------------
do_deploy() {
    step "deploy" "创建 self-signed -> CA 两级 Issuer, 再签业务证书"
    kubectl apply -f manifests/issuers.yaml
    kubectl -n cert-manager wait --for=condition=Ready certificate/demo-root-ca --timeout=120s
    kubectl apply -f manifests/certificate.yaml
    kubectl wait --for=condition=Ready certificate/a-example-com --timeout=120s
    kubectl get clusterissuer,certificate -A 2>/dev/null | grep -E "NAME|demo|a-example" || true
}

# ----------------------------- 3. openssl 验证 -----------------------------
do_verify() {
    step "verify" "从 Secret 取出证书, openssl 验证签发链/域名/有效期"
    kubectl get secret a-example-com-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/a-example-com.crt
    openssl x509 -in /tmp/a-example-com.crt -noout -issuer -subject -dates
    echo "--- DNS 名称 ---"
    openssl x509 -in /tmp/a-example-com.crt -noout -ext subjectAltName
    echo "成功判据: issuer 的 CN 为 demo-root-ca (由我们的 CA 签发, 而非集群默认); DNS 含 a.example.com; 有效期约 90 天(以实际运行为准)"
}

# ----------------------------- 4. 轮换演示 -----------------------------
do_rotate() {
    step "rotate" "修改 Certificate 的域名 -> cert-manager 自动重新签发"
    kubectl patch certificate a-example-com --type merge -p '{"spec":{"dnsNames":["a.example.com","b.example.com"]}}'
    kubectl wait --for=condition=Ready certificate/a-example-com --timeout=120s
    kubectl get secret a-example-com-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/a-example-com.crt
    openssl x509 -in /tmp/a-example-com.crt -noout -ext subjectAltName
    echo "观察点: Secret 里的证书被 cert-manager 原地换新(NotBefore 已刷新), 无需重启任何 Pod——对照 labs/05 'Secret 不自动轮换'的静态局限"
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除本实验资源 (cert-manager 本体保留)"
    kubectl delete -f manifests/certificate.yaml --ignore-not-found
    kubectl delete -f manifests/issuers.yaml --ignore-not-found
    kubectl delete secret a-example-com-tls --ignore-not-found
    echo "如需彻底卸载 cert-manager: kubectl delete namespace cert-manager"
}

case "${1:-all}" in
    install) do_install ;;
    deploy)  do_deploy ;;
    verify)  do_verify ;;
    rotate)  do_rotate ;;
    clean)   do_clean ;;
    all)     do_install; do_deploy; do_verify; do_rotate ;;
    *) echo "用法: $0 [install|deploy|verify|rotate|clean|all]"; exit 1 ;;
esac
