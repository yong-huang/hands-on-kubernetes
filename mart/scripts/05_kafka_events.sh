#!/usr/bin/env bash
# 项目 5：事件驱动 Kafka 异步解耦 —— 部署 / 三项验收 / 清理
# 用法: ./05_kafka_events.sh [build|apply|observe|verify-delivery|verify-dlq|verify-idempotent|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
# 钉死集群上下文：防止并行会话切走全局 kubectl context
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
NODE_IP="${NODE_IP:-$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
ORDER_HTTP="http://${NODE_IP}:30882"
NOTIF_HTTP="http://${NODE_IP}:30883"
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

# 宿主机 NodePort 时而抽风，统一走集群内 product Pod 中转调用（确定性最好）
in_cluster_http() {  # $1 = path
    kubectl -n "$NS" exec "$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')" -- python -c \
        "import urllib.request;print(urllib.request.urlopen('http://notification.mart.svc:8000$1', timeout=3).read().decode())" 2>/dev/null || echo '{}'
}
stats() { in_cluster_http "/stats"; }

new_order() {  # 经集群内 product Pod 中转下单，绕开宿主机 NodePort 的不确定性
    kubectl -n "$NS" exec "$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')" -- python -c "
import urllib.request, json
req = urllib.request.Request('http://order.mart.svc:8000/orders',
    data=json.dumps({'product_id':'$1','quantity':1}).encode(),
    headers={'Content-Type':'application/json'}, method='POST')
print(urllib.request.urlopen(req, timeout=5).read().decode())
"
}

wait_stats() {  # $1=字段 $2=期望增量；单次 exec 在集群内轮询（宿主机 exec 太慢不稳定）
    local field="$1" want="$2" base="${3:-}" pod
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request, json, time, sys
field, want = '$field', $want
def get():
    return json.loads(urllib.request.urlopen('http://notification.mart.svc:8000/stats', timeout=3).read())[field]
base = get() if '$base' == '' else int('$base')
t0 = time.time()
while time.time() - t0 < 140:
    try:
        if get() - base >= want:
            sys.exit(0)
    except Exception:
        pass
    time.sleep(2)
sys.exit(1)
"
}

do_build() {
    step "build" "构建 order:0.3.0（+事件发布）与 notification:0.1.0"
    docker build -q -t mart/order:0.3.0 -f services/order/Dockerfile .
    sed -i '' 's|image: mart/order:0.2.0|image: mart/order:0.3.0|g; s|value: "0.2.0"|value: "0.3.0"|' deploy/order/manifests.yaml
    docker build -q -t mart/notification:0.1.0 -f services/notification/Dockerfile .
    kind load docker-image mart/order:0.3.0 mart/notification:0.1.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "部署 Kafka（KRaft 单节点）并等就绪（首次拉镜像可能几分钟）"
    kubectl apply -f deploy/kafka/manifests.yaml
    kubectl -n "$NS" rollout status statefulset/kafka --timeout=420s
    # 显式建 topic：auto-create 在首次 Produce 的同步超时窗口里经常来不及
    kubectl -n "$NS" exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
        --create --if-not-exists --topic orders --partitions 3 --replication-factor 1 >/dev/null
    kubectl -n "$NS" exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
        --create --if-not-exists --topic orders.dlq --partitions 1 --replication-factor 1 >/dev/null
    echo "  topics: $(kubectl -n "$NS" exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | tr '\n' ' ')"
    step "apply" "滚动升级 order（+生产者）并部署 notification（消费者）"
    kubectl apply -f deploy/order/manifests.yaml
    kubectl -n "$NS" rollout restart deployment/order
    kubectl -n "$NS" rollout status deployment/order --timeout=180s
    kubectl apply -f deploy/notification/manifests.yaml
    kubectl -n "$NS" rollout status deployment/notification --timeout=180s
}

do_observe() {
    step "observe" "Kafka 主题列表与通知服务状态"
    kubectl -n "$NS" exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null || true
    echo "-- notification stats:"; stats; echo
}

# 验收①：下单后 10s 内通知服务消费到事件
do_verify_delivery() {
    in_cluster_http "/fault?mode=0" >/dev/null   # 清残留注入
    step "verify-delivery" "先取基线再下单（消费太快，事后取基线会把增量算进 base）"
    local resp id base
    base=$(stats | jq -r '.processed // 0')
    resp=$(new_order p1)
    id=$(echo "$resp" | jq -r '.id')
    echo "  订单: $id"
    if wait_stats processed 1 "$base" >/dev/null; then
        echo "✅ 验收①通过：order.created 事件异步送达通知服务"
    else
        echo "❌ 150s 内未见事件被消费"; exit 1
    fi
}

# 验收②：注入消费失败 -> 重试 3 次 -> 进 DLQ
do_verify_dlq() {
    in_cluster_http "/fault?mode=0" >/dev/null   # 清残留注入
    step "verify-dlq" "开启消费失败注入，下一单毒消息"
    in_cluster_http "/fault?mode=consumer_fail" >/dev/null
    local resp id
    resp=$(new_order p2)
    id=$(echo "$resp" | jq -r '.id')
    echo "  毒订单: $id"
    rc=0
    if wait_stats dlq 1 >/dev/null; then
        echo "  DLQ 计数 +1；核对重试日志："
        kubectl -n "$NS" logs -l app=notification --since=3m 2>/dev/null | grep -E "attempt|DLQ" | tail -4
        echo "✅ 验收②通过：重试 3 次后消息落入 orders.dlq"
    else
        echo "❌ 120s 内未见 DLQ 计数增加"; rc=1
    fi
    # 无论成败都关注入：否则残留的 fail_mode 会毒害后续所有验收
    in_cluster_http "/fault?mode=0" >/dev/null
    [ "$rc" = "0" ] || exit 1
}

# 验收③：向 Kafka 手工重投同一订单消息 -> 幂等去重
do_verify_idempotent() {
    in_cluster_http "/fault?mode=0" >/dev/null   # 清残留注入
    step "verify-idempotent" "找到最近已处理订单并向 orders 主题重投同 ID 消息"
    local id
    id=$(kubectl -n "$NS" logs -l app=order --since=10m 2>/dev/null \
        | grep -oE 'published order.created for o-[a-z0-9-]+' | tail -1 | awk '{print $NF}')
    echo "  重投订单: $id"
    local dbase
    dbase=$(stats | jq -r '.duplicates // 0')
    kubectl -n "$NS" exec -i kafka-0 -- /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic orders >/dev/null <<< \
        "{\"event_type\":\"order.created\",\"order_id\":\"$id\",\"product_id\":\"p1\",\"quantity\":1,\"price_cents\":39900}"
    if wait_stats duplicates 1 "$dbase" >/dev/null; then
        echo "✅ 验收③通过：重复投递被幂等去重，通知只发一次"
    else
        echo "❌ 120s 内未见去重计数增加"; exit 1
    fi
}

do_clean() {
    step "clean" "关闭故障注入（保留 Kafka 与数据供后续项目使用）"
    in_cluster_http "/fault?mode=0" >/dev/null
}

main() {
    local target="${1:-all}"
    case "$target" in
        build) do_build ;; apply) do_apply ;; observe) do_observe ;;
        verify-delivery) do_verify_delivery ;;
        verify-dlq) do_verify_dlq ;;
        verify-idempotent) do_verify_idempotent ;;
        clean) do_clean ;;
        all) do_build; do_apply; do_observe; do_verify_delivery; do_verify_dlq; do_verify_idempotent ;;
        *) echo "可用: build|apply|observe|verify-delivery|verify-dlq|verify-idempotent|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
