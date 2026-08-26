#!/usr/bin/env bash
# =============================================================================
# Kubernetes StatefulSet 全流程演示脚本
# 覆盖: 有序创建 -> 稳定 DNS -> 独立 PVC -> 删 Pod 验证身份不变 -> 扩容 -> 清理
# 用法: ./statefulset.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 dns)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"              # 演示用的 namespace
STS="web"                        # StatefulSet 名称 (Pod 名前缀: web-0/1/2)
HEADLESS="mysql-h"               # Headless Service 名称
LABEL="app=mysql"                # 标签选择器, 便于过滤资源

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 创建并观察有序性 -----------------------------
do_apply() {
    step "apply" "创建 Headless Service + StatefulSet (replicas=3)"
    kubectl apply -f manifests/statefulset.yaml

    step "apply" "观察有序创建: OrderedReady 下 web-0 Ready 之前不会有 web-1"
    kubectl get pods -l "${LABEL}" -n "${NAMESPACE}" -w &   # 后台 watch
    WATCH_PID=$!
    kubectl rollout status "statefulset/${STS}" -n "${NAMESPACE}"
    kill "${WATCH_PID}" 2>/dev/null || true

    step "apply" "最终状态: 注意 Pod 名是固定的 web-0/1/2, 无随机后缀"
    kubectl get pods -l "${LABEL}" -n "${NAMESPACE}" -o wide
}

# ----------------------------- 2. 稳定网络标识 -----------------------------
do_dns() {
    step "dns" "验证 Headless Service: clusterIP 为 None"
    kubectl get svc "${HEADLESS}" -n "${NAMESPACE}"

    step "dns" "通过 busybox 查每个 Pod 的稳定域名 (每 Pod 一条独立解析)"
    kubectl run dns-test --rm -i --restart=Never --image=busybox:1.36 \
        --namespace "${NAMESPACE}" -- \
        sh -c "nslookup web-0.${HEADLESS}.${NAMESPACE}.svc.cluster.local && \
               nslookup web-1.${HEADLESS}.${NAMESPACE}.svc.cluster.local"
    echo "对比: Deployment 的 Pod 没有独立 DNS 名, 只能通过 Service VIP 随机转发"
}

# ----------------------------- 3. 每个 Pod 独立 PVC -----------------------------
do_pvc() {
    step "pvc" "volumeClaimTemplates 自动为每个 Pod 生成专属 PVC"
    kubectl get pvc -l "${LABEL}" -n "${NAMESPACE}"
    echo "命名规则: <模板名data>-<Pod名> => data-web-0 / data-web-1 / data-web-2"
}

# ----------------------------- 4. 删 Pod: 身份与数据都不变 -----------------------------
do_stable() {
    step "stable" "删除 web-1 (模拟故障)"
    kubectl delete pod web-1 -n "${NAMESPACE}" --wait=false

    step "stable" "StatefulSet 重建它: 名字仍是 web-1 (Deployment 会换随机名)"
    kubectl rollout status "statefulset/${STS}" -n "${NAMESPACE}"
    kubectl get pods -l "${LABEL}" -n "${NAMESPACE}"

    step "stable" "验证重建后仍挂同一个 PVC (data-web-1 未变 => 数据还在)"
    kubectl get pod web-1 -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumes[0].persistentVolumeClaim.claimName}'; echo
}

# ----------------------------- 5. 扩容: 新 Pod + 新 PVC -----------------------------
do_scale() {
    step "scale" "扩容: 3 -> 5 副本 (web-3 Ready 后才创建 web-4)"
    kubectl scale "statefulset/${STS}" --replicas=5 -n "${NAMESPACE}"
    kubectl rollout status "statefulset/${STS}" -n "${NAMESPACE}"
    kubectl get pods -l "${LABEL}" -n "${NAMESPACE}"

    step "scale" "新增两个 PVC: data-web-3 / data-web-4 自动创建"
    kubectl get pvc -l "${LABEL}" -n "${NAMESPACE}"

    step "scale" "缩容回 3: 按 4 -> 3 逆序删除; 但 PVC data-web-3/4 会保留"
    kubectl scale "statefulset/${STS}" --replicas=3 -n "${NAMESPACE}"
    kubectl rollout status "statefulset/${STS}" -n "${NAMESPACE}"
    kubectl get pvc -l "${LABEL}" -n "${NAMESPACE}"
}

# ----------------------------- 6. 清理 -----------------------------
do_clean() {
    step "clean" "删除 StatefulSet 与 Service (PVC 不会被删除!)"
    kubectl delete statefulset/"${STS}" service/"${HEADLESS}" \
        -n "${NAMESPACE}" --wait=true
    step "clean" "手工删除 PVC (StatefulSet 不代管 PVC, 数据安全 > 便利)"
    kubectl delete pvc -l "${LABEL}" -n "${NAMESPACE}" --wait=true
    kubectl get all,pvc -l "${LABEL}" -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        apply)  do_apply ;;
        dns)    do_dns ;;
        pvc)    do_pvc ;;
        stable) do_stable ;;
        scale)  do_scale ;;
        clean)  do_clean ;;
        all)    do_apply; do_dns; do_pvc; do_stable; do_scale; do_clean ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: apply | dns | pvc | stable | scale | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
