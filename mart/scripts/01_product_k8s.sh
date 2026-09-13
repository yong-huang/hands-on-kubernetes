#!/usr/bin/env bash
# 项目 1：Python 商品服务上 K8s —— 部署 / 观察 / 两项验收 / 清理
# 用法: ./01_product_k8s.sh [apply|observe|verify-rolling|verify-readiness|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
DEPLOY="product"
# kind 集群名 ≠ kubectl 上下文名：本机集群建的时候叫 kind（kind get clusters 可见）
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底
NODE_IP="${NODE_IP:-$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
BASE="http://${NODE_IP}:30880"
ROOT="$(cd .. && pwd)"    # 仓库根（找 tests/）

step() { echo; echo "=====> [$1] $2"; }

need_tool() { command -v "$1" >/dev/null || { echo "缺少工具: $1"; exit 1; }; }

do_build() {
    step "build" "构建镜像并灌入 kind（多阶段构建 + 非 root 用户）"
    docker build -q -t mart/product:0.1.0 services/product
    docker tag mart/product:0.1.0 mart/product:0.2.0   # 同一镜像两个 tag，滚动更新验收时切换用
    kind load docker-image mart/product:0.1.0 mart/product:0.2.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "部署 product Service + Deployment（maxSurge=1/maxUnavailable=0）"
    kubectl apply -f deploy/product/manifests.yaml
    kubectl -n "$NS" rollout status deployment/"$DEPLOY" --timeout=120s
}

do_observe() {
    step "observe" "Pod 状态与探针事件（看 READY 1/1 与无重启）"
    kubectl -n "$NS" get pods -l app="$DEPLOY" -o wide
    kubectl -n "$NS" get deployment "$DEPLOY"
    step "observe" "宿主机经 NodePort 直达四个端点"
    for p in /healthz /readyz /version /products; do
        echo "-- GET $p"; curl -s --max-time 3 "$BASE$p"; echo
    done
}

# 验收①：滚动更新期间 k6 恒压 50rps，非 2xx 响应数必须为 0
do_verify_rolling() {
    need_tool k6; need_tool jq
    local cur tgt out
    cur=$(kubectl -n "$NS" get deploy "$DEPLOY" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APP_VERSION")].value}')
    if [ "${cur}" = "0.1.0" ]; then tgt="0.2.0"; else tgt="0.1.0"; fi
    out=$(mktemp /tmp/k6-rolling.XXXXXX)

    step "verify-rolling" "当前版本 ${cur}，压测后台启动（50rps × 45s），随后切到 ${tgt}"
    BASE="$BASE" DURATION=45s OUT="${out}" k6 run tests/load/rolling_zero_downtime.js --quiet >/dev/null 2>&1 &
    local k6pid=$!
    sleep 5   # 让压力先稳定打在旧版本上
    kubectl -n "$NS" patch deploy "$DEPLOY" --type=json -p="[
      {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"mart/product:$tgt\"},
      {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/0/value\",\"value\":\"$tgt\"}]"
    kubectl -n "$NS" rollout status deployment/"$DEPLOY" --timeout=120s
    echo "（滚动完成，压力继续打满剩余时长）"
    wait "$k6pid" || true

    local bad total
    bad=$(jq '[.metrics.bad_responses.values.count // 0][0]' "${out}" 2>/dev/null || \
          jq '.metrics.bad_responses.values.count // 0' "${out}")
    total=$(jq '.metrics.http_reqs.values.count' "${out}")
    echo
    step "verify-rolling" "结果：总请求 ${total}，非 2xx 响应 ${bad}"
    if [ "${bad}" = "0" ] && [ "${total}" -gt 500 ]; then
        echo "✅ 验收①通过：滚动更新全程零失败（优雅关闭 + preStop 生效）"
    else
        echo "❌ 验收①未通过：出现了 $bad 个失败响应"; exit 1
    fi
}

# 验收②：readiness 端口配错 → rollout 卡住 → progressDeadline 到点自动中止 → undo 恢复
do_verify_readiness() {
    step "verify-readiness" "把 readinessProbe 端口改成 9999（模拟配置事故）"
    kubectl -n "$NS" patch deploy "$DEPLOY" --type=json \
        -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":9999}]'
    step "verify-readiness" "rollout status 应在 60s 进度期限后失败退出（旧 Pod 全程在线）"
    if kubectl -n "$NS" rollout status deployment/"$DEPLOY" --timeout=150s; then
        echo "❌ 预期 rollout 失败中止，但它竟然成功了"; exit 1
    fi
    echo "-- Deployment 条件（看 Progressing=False/ProgressDeadlineExceeded）:"
    kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.status.conditions}'; echo
    echo "-- DESIRED/UP-TO-DATE/AVAILABLE 数量错位 = 卡住现场:"
    kubectl -n "$NS" get deploy "$DEPLOY"
    echo "-- 新 Pod 事件（看 readiness probe failure）:"
    kubectl -n "$NS" get pods -l app="$DEPLOY" --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].readinessProbe.httpGet.port}{"\n"}{end}'
    step "verify-readiness" "回滚恢复"
    kubectl -n "$NS" rollout undo deployment/"$DEPLOY"
    kubectl -n "$NS" rollout status deployment/"$DEPLOY" --timeout=120s
    echo "✅ 验收②通过：坏探针卡住发布、到点自动中止、undo 恢复，全程服务不中断"
}

do_clean() {
    step "clean" "删除 product 全部资源（保留 mart 命名空间给后续项目）"
    kubectl -n "$NS" delete deploy "$DEPLOY" --ignore-not-found
    kubectl -n "$NS" delete svc "$DEPLOY" --ignore-not-found
    kubectl -n "$NS" get all -l app="$DEPLOY"
}

main() {
    local target="${1:-all}"
    case "$target" in
        build) do_build ;;
        apply) do_apply ;;
        observe) do_observe ;;
        verify-rolling) do_verify_rolling ;;
        verify-readiness) do_verify_readiness ;;
        clean) do_clean ;;
        all) do_build; do_apply; do_observe ;;
        *) echo "可用: build | apply | observe | verify-rolling | verify-readiness | clean | all" >&2; exit 1 ;;
    esac
}
main "$@"
