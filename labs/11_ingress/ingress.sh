#!/usr/bin/env bash
# =============================================================================
# 11_ingress 演示脚本: 装 Controller -> 应用路由规则 -> 测试域名/路径路由 -> 清理
# 用法: ./ingress.sh [controller|apply|test|clean|all]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"
MANIFEST="manifests/ingress.yaml"
NAMESPACE="default"
CONTROLLER_NS="ingress-nginx"

# kind 官方维护的 ingress-nginx 清单 ( 针对 kind 优化, 用 hostPort 80/443 )
CONTROLLER_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"
# 本地缓存路径 (github 直连不稳时, 手动下载一份放这里)
CONTROLLER_LOCAL="manifests/ingress-nginx-kind.yaml"

step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装 Ingress Controller -----------------------------
do_controller() {
    step "controller" "安装 ingress-nginx (kind 专用清单)"
    if kubectl get namespace "${CONTROLLER_NS}" &>/dev/null; then
        echo "ingress-nginx 已存在, 跳过安装"
    else
        if [ -f "${CONTROLLER_LOCAL}" ]; then
            kubectl apply -f "${CONTROLLER_LOCAL}"
        else
            # github 直连可能超时; 失败时手动下载:
            #   curl -Lo ingress-nginx-kind.yaml ${CONTROLLER_URL}
            kubectl apply -f "${CONTROLLER_URL}"
        fi
        # ★ 镜像在国内需要预载 (节点拉不到 registry.k8s.io):
        #   cd ../../scripts && ./load_images.sh \
        #     registry.k8s.io/ingress-nginx/controller:v1.x.x \
        #     registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.x.x
        # (具体 tag 以清单里的 image: 字段为准)
    fi
    kubectl wait --namespace "${CONTROLLER_NS}" \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s

    step "controller" "访问方式说明"
    cat <<'EOF'
  kind 集群要在宿主机直接用 80/443 端口, 建集群时必须配 extraPortMappings:
    kind: Cluster
    nodes:
      - role: control-plane
        kubeadmConfigPatches:
          - |
            kind: InitConfiguration
            nodeRegistration:
              kubeletExtraArgs:
                node-labels: "ingress-ready=true"
        extraPortMappings:
          - containerPort: 80
            hostPort: 80
          - containerPort: 443
            hostPort: 443
  (需要重建集群才生效; 不重建也可用 port-forward 测试, 见 test 步骤)
EOF
}

# ----------------------------- 2. 应用路由规则 -----------------------------
do_apply() {
    step "apply" "部署两个后端 + 域名路由 + 路径路由 (ingress.yaml)"
    kubectl apply -f "${MANIFEST}"
    kubectl rollout status deployment/web-a -n "${NAMESPACE}"
    kubectl rollout status deployment/web-b -n "${NAMESPACE}"
    kubectl get ingress -n "${NAMESPACE}"
    # HOSTS 列显示规则里的域名; ADDRESS 列是 Controller 的 LB 地址
}

# ----------------------------- 3. 测试路由 -----------------------------
do_test() {
    step "test" "确定 Controller 访问入口"
    # 优先节点 IP:port80 (kind 清单的 controller 用 hostPort), 失败提示 port-forward
    NODE_IP=$(kubectl get nodes -o jsonpath \
        '{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    BASE=""
    if [ -n "${NODE_IP}" ] && curl -s -o /dev/null --connect-timeout 3 "http://${NODE_IP}/"; then
        BASE="http://${NODE_IP}"
        echo "使用节点入口: ${BASE}"
    else
        echo "节点 80 端口不可达 (集群未配 extraPortMappings), 改用 port-forward..."
        kubectl port-forward -n "${CONTROLLER_NS}" svc/ingress-nginx-controller 18080:80 >/dev/null 2>&1 &
        PF_PID=$!
        sleep 3
        BASE="http://localhost:18080"
        echo "使用 port-forward 入口: ${BASE} (测试结束自动关闭)"
    fi

    step "test" "1) 域名路由: Host=a.example.com -> web-a"
    curl -s -H "Host: a.example.com" "${BASE}/" ; echo
    step "test" "2) 域名路由: Host=b.example.com -> web-b"
    curl -s -H "Host: b.example.com" "${BASE}/" ; echo
    step "test" "3) 路径路由: Host=example.com /a -> web-a"
    curl -s -H "Host: example.com" "${BASE}/a" ; echo
    step "test" "4) 路径路由: Host=example.com /b -> web-b"
    curl -s -H "Host: example.com" "${BASE}/b" ; echo

    # 关闭 port-forward
    [ -n "${PF_PID:-}" ] && kill "${PF_PID}" 2>/dev/null || true
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除路由与后端 (保留 ingress-nginx Controller)"
    kubectl delete -f "${MANIFEST}" --ignore-not-found --wait=true
    # 级联删除的 Pod 是异步的，等它们真正消失再收尾
    kubectl wait --for=delete pod -l app=web-a -n "${NAMESPACE}" --timeout=120s || true
    kubectl wait --for=delete pod -l app=web-b -n "${NAMESPACE}" --timeout=120s || true
    echo "(如需卸载 Controller: kubectl delete -n ${CONTROLLER_NS} --all)"
}

# ----------------------------- 入口 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        controller) do_controller ;;
        apply)      do_apply ;;
        test)       do_test ;;
        clean)      do_clean ;;
        all)        do_controller; do_apply; do_test ;;
        *) echo "用法: $0 [controller|apply|test|clean|all]"; exit 1 ;;
    esac
}

main "$@"
