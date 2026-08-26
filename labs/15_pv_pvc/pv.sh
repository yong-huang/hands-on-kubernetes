#!/usr/bin/env bash
# =============================================================================
# Kubernetes PV/PVC 静态存储全流程演示脚本
# 覆盖: 创建绑定 -> 数据持久性验证 -> 回收策略(Retain) -> 清理
# 用法: ./pv.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 verify)只执行该步骤
# 注意: kind 集群的 hostPath 位于 kind 节点容器内部, 清数据用 docker exec
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"              # 演示用的 namespace
PV="pv-demo"                     # 主 PV 名称
PV_TOPO="pv-demo-topo"           # 带节点亲和性的第二个 PV
PVC="pvc-demo"                   # PVC 名称
POD="pv-demo-pod"                # 挂载 PVC 的 Pod
NODE_DIR="/data/pv-demo"         # hostPath 在 kind 节点内的路径
# 找到 Pod 所在的 kind 节点名(清数据时需要 docker exec 进去)
# 注意: Pod 可能尚未创建或已删除, 因此在需要时才惰性查询
pod_node() {
    kubectl get pod "${POD}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo ""
}

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# 等待 Pod 进入 Running
wait_pod() {
    kubectl wait "pod/${POD}" -n "${NAMESPACE}" \
        --for=condition=Ready --timeout=60s
}

# ----------------------------- 1. 创建并绑定 -----------------------------
do_deploy() {
    step "deploy" "创建 PV / PVC / Pod (apply)"
    kubectl apply -f manifests/pv_pvc.yaml

    step "deploy" "等待 Pod Running (PVC Bound 后才能调度成功)"
    wait_pod || {
        echo "Pod 未就绪, 排查事件:" >&2
        kubectl describe pod "${POD}" -n "${NAMESPACE}" | tail -20 >&2
        exit 1
    }

    step "deploy" "查看 PV 状态 (Available -> Bound) 与绑定信息 (CLAIM 列)"
    kubectl get pv "${PV}" "${PV_TOPO}" 2>/dev/null \
        || kubectl get pv
    echo "(claimRef 指向: $(kubectl get pv "${PV}" \
        -o jsonpath='{.spec.claimRef.name}'))"

    step "deploy" "查看 PVC 状态 (Bound) 与绑定的 PV 名 (spec.volumeName)"
    kubectl get pvc "${PVC}" -n "${NAMESPACE}"
    echo "(volumeName = $(kubectl get pvc "${PVC}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumeName}'))"

    step "deploy" "确认 Pod 已把 PV 挂到 /data"
    kubectl get pod "${POD}" -n "${NAMESPACE}" -o wide
}

# ----------------------------- 2. 验证数据持久性 -----------------------------
do_verify() {
    step "verify" "向 /data 写入一个标记文件"
    kubectl exec "${POD}" -n "${NAMESPACE}" -- \
        sh -c "echo \"marker-$(date +%s)\" >> /data/hello.log && cat /data/hello.log"
    echo "--- 当前 /data 内容 (含循环追加的时间戳日志) ---"
    kubectl exec "${POD}" -n "${NAMESPACE}" -- ls -l /data

    step "verify" "删除 Pod (存储属于 PV, 不随 Pod 消失)"
    kubectl delete pod "${POD}" -n "${NAMESPACE}" --wait=true

    step "verify" "重新 apply YAML 重建 Pod (绑定同一个 PVC/PV)"
    kubectl apply -f manifests/pv_pvc.yaml
    wait_pod

    step "verify" "验证数据跨 Pod 重建依然存在"
    kubectl exec "${POD}" -n "${NAMESPACE}" -- \
        sh -c "tail -3 /data/hello.log && echo '--- 数据仍在, 持久化 OK ---'"

    step "verify" "当前 Pod 挂载的 PV 来源"
    kubectl get pvc "${PVC}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumeName}'; echo
}

# ----------------------------- 3. 回收策略演示 (Retain) -----------------------------
do_reclaim() {
    step "reclaim" "先删除正在使用 PVC 的 Pod (否则 PVC 因 pvc-protection 卡 Terminating)"
    kubectl delete pod "${POD}" -n "${NAMESPACE}" --ignore-not-found --wait=true

    step "reclaim" "删除 PVC, 观察 PV 状态变为 Released"
    kubectl delete pvc "${PVC}" -n "${NAMESPACE}" --wait=true
    kubectl get pv "${PV}"
    echo "(Released != Available: reclaimPolicy=Retain 时数据与 claimRef 保留,"
    echo " 防止数据被误用; 想复用必须手动清理)"

    step "reclaim" "手动清理第一步: 删除 PV 对象 (hostPath 数据仍在磁盘上)"
    kubectl delete pv "${PV}" --wait=true

    step "reclaim" "手动清理第二步: 进入 kind 节点容器删除宿主数据"
    echo "(kind 节点本身是容器, NODE_DIR 解析在节点容器内部)"
    local node
    node=$(pod_node)
    if [[ -n "${node}" ]]; then
        echo "docker exec ${node} rm -rf ${NODE_DIR}"
        docker exec "${node}" rm -rf "${NODE_DIR}" \
            || echo "(跳过: 无法 docker exec, 请手动执行上面这行)"
    else
        echo "未找到 Pod 所在节点, 请手动执行:"
        echo "  docker exec <kind节点名> rm -rf ${NODE_DIR}"
    fi
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源 (Pod/PVC/PV)"
    local node
    node=$(pod_node)                # 先取节点名, 删 Pod 后就查不到了
    kubectl delete -f manifests/pv_pvc.yaml --ignore-not-found --wait=true || true
    if [[ -n "${node}" ]]; then
        docker exec "${node}" rm -rf "${NODE_DIR}" \
            "${NODE_DIR}-topo" 2>/dev/null || true
    fi
    kubectl get pv,pvc -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        deploy)  do_deploy ;;
        verify)  do_verify ;;
        reclaim) do_reclaim ;;
        clean)   do_clean ;;
        all)
            do_deploy; do_verify; do_reclaim; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: deploy | verify | reclaim | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
