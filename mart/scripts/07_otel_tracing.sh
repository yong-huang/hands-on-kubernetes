#!/usr/bin/env bash
# 项目 7：OpenTelemetry 全链路埋点 —— 部署观测栈 / 验收跨服务 trace / RED 指标 / Grafana
# 用法: ./07_otel_tracing.sh [build|apply|verify-jaeger|verify-prometheus|verify-grafana|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
OBS="observability"
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

in_cluster() {  # $1=url $2=method $3=body —— 经 product Pod 中转
    local url="$1" method="${2:-GET}" body="${3:-}" pod
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request
req = urllib.request.Request('$url', method='$method',
    data=('$body'.encode() if '$body' else None),
    headers={'Content-Type': 'application/json'})
try:
    print(urllib.request.urlopen(req, timeout=30).read().decode())
except urllib.error.HTTPError as e:
    print(e.read().decode()[:300])
"
}

new_order() { in_cluster "http://order.mart.svc:8000/orders" POST '{"product_id":"p1","quantity":1}'; }

do_build() {
    step "build" "重建四服务镜像（+OTel 埋点）并灌入 kind"
    docker build -q -t mart/product:0.3.0 -f services/product/Dockerfile services/product
    docker build -q -t mart/order:0.4.0 -f services/order/Dockerfile .
    docker build -q -t mart/notification:0.1.0 -f services/notification/Dockerfile .
    docker build -q -t mart/inventory:0.1.0 -f services/inventory/Dockerfile services/inventory
    kind load docker-image mart/product:0.3.0 mart/order:0.4.0 mart/notification:0.1.0 mart/inventory:0.1.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "部署观测底座（Jaeger/Prometheus/Grafana）+ 滚动重启四服务"
    kubectl apply -f deploy/otel/manifests.yaml
    kubectl -n "$OBS" rollout status deploy/jaeger --timeout=180s
    kubectl -n "$OBS" rollout status deploy/prometheus --timeout=180s
    kubectl -n "$OBS" rollout status deploy/grafana --timeout=180s
    kubectl apply -f deploy/product/manifests.yaml
    kubectl apply -f deploy/order/manifests.yaml
    kubectl apply -f deploy/notification/manifests.yaml
    kubectl apply -f deploy/inventory/manifests.yaml
    for d in product order notification inventory; do
        kubectl -n "$NS" rollout restart deployment/$d >/dev/null
        kubectl -n "$NS" rollout status deployment/$d --timeout=240s
    done
}

# 验收①：一次下单 -> Jaeger 中一条 trace 横跨 order/product/inventory/notification
do_verify_jaeger() {
    step "verify-jaeger" "下单并等待 trace 上报（batch 间隔最多 ~5s）"
    local resp id
    resp=$(new_order); echo "  订单: $(echo "$resp" | head -c 120)"
    id=$(echo "$resp" | jq -r '.id // empty')
    sleep 20   # batch 上报 + Kafka 消费，竞态窗口给足
    local traces json
    json=$(in_cluster "http://jaeger.$OBS.svc:16686/api/traces?service=order&operation=saga.reserve&limit=20&lookback=1h")
    # 找一条同时包含四个服务 span 的 trace（notification 的 parent 来自 Kafka header 透传）
    local found
    found=$(echo "$json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d.get('data', []):
    services = {p['serviceName'] for p in t.get('processes', {}).values()}
    if {'order', 'product', 'inventory', 'notification'} <= services:
        print(t['traceID'], ','.join(sorted(services)))
        break
")
    if [ -n "$found" ]; then
        echo "  traceID=${found%% *}"
        echo "  services=${found#* }"
        echo "✅ 验收①通过：一次下单的 trace 串联四个服务（HTTP/gRPC/Kafka 全链路）"
    else
        echo "❌ 未找到跨四服务的 trace"; exit 1
    fi
}

# 验收②：Prometheus 抓到四个服务的 RED 指标
do_verify_prometheus() {
    step "verify-prometheus" "查询 Prometheus：每个服务的 http.server 请求计数"
    # PromQL 预 URL 编码（静态查询，避免三层引号转义问题）
    local encoded="count%20by%20(service)%20(%7B__name__%3D~%22http_server_duration_milliseconds_count%7Chttp_server_request_duration_seconds_count%22%7D)"
    local got svcs
    got=$(in_cluster "http://prometheus.$OBS.svc:9090/api/v1/query?query=$encoded")
    echo "  查询结果: $(echo "$got" | head -c 300)"
    svcs=$(echo "$got" | python3 -c "
import json, sys
d = json.load(sys.stdin)
names = set()
for r in d.get('data', {}).get('result', []):
    m = r.get('metric', {}).get('service', '')
    if m:
        names.add(m)
print(','.join(sorted(names)))
")
    echo "  发现服务: $svcs"
    local ok=0
    for s in order product inventory notification; do
        echo "$svcs" | grep -q "\b$s\b" && ok=$((ok+1))
    done
    if [ "$ok" = "4" ]; then
        echo "✅ 验收②通过：Prometheus 抓到四个服务的指标（Grafana RED 看板数据源就绪）"
    else
        echo "❌ 指标覆盖不全（$ok/4）"; exit 1
    fi
}

# 验收③：Grafana 可访问、数据源与 RED 看板已自动装载
do_verify_grafana() {
    step "verify-grafana" "Grafana API 健康与看板"
    local health dash
    health=$(in_cluster "http://grafana.$OBS.svc:3000/api/health")
    echo "  health: $(echo "$health" | head -c 100)"
    dash=$(in_cluster "http://grafana.$OBS.svc:3000/api/dashboards/uid/mini-mart-red")
    echo "$dash" | grep -q '"title"' && echo "✅ 验收③通过：Grafana 正常，mini-mart RED 看板已装载（浏览器打开节点IP:30885）" || { echo "❌ 看板未装载"; exit 1; }
}

do_clean() {
    step "clean" "观测栈保留给项目 10 使用，无需清理"
    echo "  （如需彻底清理: kubectl delete ns observability）"
}

main() {
    local target="${1:-all}"
    case "$target" in
        build) do_build ;; apply) do_apply ;;
        verify-jaeger) do_verify_jaeger ;;
        verify-prometheus) do_verify_prometheus ;;
        verify-grafana) do_verify_grafana ;;
        clean) do_clean ;;
        all) do_build; do_apply; do_verify_jaeger; do_verify_prometheus; do_verify_grafana ;;
        *) echo "可用: build|apply|verify-jaeger|verify-prometheus|verify-grafana|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
