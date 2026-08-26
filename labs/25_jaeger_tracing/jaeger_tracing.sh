#!/usr/bin/env bash
# =============================================================================
# 分布式追踪演示: deploy(装Jaeger+三服务) -> trace(观察链路) -> ui(看瀑布图)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

step() { echo; echo "=====> [$1] $2"; }

do_deploy() {
    step "deploy" "部署 Jaeger + 三层微服务 demo"
    kubectl create ns tracing-demo --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f manifests/jaeger_tracing.yaml
    kubectl -n tracing-demo get pods
}

do_trace() {
    step "trace" "等流量跑几轮, 从 Jaeger API 拉最近 trace"
    sleep 20
    kubectl -n tracing-demo run jq --rm -q --restart=Never \
      --image=curlimages/curl:8.5.0 -- \
      -s "http://jaeger-query.tracing-demo.svc:16686/api/traces?service=svc-front&limit=3" \
      | head -c 600 || true
    echo
    echo "  ^ JSON 中 services 数组含 [svc-front, svc-order, svc-payment] 即为完整链路"
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

case "${1:-all}" in
    deploy) do_deploy ;; trace) do_trace ;; ui) do_ui ;;
    *) do_deploy ;;
esac
