#!/usr/bin/env bash
# 项目 4：弹性容错三件套（熔断/重试/超时）—— 部署 / 熔断全状态机验收 / 清理
# 用法: ./04_resilience.sh [build|apply|verify-breaker|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
# 钉死集群上下文：防止并行会话切走全局 kubectl context
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
NODE_IP="${NODE_IP:-$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
PRODUCT_HTTP="http://${NODE_IP}:30880"
ORDER_HTTP="http://${NODE_IP}:30882"
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

# 对全部 product Pod 执行同一段 HTTP 调用（内存态故障开关必须每个副本都改）
product_all_pods() {
    local path="$1" pod
    for pod in $(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[*].metadata.name}'); do
        kubectl -n "$NS" exec "$pod" -- python -c \
            "import urllib.request;urllib.request.urlopen('http://localhost:8000$path')" >/dev/null
    done
}

# 发一次下单，输出 "HTTP状态码 耗时ms"
one_order() {
    local start end code
    start=$(date +%s%N 2>/dev/null || python3 -c 'import time;print(time.time_ns())')
    code=$(curl -s -o /tmp/o4-resp.txt -w '%{http_code}' --max-time 10 \
        -X POST "$ORDER_HTTP/orders" -H 'Content-Type: application/json' \
        -d '{"product_id":"p1","quantity":1}')
    end=$(date +%s%N 2>/dev/null || python3 -c 'import time;print(time.time_ns())')
    echo "$code $(( (end - start) / 1000000 ))"
}

do_build() {
    step "build" "构建 product:0.3.0（+mode500 注入）与 order:0.2.0（+gobreaker）"
    docker build -q -t mart/product:0.3.0 -f services/product/Dockerfile services/product
    docker build -q -t mart/order:0.2.0 -f services/order/Dockerfile .
    kind load docker-image mart/product:0.3.0 mart/order:0.2.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "滚动升级两个服务（镜像同 tag 重建时 apply 不触发更新，需显式 restart）"
    kubectl apply -f deploy/product/manifests.yaml
    kubectl -n "$NS" rollout restart deployment/product
    kubectl -n "$NS" rollout status deployment/product --timeout=180s
    kubectl apply -f deploy/order/manifests.yaml
    kubectl -n "$NS" rollout restart deployment/order
    kubectl -n "$NS" rollout status deployment/order --timeout=180s
}

do_verify_breaker() {
    # 熔断器是进程内状态：重启 order 保证从 Closed 起步，不受上次运行残留影响
    step "verify-breaker" "重启 order（熔断器状态归零）"
    kubectl -n "$NS" rollout restart deployment/order >/dev/null
    kubectl -n "$NS" rollout status deployment/order --timeout=180s >/dev/null
    sleep 5   # 等 NodePort/DNS 就绪，避免首个请求 connection refused
    step "verify-breaker" "健康基线：注入前下一单应成功"
    local r
    r=$(one_order); echo "  -> $r"
    echo "$r" | grep -q '^201 ' || { echo "❌ 基线都不健康"; exit 1; }

    step "verify-breaker" "所有 product 副本注入 mode=500（瞬时错误），连打 8 单"
    product_all_pods "/fault?mode=500"
    local tf=/tmp/o4-codes.txt
    : > "$tf"
    local i r
    for i in 1 2 3 4 5 6 7 8; do
        r=$(one_order)
        echo "$r" >> "$tf"
        echo "  req$i -> $r"
    done

    step "verify-breaker" "验收①：熔断 Open 后应出现 <100ms 的 503 快速失败"
    local fast=0 c e
    while read -r c e; do
        if [ "$c" = "503" ] && [ "$e" -lt 100 ]; then fast=$((fast + 1)); fi
    done < "$tf"
    if [ "$fast" -lt 2 ]; then echo "❌ 没有观察到快速失败（503 <100ms）"; cat "$tf"; exit 1; fi
    echo "  观察到 ${fast} 次快速失败"

    step "verify-breaker" "验收②：日志应出现完整状态机 Closed -> Open -> Half-Open -> Closed"

    step "verify-breaker" "清除注入，等熔断 10s 超时进入 Half-Open 探测"
    product_all_pods "/fault?mode=0"
    sleep 12
    # 多打几单：两个 order 副本都在，得保证探测请求命中处于 Half-Open 的那个
    local okcount=0
    for i in 1 2 3 4; do
        r=$(one_order); echo "  探测$i -> $r"
        echo "$r" | grep -q '^201 ' && okcount=$((okcount + 1))
    done
    if [ "$okcount" -lt 3 ]; then echo "❌ 探测恢复失败（仅 $okcount/4 成功）"; exit 1; fi

    sleep 2
    logs=$(kubectl -n "$NS" logs -l app=order --since=15m 2>/dev/null | grep 'CIRCUIT' || true)
    echo "$logs"
    echo "$logs" | grep -qi 'Closed -> Open'      || { echo "❌ 缺少 Closed -> Open"; exit 1; }
    echo "$logs" | grep -qi 'Open -> Half-Open'   || { echo "❌ 缺少 Open -> Half-Open"; exit 1; }
    echo "$logs" | grep -qi 'Half-Open -> Closed' || { echo "❌ 缺少 Half-Open -> Closed"; exit 1; }

    step "verify-breaker" "验收③：清除注入后错误率回到 0"
    local ok=0
    for i in 1 2 3 4 5; do
        r=$(one_order); echo "$r" | grep -q '^201 ' && ok=$((ok + 1))
    done
    if [ "$ok" = "5" ]; then
        echo "✅ 验收①②③全部通过：熔断快速失败、状态机完整、恢复后错误率归零"
    else
        echo "❌ 恢复后仍有失败（$ok/5 成功）"; exit 1
    fi
}

do_clean() {
    step "clean" "清除所有故障注入"
    product_all_pods "/fault?mode=0" || true
}

main() {
    local target="${1:-all}"
    case "$target" in
        build) do_build ;; apply) do_apply ;; verify-breaker) do_verify_breaker ;;
        clean) do_clean ;;
        all) do_build; do_apply; do_verify_breaker ;;
        *) echo "可用: build|apply|verify-breaker|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
