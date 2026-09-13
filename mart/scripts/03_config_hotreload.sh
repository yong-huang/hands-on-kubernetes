#!/usr/bin/env bash
# 项目 3：配置与密钥的应用侧热加载 —— 部署 / 观察 / 两项验收 / 清理
# 用法: ./03_config_hotreload.sh [apply|observe|verify-config|verify-secret|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
# 钉死集群上下文：防止并行会话切走全局 kubectl context
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
NODE_IP="${NODE_IP:-$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
PRODUCT_HTTP="http://${NODE_IP}:30880"
ORDER_HTTP="http://${NODE_IP}:30882"
# kubelet 同步挂载卷的周期约 1 分钟，验收轮询窗口放宽到 150s
WAIT=240

step() { echo; echo "=====> [$1] $2"; }

set_config_json() {  # $1 = log_level，$2 = 目标 configmap
    local level="$1" cm="${2:-product-config}" patch
    # 注意：kubectl patch 的 -p - 走管道会报"cannot unmarshal array"，必须变量传
    patch=$(jq -n --arg v "{\"log_level\":\"$level\",\"max_qps\":100}" \
        "{\"data\":{\"config.json\":\$v}}")
    kubectl -n "$NS" patch configmap "$cm" --type merge -p "$patch"
}

restarts_sum() {  # 某 Deployment 所有 Pod 的重启总数（热加载的铁证：数字不变）
    kubectl -n "$NS" get pods -l app="$1" -o json \
        | jq '[.items[].status.containerStatuses[0].restartCount] | add // 0'
}

wait_for_config() {  # $1=期望值 $2=服务地址；轮询 /config 直到 log_level 匹配
    local want="$1" url="$2" i=0
    while [ "$i" -lt "$WAIT" ]; do
        local got
        got=$(curl -s --max-time 3 "$url" | jq -r '.config.log_level // empty' || true)
        if [ "$got" = "$want" ]; then echo "（${i}s 时观测到 log_level=${want}）"; return 0; fi
        sleep 5; i=$((i + 5))
    done
    echo "❌ ${WAIT}s 内未见 log_level=$want 生效"; return 1
}

do_apply() {
    step "apply" "部署 ConfigMap/Secret + 带挂载的两个服务"
    kubectl apply -f deploy/product/manifests.yaml
    kubectl -n "$NS" rollout status deployment/product --timeout=180s
    kubectl apply -f deploy/order/manifests.yaml
    kubectl -n "$NS" rollout status deployment/order --timeout=180s
}

do_observe() {
    step "observe" "两个服务的 /config：当前生效配置（product 还带密钥指纹长度）"
    echo "-- product:"; curl -s "$PRODUCT_HTTP/config"; echo
    echo "-- order:";   curl -s "$ORDER_HTTP/config"; echo
}

# 验收①：patch ConfigMap -> 一个同步周期内新配置生效，Pod 零重启
do_verify_config() {
    step "verify-config" "先归零：两边都设 INFO，等它生效拿到干净基线"
    set_config_json INFO product-config
    set_config_json INFO order-config
    wait_for_config INFO "$PRODUCT_HTTP/config"
    wait_for_config INFO "$ORDER_HTTP/config"
    local before after
    before=$(restarts_sum product)
    step "verify-config" "patch 两个 configmap 把 log_level 改为 DEBUG（product 重启数 ${before}）"
    set_config_json DEBUG product-config
    set_config_json DEBUG order-config
    wait_for_config DEBUG "$PRODUCT_HTTP/config"
    wait_for_config DEBUG "$ORDER_HTTP/config"
    after=$(restarts_sum product)
    if [ "$before" = "$after" ]; then
        echo "✅ 验收①通过：两个服务的配置都热生效且 Pod 重启数不变（${before}）"
    else
        echo "❌ 重启数变了：${before} -> ${after}（发生的是重启不是热加载）"; exit 1
    fi
}

# 验收②：轮换 Secret 里的数据库密码 -> 应用无重启换用新密码"重连"
do_verify_secret() {
    local before newpw pwlen
    before=$(restarts_sum product)
    # 唯一值 + 独特长度：避免等长旧值/重启后基线混淆造成的假阳性
    newpw="rotated-$(date +%s)-pw"
    pwlen=${#newpw}
    step "verify-secret" "轮换 db_password 到唯一新值 len=${pwlen}（当前重启数 ${before}）"
    kubectl -n "$NS" patch secret db-credentials \
        -p "{\"stringData\":{\"db_password\":\"${newpw}\"}}" >/dev/null
    # 断言用 /config 的密钥指纹（进程内状态），比 grep 多 pod 日志更确定
    local i=0 found=0 got
    while [ "$i" -lt "$WAIT" ]; do
        got=$(curl -s --max-time 3 "$PRODUCT_HTTP/config" | jq -r '.db_password_len // empty' 2>/dev/null || true)
        if [ -n "$got" ] && [ "$got" = "$pwlen" ]; then
            found=1; echo "（${i}s 时观测到应用换用新密码，指纹 len=${got}）"; break
        fi
        sleep 5; i=$((i + 5))
    done
    local after
    after=$(restarts_sum product)
    if [ "$found" = "1" ] && [ "$before" = "$after" ]; then
        echo "✅ 验收②通过：Secret 轮换后应用零重启切换到新密码"
    else
        echo "❌ 验收②未通过：found=${found} restarts ${before} -> ${after}"; exit 1
    fi
    kubectl -n "$NS" patch secret db-credentials \
        -p '{"stringData":{"db_password":"super-secret-v1"}}' >/dev/null   # 恢复
}

do_clean() {
    step "clean" "恢复默认配置（ConfigMap/Secret 保留给后续项目）"
    set_config_json INFO product-config
    kubectl -n "$NS" patch secret db-credentials \
        -p '{"stringData":{"db_password":"super-secret-v1"}}' >/dev/null
}

main() {
    local target="${1:-all}"
    case "$target" in
        apply) do_apply ;; observe) do_observe ;;
        verify-config) do_verify_config ;; verify-secret) do_verify_secret ;;
        clean) do_clean ;;
        all) do_apply; do_observe; do_verify_config; do_verify_secret ;;
        *) echo "可用: apply|observe|verify-config|verify-secret|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
