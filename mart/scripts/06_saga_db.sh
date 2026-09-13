#!/usr/bin/env bash
# 项目 6：数据库拆分与 Saga 补偿事务 —— 部署 / 三项验收 / 清理
# 用法: ./06_saga_db.sh [build|apply|observe|verify-consistency|verify-insufficient|verify-kill|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
NODE_IP="${NODE_IP:-$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

# 宿主机 NodePort 不稳，全部走集群内 product Pod 中转
in_cluster() {  # $1=完整 URL $2=method(默认GET) $3=body(json，可空)
    local url="$1" method="${2:-GET}" body="${3:-}" pod
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request, json, sys
req = urllib.request.Request('$url', method='$method',
    data=('$body'.encode() if '$body' else None),
    headers={'Content-Type': 'application/json'})
try:
    print(urllib.request.urlopen(req, timeout=30).read().decode())
except urllib.error.HTTPError as e:
    print(e.read().decode()[:300])  # 只输出响应体：错误响应也是 JSON，jq 能继续解析
"
}

new_order() { in_cluster "http://order.mart.svc:8000/orders" POST "{\"product_id\":\"$1\",\"quantity\":$2}"; }
order_by_id() { in_cluster "http://order.mart.svc:8000/orders/$1"; }
stock_of() { in_cluster "http://inventory.mart.svc:8000/stock/$1"; }
psql_orderdb() { kubectl -n "$NS" exec postgres-0 -- psql -U order_user -d orderdb -tA -c "$1"; }
psql_invdb() { kubectl -n "$NS" exec postgres-0 -- psql -U inv_user -d invdb -tA -c "$1"; }

do_build() {
    step "build" "构建 order:0.4.0（+PG/Saga）与 inventory:0.1.0"
    docker build -q -t mart/order:0.4.0 -f services/order/Dockerfile .
    docker build -q -t mart/inventory:0.1.0 -f services/inventory/Dockerfile services/inventory
    kind load docker-image mart/order:0.4.0 mart/inventory:0.1.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "部署 Postgres（双库初始化）"
    kubectl apply -f deploy/db/postgres.yaml
    kubectl -n "$NS" rollout status statefulset/postgres --timeout=300s
    # 建表（服务只会 CREATE IF NOT EXISTS，这里主动把库存种子数据插好）
    kubectl -n "$NS" exec postgres-0 -- psql -U inv_user -d invdb -c "
        CREATE TABLE IF NOT EXISTS stock(product_id text primary key, available int not null, reserved int not null default 0);
        CREATE TABLE IF NOT EXISTS reservations(order_id text primary key, product_id text, quantity int, status text);
        INSERT INTO stock VALUES ('p1',100,0),('p2',50,0),('p3',20,0) ON CONFLICT (product_id) DO NOTHING;" >/dev/null
    kubectl -n "$NS" exec postgres-0 -- psql -U order_user -d orderdb -c "
        CREATE TABLE IF NOT EXISTS orders(id text primary key, product_id text, quantity int,
            price_cents bigint, status text, created_at timestamptz not null default now());" >/dev/null
    step "apply" "部署 inventory 并滚动升级 order"
    kubectl apply -f deploy/inventory/manifests.yaml
    kubectl -n "$NS" rollout status deployment/inventory --timeout=180s
    kubectl apply -f deploy/order/manifests.yaml
    kubectl -n "$NS" rollout restart deployment/order
    kubectl -n "$NS" rollout status deployment/order --timeout=180s
}

do_observe() {
    step "observe" "双库数据与库存水位"
    echo "-- orderdb.orders:"; psql_orderdb "SELECT id,status FROM orders ORDER BY created_at DESC LIMIT 5"
    echo "-- invdb.stock:"; psql_invdb "SELECT * FROM stock"
}

# 验收①：正常下单跨库一致（orders=created 且 stock.available-1、reservation=reserved）
do_verify_consistency() {
    step "verify-consistency" "正常下单 p1 x2"
    local resp id before after
    before=$(psql_invdb "SELECT available FROM stock WHERE product_id='p1'")
    resp=$(new_order p1 2); echo "  -> $resp"
    id=$(echo "$resp" | jq -r '.id // empty')
    [ -n "$id" ] || { echo "❌ 下单失败"; exit 1; }
    after=$(psql_invdb "SELECT available FROM stock WHERE product_id='p1'")
    local ostatus rstatus
    ostatus=$(psql_orderdb "SELECT status FROM orders WHERE id='$id'")
    rstatus=$(psql_invdb "SELECT status FROM reservations WHERE order_id='$id'")
    echo "  before=$before after=$after order=$ostatus reservation=$rstatus"
    if [ "$ostatus" = "created" ] && [ "$rstatus" = "reserved" ] && [ "$((before - after))" = "2" ]; then
        echo "✅ 验收①通过：订单 created、库存精确 -2、预定单 reserved，跨库一致"
    else
        echo "❌ 跨库不一致"; exit 1
    fi
}

