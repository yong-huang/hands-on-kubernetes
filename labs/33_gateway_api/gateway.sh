#!/usr/bin/env bash
# =============================================================================
# 33_gateway_api 演示脚本:
#   install(CRD+Envoy Gateway) -> deploy(Gateway+后端+HTTPRoute) -> test -> clean
# 用法: ./gateway.sh [install|deploy|test|clean|all]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

GATEWAY_API_VER="v1.2.1"
CRD_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VER}/standard-install.yaml"
CRD_LOCAL="manifests/gateway-api-standard.yaml"
EG_URL="https://github.com/envoyproxy/gateway/releases/download/v1.2.4/install.yaml"
EG_LOCAL="manifests/envoy-gateway-install.yaml"

step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装 CRD + Envoy Gateway -----------------------------
do_install() {
    step "install" "安装 Gateway API CRD (标准通道)"
    if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        echo "CRD 已存在, 跳过"
    elif [ -s "${CRD_LOCAL}" ] && head -1 "${CRD_LOCAL}" | grep -q apiVersion; then
        kubectl apply --server-side -f "${CRD_LOCAL}"
    else
        kubectl apply --server-side -f "${CRD_URL}" \
          || { echo "下载失败: 手动下载 ${CRD_URL} 存为 ${CRD_LOCAL} 后重试"; exit 1; }
    fi
    kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s

    step "install" "安装 Envoy Gateway (Gateway API 的一个 Controller 实现)"
    if kubectl get namespace envoy-gateway-system &>/dev/null; then
        echo "Envoy Gateway 已存在, 跳过安装"
    elif [ -s "${EG_LOCAL}" ] && head -1 "${EG_LOCAL}" | grep -q apiVersion; then
        kubectl apply --server-side -f "${EG_LOCAL}"
    else
        kubectl apply --server-side -f "${EG_URL}" \
          || { echo "下载失败: 手动下载 ${EG_URL} 存为 ${EG_LOCAL} 后重试"; exit 1; }
    fi
    kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s
}

# ----------------------------- 2. 部署 Gateway/后端/HTTPRoute -----------------------------
do_deploy() {
    step "deploy" "创建 Gateway + 两个后端 + HTTPRoute (域名/路径/权重)"
    kubectl apply -f manifests/gatewayclass.yaml
    kubectl apply -f manifests/gateway.yaml
    kubectl apply -f manifests/backends.yaml
    kubectl rollout status deploy/route-v1 --timeout=120s
    kubectl rollout status deploy/route-v2 --timeout=120s
    kubectl apply -f manifests/httproute.yaml
    step "deploy" "等待 Envoy 数据面 Pod 出现 (由 Gateway 自动创建)"
    sleep 5
    kubectl get gateway demo-gateway 2>/dev/null || true
    kubectl -n envoy-gateway-system get pods -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway 2>/dev/null || true
}

# ----------------------------- 3. 验证路由与权重 -----------------------------
do_test() {
    step "test" "等待 Envoy 数据面就绪 (Gateway PROGRAMMED), 再 port-forward 验证"
    for _ in $(seq 1 24); do
        ENVOY_POD=$(kubectl -n envoy-gateway-system get pods -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        [ -n "${ENVOY_POD}" ] && kubectl -n envoy-gateway-system wait --for=condition=Ready "pod/${ENVOY_POD}" --timeout=60s >/dev/null 2>&1 && break
        ENVOY_POD=""
        sleep 5
    done
    [ -n "${ENVOY_POD}" ] || { echo "Envoy 数据面 120s 内未就绪"; exit 1; }
    echo "数据面 Pod: ${ENVOY_POD}"
    # 集群内起一个临时 curl Pod, 直接打 Envoy Service 的 DNS (不依赖宿主机端口转发)
    kubectl delete pod gw-curl --ignore-not-found >/dev/null 2>&1
    kubectl run gw-curl --image=curlimages/curl --restart=Never --command -- sleep 300 >/dev/null
    kubectl wait --for=condition=Ready pod/gw-curl --timeout=120s
    SVC="envoy-default-demo-gateway-88752a31.envoy-gateway-system.svc"
    echo "--- 域名路由 (Host: a.example.com) ---"
    kubectl exec gw-curl -- curl -s --max-time 3 -H "Host: a.example.com" "http://${SVC}/" || true
    echo ""
    echo "--- 路径路由 (/api 固定进 v2) ---"
    kubectl exec gw-curl -- curl -s --max-time 3 -H "Host: a.example.com" "http://${SVC}/api" || true
    echo ""
    echo "--- 权重路由 (20 次请求统计 v1/v2 命中, 期望约 90/10) ---"
    V1=0; V2=0
    for i in $(seq 1 20); do
        R=$(kubectl exec gw-curl -- curl -s --max-time 3 -H "Host: a.example.com" "http://${SVC}/" 2>/dev/null || true)
        case "${R}" in v1) V1=$((V1+1));; v2) V2=$((V2+1));; esac
    done
    echo "v1=${V1} v2=${V2} (20 次是小样本, 围绕 18/2 波动、偶发 20/0 属正常)"
    kubectl delete pod gw-curl --ignore-not-found >/dev/null 2>&1 || true
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除本实验资源 (Envoy Gateway 本体保留, 需要时手动卸载)"
    kubectl delete -f manifests/httproute.yaml --ignore-not-found
    kubectl delete -f manifests/backends.yaml --ignore-not-found
    kubectl delete gateway demo-gateway --ignore-not-found
    echo "如需彻底卸载 Controller: kubectl delete namespace envoy-gateway-system && kubectl delete -f manifests/gateway-api-standard.yaml"
}

case "${1:-all}" in
    install) do_install ;;
    deploy)  do_deploy ;;
    test)    do_test ;;
    clean)   do_clean ;;
    all)     do_install; do_deploy; do_test ;;
    *) echo "用法: $0 [install|deploy|test|clean|all]"; exit 1 ;;
esac
