#!/usr/bin/env bash
# 项目 2：Go 订单服务 + 跨语言 gRPC —— 部署 / grpcurl 观察 / 三项验收 / 清理
# 用法: ./02_order_grpc.sh [gen|build|apply|observe|verify-price|verify-timeout|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
# 钉死集群上下文：防止并行会话切走全局 kubectl context
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
NODE_IP="${NODE_IP:-$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
PRODUCT_HTTP="http://${NODE_IP}:30880"
PRODUCT_GRPC="${NODE_IP}:30881"
ORDER_HTTP="http://${NODE_IP}:30882"
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

do_gen() {
    step "gen" "protoc 生成 Go/Python 桩（契约变更后先跑这步）"
    bash scripts/gen_proto.sh
}

do_build() {
    step "build" "构建 product:0.3.0（+gRPC）与 order:0.1.0 并灌入 kind"
    docker build -q -t mart/product:0.3.0 -f services/product/Dockerfile services/product
    docker build -q -t mart/order:0.1.0 -f services/order/Dockerfile .   # 上下文是 mart 根：要带 api/gen/go
    kind load docker-image mart/product:0.3.0 mart/order:0.1.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "滚动升级 product（新增 gRPC 端口）+ 部署 order"
    kubectl apply -f deploy/product/manifests.yaml
    kubectl -n "$NS" rollout status deployment/product --timeout=120s
    kubectl apply -f deploy/order/manifests.yaml
    kubectl -n "$NS" rollout status deployment/order --timeout=120s
}

do_observe() {
    step "observe" "grpcurl 直连 Python 服务列出 RPC（服务端反射，无需 proto 文件）"
    grpcurl -plaintext "$PRODUCT_GRPC" list
    step "observe" "gRPC 查价（跨语言第一跳：宿主机 -> Python）"
    grpcurl -plaintext -d '{"product_id":"p1"}' "$PRODUCT_GRPC" mart.v1.ProductService/GetProduct
    step "observe" "下单（Go 订单服务内部经 gRPC 查 Python 拿价格）"
    curl -s -X POST "$ORDER_HTTP/orders" -H 'Content-Type: application/json' \
        -d '{"product_id":"p1","quantity":2}'; echo
    kubectl -n "$NS" get pods -l 'app in (product,order)'
}

# 对全部 product Pod 执行同一段 HTTP 调用（内存态服务，必须每个副本都改）
# 这也是本项目的教学点：gRPC 长连接会把客户端钉在单个 Pod 上，多副本内存态不一致
product_all_pods() {
    local path="$1" pod
    for pod in $(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[*].metadata.name}'); do
        kubectl -n "$NS" exec "$pod" -- python -c \
            "import urllib.request;urllib.request.urlopen('http://localhost:8000$path')" >/dev/null
    done
}

# 验收②：改商品价 -> 再下单 -> 订单价格跟着变（证明价格是实时查的）
do_verify_price() {
    step "verify-price" "把 p1 改价到 12345 分（所有副本），再下一单"
    # 改价请求体带 JSON，urllib 需要 Request 包装，单独循环写
    local pod resp price
    for pod in $(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[*].metadata.name}'); do
        kubectl -n "$NS" exec "$pod" -- python -c \
            "import urllib.request,json;req=urllib.request.Request('http://localhost:8000/products/p1',data=json.dumps({'price_cents':12345}).encode(),headers={'Content-Type':'application/json'},method='PUT');urllib.request.urlopen(req)" >/dev/null
    done
    resp=$(curl -s -X POST "$ORDER_HTTP/orders" -H 'Content-Type: application/json' \
        -d '{"product_id":"p1","quantity":1}')
    echo "$resp"
    price=$(echo "$resp" | jq -r '.price_cents')
    if [ "$price" = "12345" ]; then
        echo "✅ 验收②通过：订单价格 = gRPC 实时查价（12345）"
    else
        echo "❌ 验收②未通过：期望 12345，实际 ${price}"; exit 1
    fi
    for pod in $(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[*].metadata.name}'); do
        kubectl -n "$NS" exec "$pod" -- python -c \
            "import urllib.request,json;req=urllib.request.Request('http://localhost:8000/products/p1',data=json.dumps({'price_cents':39900}).encode(),headers={'Content-Type':'application/json'},method='PUT');urllib.request.urlopen(req)" >/dev/null
    done
}

# 验收③：全部副本注入 2s 延迟 -> 订单服务 500ms 预算内返回 504，不悬挂
do_verify_timeout() {
    step "verify-timeout" "所有 product 副本注入 /fault?delay=2s 后下单，应约 500ms 拿到 504"
    product_all_pods "/fault?delay=2s"
    local start elapsed code
    start=$(date +%s%N 2>/dev/null || python3 -c 'import time;print(time.time_ns())')
    code=$(curl -s -o /tmp/order-timeout-resp.txt -w '%{http_code}' --max-time 10 \
        -X POST "$ORDER_HTTP/orders" -H 'Content-Type: application/json' \
        -d '{"product_id":"p1","quantity":1}')
    end=$(date +%s%N 2>/dev/null || python3 -c 'import time;print(time.time_ns())')
    elapsed=$(( (end - start) / 1000000 ))
    echo "HTTP ${code}，耗时 ${elapsed}ms，响应: $(cat /tmp/order-timeout-resp.txt)"
    product_all_pods "/fault?delay=0"   # 清除所有副本的注入
    if [ "$code" = "504" ] && [ "$elapsed" -lt 1500 ]; then
        echo "✅ 验收③通过：${elapsed}ms 内快速失败（预算 500ms + 重试），请求不悬挂"
    else
        echo "❌ 验收③未通过：code=${code} elapsed=${elapsed}ms"; exit 1
    fi
    sleep 1
    step "verify-timeout" "清除注入后下单恢复正常"
    curl -s -X POST "$ORDER_HTTP/orders" -H 'Content-Type: application/json' \
        -d '{"product_id":"p2","quantity":1}' | jq -c '{id,price_cents,status}'
}

do_clean() {
    step "clean" "删除 order 部署（product 保留，是后续项目的地基）"
    kubectl -n "$NS" delete -f deploy/order/manifests.yaml --ignore-not-found
}

main() {
    local target="${1:-all}"
    case "$target" in
        gen) do_gen ;; build) do_build ;; apply) do_apply ;; observe) do_observe ;;
        verify-price) do_verify_price ;; verify-timeout) do_verify_timeout ;;
        clean) do_clean ;;
        all) do_gen; do_build; do_apply; do_observe; do_verify_price; do_verify_timeout ;;
        *) echo "可用: gen|build|apply|observe|verify-price|verify-timeout|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
