# =============================================================================
# 分布式追踪演示: install(cert-manager+OTel Operator) -> deploy(Jaeger+三服务)
#               -> trace(观察链路) -> ui(看瀑布图) -> clean
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# 版本固定, 保证实验可复现
CERT_MANAGER_VER="v1.18.2"
OTEL_OPERATOR_VER="v0.158.0"

step() { echo; echo "=====> [$1] $2"; }

do_install() {
    step "install" "安装 cert-manager (OTel Operator 的 webhook 依赖它签证书)"
    kubectl apply -f \
        "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VER}/cert-manager.yaml"
    kubectl -n cert-manager rollout status deploy/cert-manager --timeout=300s

    step "install" "安装 OpenTelemetry Operator"
    kubectl apply -f \
        "https://github.com/open-telemetry/opentelemetry-operator/releases/download/${OTEL_OPERATOR_VER}/opentelemetry-operator.yaml"
    kubectl -n opentelemetry-operator-system rollout status \
        deploy/opentelemetry-operator-controller-manager --timeout=300s
}

do_deploy() {
    step "deploy" "部署 Jaeger + Instrumentation + 三层 Python 微服务"
    kubectl create ns tracing-demo --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f manifests/jaeger_tracing.yaml
    echo "  (首次运行需拉取 python 镜像并让 init 容器拷贝 OTel agent, 请耐心等待)"
    kubectl -n tracing-demo rollout status deploy/jaeger --timeout=300s
    for d in svc-front svc-order svc-payment; do
        kubectl -n tracing-demo rollout status deploy/$d --timeout=600s
    done
    kubectl -n tracing-demo get pods
}

do_trace() {
    step "trace" "等流量跑几轮, 从 Jaeger API 拉最近 trace"
    sleep 30
    # 注意: kubectl 没有 -q 之类的静默旗标, 静默交给 curl 自己的 -s
    kubectl -n tracing-demo run curl --rm -it --restart=Never \
      --image=curlimages/curl:8.5.0 -- \
      -s "http://jaeger-query.tracing-demo.svc:16686/api/traces?service=svc-front&limit=1" \
      | head -c 800 || true
    echo
    echo "  ^ JSON 中同一 traceID 下出现 svc-front/svc-order/svc-payment 即为完整链路"
}

do_ui() {
    step "ui" "打开 Jaeger UI 看瀑布图"
    kubectl -n tracing-demo port-forward svc/jaeger-query 16686:16686 &
    PF=$!; sleep 2
    echo "  浏览器 http://localhost:16686"
    echo "  Search: service=svc-front -> 点开一条 trace"
    echo "  应看到 front -> order -> payment 的父子 span 层级与各自耗时"
    kill $PF 2>/dev/null || true
}

do_clean() {
    step "clean" "删除演示命名空间 (cert-manager / OTel Operator 保留, 供其他实验复用)"
    kubectl delete ns tracing-demo --ignore-not-found
}

case "${1:-all}" in
    install) do_install ;; deploy) do_deploy ;; trace) do_trace ;;
    ui)      do_ui ;; clean) do_clean ;;
    all)     do_install; do_deploy ;;
esac
