#!/usr/bin/env bash
# =============================================================================
# AI Ops 体验流程: install(装假GPU) -> verify(节点出现GPU) -> run(按卡调度)
#                  -> quota(超配额Pending) -> inspect(GPU分配巡检) -> clean
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效
NS="gpu-demo"
step() { echo; echo "=====> [$1] $2"; }

do_install() {
    step "install" "部署 fake GPU device plugin"
    kubectl apply -f manifests/fake_gpu.yaml
}

do_verify() {
    step "verify" "等一个周期后查看节点 GPU 容量"
    sleep 20
    kubectl get nodes -o json | \
      jq -r '.items[] | "\(.metadata.name)\tGPU=\(.status.allocatable["nvidia.com/gpu"] // 0)"'
    echo "  ^ 出现 nvidia.com/gpu 即模拟成功 (调度器已把它当真实扩展资源)"
}

do_run() {
    step "run" "小任务(1卡)应正常调度并 Running"
    kubectl -n "$NS" wait --for=condition=ready pod \
        -l job-name=train-job-small --timeout=60s || true

    step "run" "大任务(6卡): 配额剩 3 张 -> Quota 拒绝创建 Pod"
    kubectl -n "$NS" describe resourcequota team-gpu-quota | sed -n '/Resource/,+4p'
    kubectl -n "$NS" get pods -l job-name=train-job-big || true
    echo "  ^ 事件里可见 'exceeded quota', Pod 根本不会被创建"
}

do_inspect() {
    step "inspect" "运维巡检: 全局 GPU 分配视图"
    kubectl describe nodes | grep -A8 "Allocated resources" | grep -E "Name|nvidia|^-" || true
    echo "--- 按 Pod 视角 ---"
    kubectl -n "$NS" get pods -o custom-columns=\
'POD:.metadata.name,GPU:.spec.containers[*].resources.requests.nvidia\.com/gpu,NODE:.spec.nodeName'
}

do_clean() {
    step "clean" "清理并恢复节点状态(移除假GPU字段)"
    kubectl delete ns "$NS" --ignore-not-found
    for n in $(kubectl get nodes -o name); do
        kubectl patch "$n" --subresource=status --type=json \
          -p='[{"op":"remove","path":"/status/capacity/nvidia.com~1gpu"}]' 2>/dev/null || true
        kubectl patch "$n" --subresource=status --type=json \
          -p='[{"op":"remove","path":"/status/allocatable/nvidia.com~1gpu"}]' 2>/dev/null || true
    done
}

case "${1:-all}" in
    install) do_install ;; verify) do_verify ;; run) do_run ;;
    inspect) do_inspect ;; clean) do_clean ;;
    all) do_install; do_verify; do_run ;;
esac
