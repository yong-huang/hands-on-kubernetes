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
    # GitHub 直连在国内常超时; 优先用本目录缓存清单, 无缓存才联网下载。
    # 缓存获取方式 (任选):
    #   curl -L -o cert-manager-cache.yaml \
    #     https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
    #   curl -L -o otel-operator-cache.yaml \
    #     https://github.com/open-telemetry/opentelemetry-operator/releases/download/v0.158.0/opentelemetry-operator.yaml
    local cm_yaml="cert-manager-cache.yaml" otel_yaml="otel-operator-cache.yaml"
    if [ ! -s "$cm_yaml" ]; then
        cm_yaml="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VER}/cert-manager.yaml"
    else
        echo "  (使用本地缓存 $cm_yaml)"
    fi
    step "install" "安装 cert-manager (OTel Operator 的 webhook 依赖它签证书)"
    kubectl apply -f "$cm_yaml"
    # 必须等 webhook 也就绪, 否则后续带 cert-manager 注解的资源会因
    # "failed calling webhook ... connection refused" 创建失败
    kubectl -n cert-manager rollout status deploy/cert-manager --timeout=300s
    kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s
    kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=300s

    if [ ! -s "$otel_yaml" ]; then
        otel_yaml="https://github.com/open-telemetry/opentelemetry-operator/releases/download/${OTEL_OPERATOR_VER}/opentelemetry-operator.yaml"
    else
        echo "  (使用本地缓存 $otel_yaml)"
    fi
    step "install" "安装 OpenTelemetry Operator"
    # webhook 就绪后仍可能短暂不可达, 重试 apply 直到成功
    for i in 1 2 3 4 5; do
        if kubectl apply -f "$otel_yaml"; then break; fi
        echo "  [retry $i] cert-manager webhook 暂不可达, 8s 后重试..."
        sleep 8
        [ "$i" = "5" ] && { echo "[error] OTel Operator 安装失败" >&2; exit 1; }
    done
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
