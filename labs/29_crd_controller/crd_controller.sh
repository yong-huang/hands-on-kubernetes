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
    step "drift" "模拟配置漂移: 手动把 STS 副本改成 2"
    kubectl -n "$NS" patch sts orders-db --type=json \
        -p='[{"op":"replace","path":"/spec/replicas","value":2}]'
    sleep 2
    echo "  controller 下个循环会把它拉回 spec.replicas —— 自愈即调谐"
}

do_clean() {
    kubectl delete ns "$NS" --ignore-not-found
    kubectl delete crd databases.demo.example.com --ignore-not-found
}

case "${1:-all}" in
    deploy) do_deploy ;; run) do_run ;; drift) do_drift ;; clean) do_clean ;;
    all) do_deploy; do_run ;;
esac
