#!/usr/bin/env bash
# =============================================================================
# Kubernetes StorageClass 动态供给全流程演示脚本
# 覆盖: 部署观察 WaitForFirstConsumer 延迟绑定 -> 数据持久性 -> 回收 -> 清理
# 用法: ./sc.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 deploy)只执行该步骤
# 注意: 与 15 的静态供给不同, 本项目不需要手动创建/清理任何 PV
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"              # 演示用的 namespace
SC="fast-local"                  # 自定义 StorageClass
PVC="pvc-dynamic"                # PVC 名称
POD="sc-demo-pod"                # 挂载 PVC 的 Pod

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# 等待 Pod 进入 Running
wait_pod() {
    kubectl wait "pod/${POD}" -n "${NAMESPACE}" \
        --for=condition=Ready --timeout=60s
}

# 查询 PVC 绑定的动态 PV 名 (可能尚未生成, 输出空)
pv_of_pvc() {
    kubectl get pvc "${PVC}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo ""
}

# ----------------------------- 1. 部署: 观察 WaitForFirstConsumer -----------------------------
do_deploy() {
    # 说明: kubectl 无法按多文档 YAML 拆分 apply, 这里一次性 apply 全部,
    # 然后"抢"在供给完成前抓 PVC 的 Pending 状态; 若动作太慢已 Bound, 属正常现象
    step "deploy" "apply StorageClass + PVC + Pod"
    kubectl apply -f manifests/storageclass.yaml

    step "deploy" "查看 StorageClass: kind 自带默认 standard + 我们新建的 fast-local"
    kubectl get sc
    echo "(注意 VOLUMEBINDINGMODE 列: WaitForFirstConsumer vs Immediate;"
    echo " 默认 SC 带 annotation storageclass.kubernetes.io/is-default-class=true)"

    step "deploy" "抓 PVC 状态: WaitForFirstConsumer 下, Pod 调度前 PVC 停留在 Pending"
    kubectl get pvc "${PVC}" -n "${NAMESPACE}" || true
    echo "(这就是延迟绑定: 此刻还没有任何 PV 被创建, kubectl get pv 为空)"

    step "deploy" "等待 Pod Running (调度结果决定卷的拓扑位置)"
    wait_pod || {
        echo "Pod 未就绪, 排查事件:" >&2
        kubectl describe pod "${POD}" -n "${NAMESPACE}" | tail -20 >&2
        exit 1
    }

    step "deploy" "Pod 已调度 -> provisioner 自动建卷 -> PVC 变 Bound"
    kubectl get pvc "${PVC}" -n "${NAMESPACE}"
    kubectl get pod "${POD}" -n "${NAMESPACE}" -o wide

    step "deploy" "PV 是自动冒出来的 (对比 15: 那是手动写好 PV 再绑定)"
    local pv; pv=$(pv_of_pvc)
    if [[ -n "${pv}" ]]; then
        echo "动态生成的 PV: ${pv}"
        kubectl get pv "${pv}"
        echo "(storageClassName = $(kubectl get pv "${pv}" \
            -o jsonpath='{.spec.storageClassName}'), "
        echo " reclaimPolicy = $(kubectl get pv "${pv}" \
            -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'))"
    else
        echo "PV 尚未生成 (供给仍在进行), 稍后可用 kubectl get pv 查看"
    fi
}

# ----------------------------- 2. 数据持久性验证 -----------------------------
do_test() {
    step "test" "向 /data 写入一个标记文件"
    kubectl exec "${POD}" -n "${NAMESPACE}" -- \
        sh -c "echo \"marker-$(date +%s)\" >> /data/marker.log && cat /data/marker.log"

    step "test" "删除 Pod (PVC/PV 与数据不随 Pod 消失)"
    kubectl delete pod "${POD}" -n "${NAMESPACE}" --wait=true

    step "test" "重新 apply 重建 Pod (绑定同一个 PVC/PV)"
    kubectl apply -f manifests/storageclass.yaml
    wait_pod

    step "test" "验证数据跨 Pod 重建依然存在 (且未再新建 PV)"
    kubectl exec "${POD}" -n "${NAMESPACE}" -- \
        sh -c "tail -3 /data/marker.log && echo '--- 数据仍在, 动态卷持久化 OK ---'"
    echo "PV 数量 (删 Pod 前后不变): $(kubectl get pv -o name | wc -l | tr -d ' ')"
}

# ----------------------------- 3. 回收: Delete 策略 -----------------------------
do_reclaim() {
    step "reclaim" "先删 Pod (否则 PVC 因 pvc-protection 卡 Terminating)"
    kubectl delete pod "${POD}" -n "${NAMESPACE}" --ignore-not-found --wait=true

    local pv; pv=$(pv_of_pvc)
    step "reclaim" "删除 PVC, 观察动态 PV 被自动删除 (reclaimPolicy=Delete)"
    kubectl delete pvc "${PVC}" -n "${NAMESPACE}" --wait=true
    if [[ -n "${pv}" ]]; then
        kubectl get pv "${pv}" 2>/dev/null \
            || echo "PV ${pv} 已随 PVC 一起被删除 (对比 15: Retain 只变 Released)"
    fi
    kubectl get pv || true
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源 (Pod/PVC/SC; PV 已随 PVC 自动回收)"
    kubectl delete -f manifests/storageclass.yaml --ignore-not-found --wait=true || true
    # 兜底: 清掉可能残留的动态 PV
    local pv; pv=$(pv_of_pvc)
    [[ -n "${pv}" ]] && kubectl delete pv "${pv}" --ignore-not-found || true
    kubectl get sc,pv,pvc -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        deploy)  do_deploy ;;
        test)    do_test ;;
        reclaim) do_reclaim ;;
        clean)   do_clean ;;
        all)
            do_deploy; do_test; do_reclaim; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: deploy | test | reclaim | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