# 验收②：库存不足 -> 订单自动 cancelled，库存无变化、无残留预定
do_verify_insufficient() {
    step "verify-insufficient" "把 p3 库存设为 0，下单 x1 应 409 且自动取消"
    psql_invdb "UPDATE stock SET available=0 WHERE product_id='p3'" >/dev/null
    local resp id ostatus rstatus cnt
    resp=$(new_order p3 1); echo "  -> $resp"
    id=$(echo "$resp" | jq -r '.id // empty')
    [ -n "$id" ] || { echo "❌ 没拿到订单号"; exit 1; }
    sleep 1
    ostatus=$(psql_orderdb "SELECT status FROM orders WHERE id='$id'")
    rstatus=$(psql_invdb "SELECT count(*) FROM reservations WHERE order_id='$id'")
    cnt=$(psql_invdb "SELECT available FROM stock WHERE product_id='p3'")
    echo "  order=$ostatus reservations=$rstatus stock=$cnt"
    if [ "$ostatus" = "cancelled" ] && [ "$rstatus" = "0" ] && [ "$cnt" = "0" ]; then
        echo "✅ 验收②通过：库存不足 -> 订单 cancelled、无中间态残留"
    else
        echo "❌ 补偿不干净"; exit 1
    fi
    psql_invdb "UPDATE stock SET available=20 WHERE product_id='p3'" >/dev/null   # 恢复
}

# 验收③：Saga 进行中杀掉 inventory Pod -> 恢复后订单收敛、数据一致
do_verify_kill() {
    step "verify-kill" "注入 inventory 延迟 5s 拖住 Saga，下单后立即杀 Pod"
    kubectl -n "$NS" get pods -l app=inventory -o jsonpath='{.items[0].metadata.name}' | xargs -I{} \
        kubectl -n "$NS" exec {} -- python -c "import urllib.request;urllib.request.urlopen('http://localhost:8000/fault?delay=5')" >/dev/null
    ( in_cluster "http://order.mart.svc:8000/orders" POST '{"product_id":"p1","quantity":1}' > /tmp/o6-kill-resp.txt 2>&1 ) &
    sleep 2   # 让 Saga 进入第一轮 reserve 重试
    kubectl -n "$NS" delete pod -l app=inventory --force --grace-period=0 >/dev/null 2>&1 || true
    echo "  inventory Pod 已杀，等它重建 + Saga 收敛（最多 90s）..."
    local deadline=$((SECONDS + 90)) id ostatus
    id=$(kubectl -n "$NS" exec "$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')" -- python -c "print(open('/tmp/o6-id').read())" 2>/dev/null || echo "")
    # 等下单请求返回拿订单号
    local tries=0
    while [ ! -s /tmp/o6-kill-resp.txt ] && [ "$tries" -lt 60 ]; do sleep 2; tries=$((tries+1)); done
    id=$(jq -r '.id // empty' /tmp/o6-kill-resp.txt 2>/dev/null || echo "")
    echo "  订单: $id"
    # 轮询订单终态
    while [ "$SECONDS" -lt "$deadline" ]; do
        ostatus=$(psql_orderdb "SELECT status FROM orders WHERE id='$id'" 2>/dev/null || echo "")
        case "$ostatus" in
            created|cancelled) break ;;
        esac
        sleep 3
    done
    sleep 3   # 给补偿/重试留一点收尾时间
    local avail resv
    avail=$(psql_invdb "SELECT available FROM stock WHERE product_id='p1'")
    resv=$(psql_invdb "SELECT coalesce(status,'none') FROM reservations WHERE order_id='$id'")
    echo "  终态: order=$ostatus reservation=$resv stock.available=$avail"
    if [ "$ostatus" = "created" ] && [ "$resv" = "reserved" ]; then
        echo "✅ 验收③通过：Pod 重建后 Saga 幂等重试成功，订单 created 且库存扣减有据"
    elif [ "$ostatus" = "cancelled" ] && { [ "$resv" = "none" ] || [ "$resv" = "released" ]; }; then
        echo "✅ 验收③通过：Saga 补偿生效，订单 cancelled 且库存无残留"
    else
        echo "❌ 订单未收敛或数据不一致: order=$ostatus resv=$resv"; exit 1
    fi
}

do_clean() {
    step "clean" "清除 inventory 延迟注入"
    kubectl -n "$NS" get pods -l app=inventory -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | while read -r pod; do
        kubectl -n "$NS" exec "$pod" -- python -c "import urllib.request;urllib.request.urlopen('http://localhost:8000/fault?delay=0')" >/dev/null 2>&1 || true
    done
}

main() {
    local target="${1:-all}"
    case "$target" in
        build) do_build ;; apply) do_apply ;; observe) do_observe ;;
        verify-consistency) do_verify_consistency ;;
        verify-insufficient) do_verify_insufficient ;;
        verify-kill) do_verify_kill ;;
        clean) do_clean ;;
        all) do_build; do_apply; do_observe; do_verify_consistency; do_verify_insufficient; do_verify_kill ;;
        *) echo "可用: build|apply|observe|verify-consistency|verify-insufficient|verify-kill|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
