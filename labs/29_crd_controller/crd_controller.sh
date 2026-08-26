#!/usr/bin/env bash
# =============================================================================
# CRD + Controller 演示: deploy(装CRD+CR) -> run(启动controller) -> verify
#                        -> drift(手动改STS制造漂移,观察自愈) -> clean
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效
NS="crd-demo"
step() { echo; echo "=====> [$1] $2"; }

do_deploy() {
    step "deploy" "安装 Database CRD 与示例 CR"
    kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f manifests/database_crd.yaml

    step "deploy" "kubectl 现在认识新资源类型了"
    kubectl api-resources | grep databases
    kubectl -n "$NS" get db          # shortName 生效
}

do_run() {
    step "run" "本地运行 controller (开发模式; 生产打包成镜像部署)"
    python3 controller.py &
    CTL=$!; sleep 12; kill $CTL 2>/dev/null || true

    step "run" "查看 controller 回写的 status"
    kubectl -n "$NS" get database orders-db -o yaml | grep -A6 'status:'
}

do_drift() {
    step "drift" "模拟配置漂移: 后台重启 controller, 手动把 STS 副本改成 2, 观察自愈"
    # controller 后台常驻, 日志落文件方便观察调谐动作; 记下 PID 便于停止
    CTL_LOG="/tmp/crd_controller.log"
    python3 controller.py >"$CTL_LOG" 2>&1 &
    CTL_PID=$!
    echo "  controller 已后台运行 (pid=$CTL_PID, 日志: $CTL_LOG)"

    kubectl -n "$NS" patch sts orders-db --type=json \
        -p='[{"op":"replace","path":"/spec/replicas","value":2}]'
    echo "  已手动把副本改成 2 (偏离 CR 声明的 replicas=1), 等待下个调谐循环..."

    sleep 12
    echo "--- controller 日志(漂移被拉回的证据) ---"
    grep -E "drift|patched" "$CTL_LOG" | tail -2 || true
    echo "--- 当前 STS 实际副本 ---"
    kubectl -n "$NS" get sts orders-db \
        -o jsonpath='{.spec.replicas}'; echo
    echo "  ^ 回到 1 即自愈成功 —— 自愈即调谐"
    echo "  停止 controller: kill $CTL_PID"
}

do_clean() {
    kubectl delete ns "$NS" --ignore-not-found
    kubectl delete crd databases.demo.example.com --ignore-not-found
}

case "${1:-all}" in
    deploy) do_deploy ;; run) do_run ;; drift) do_drift ;; clean) do_clean ;;
    all) do_deploy; do_run ;;
esac
