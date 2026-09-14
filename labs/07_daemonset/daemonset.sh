#!/usr/bin/env bash
# =============================================================================
# Kubernetes DaemonSet 全流程演示脚本
# 覆盖: 创建 -> 验证每节点一个 Pod -> 查看分布 -> describe/rollout
#       -> 给节点打标签观察选择性调度 -> 清理
# 用法: ./daemonset.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 label)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"               # 演示用的 namespace
DS="log-collector"                # 主 DaemonSet 名称 (日志采集)
DS_SSD="ssd-cache-agent"          # nodeAffinity 版 DaemonSet
LABEL="app=${DS}"                 # 标签选择器, 便于过滤 Pod

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 创建并验证"每节点一个" -----------------------------
do_apply() {
    step "apply" "创建 DaemonSet (日志采集 + SSD 缓存 Agent)"
    kubectl apply -f manifests/daemonset.yaml

    step "apply" "等待滚动发布完成"
    kubectl rollout status "daemonset/${DS}" -n "${NAMESPACE}"

    step "verify" "对比: 节点数 vs DaemonSet Pod 数 (两者应相等)"
    NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    # 只统计 Running 的 Pod, 避免残留的 Terminating Pod 干扰计数
    PODS=$(kubectl get pods -l "${LABEL}" -n "${NAMESPACE}" \
        --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
    echo "节点数 = ${NODES},  Pod 数 = ${PODS}"
    [ "${NODES}" = "${PODS}" ] \
        && echo "OK: 每个节点恰好一个 Pod" \
        || echo "WARN: 数量不一致 (可能有节点未就绪/被 cordon/选择器不匹配)"

    step "verify" "查看期望/当前/就绪副本数 (desired 应等于节点数)"
    kubectl get daemonset -n "${NAMESPACE}"
}

# ----------------------------- 2. 查看 Pod 分布 -----------------------------
do_dist() {
    step "dist" "用 -o wide 查看 NODE 列: 每个节点名只出现一次"
    kubectl get pods -l "${LABEL}" -n "${NAMESPACE}" -o wide

    step "dist" "describe daemonset: 关键看 Nodes Scheduled / Pods Current"
    kubectl describe daemonset "${DS}" -n "${NAMESPACE}" | head -30
}

# ----------------------------- 3. 滚动更新演示 -----------------------------
do_update() {
    step "update" "触发滚动更新 (改镜像), DaemonSet 默认逐节点替换"
    kubectl set image "daemonset/${DS}" "collector=busybox:1.37" -n "${NAMESPACE}"
    kubectl rollout status "daemonset/${DS}" -n "${NAMESPACE}"

    step "update" "查看历史与回滚"
    kubectl rollout history "daemonset/${DS}" -n "${NAMESPACE}"
    kubectl rollout undo "daemonset/${DS}" -n "${NAMESPACE}"
    kubectl rollout status "daemonset/${DS}" -n "${NAMESPACE}"
}

# ----------------------------- 4. 节点标签与选择性调度 -----------------------------
do_label() {
    step "label" "当前 ssd-cache-agent Pod 数 (还没有节点带 disktype=ssd)"
    kubectl get pods -l "app=${DS_SSD}" -n "${NAMESPACE}" -o wide || true

    step "label" "挑选一个 worker 节点打上 disktype=ssd 标签"
    # ssd-cache-agent 没有控制面容忍度, 必须选 worker 节点 (排除 control-plane)
    TARGET_NODE=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        | grep -v control-plane | head -1)
    kubectl label node "${TARGET_NODE}" disktype=ssd --overwrite
    echo "已标记节点: ${TARGET_NODE}"

    step "label" "DaemonSet 控制器感知标签变化, 立即在新匹配节点补一个 Pod"
    sleep 3
    kubectl get pods -l "app=${DS_SSD}" -n "${NAMESPACE}" -o wide

    step "label" "去掉标签再观察: Pod 被自动删除 (nodeAffinity 不再匹配)"
    kubectl label node "${TARGET_NODE}" disktype-
    sleep 2
    kubectl get pods -l "app=${DS_SSD}" -n "${NAMESPACE}" -o wide || echo "(无 Pod, 符合预期)"
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源"
    kubectl delete -f manifests/daemonset.yaml --wait=true --ignore-not-found=true
    # --wait 只覆盖 DaemonSet 本身；级联删除的 Pod 是异步的，等它们真正消失
    kubectl wait --for=delete pod -l app=log-collector -n "${NAMESPACE}" --timeout=120s || true
    kubectl wait --for=delete pod -l app=ssd-cache-agent -n "${NAMESPACE}" --timeout=120s || true
    kubectl get daemonset,pods -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        apply)  do_apply ;;
        dist)   do_dist ;;
        update) do_update ;;
        label)  do_label ;;
        clean)  do_clean ;;
        all)    do_apply; do_dist; do_update; do_label; do_clean ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: apply | dist | update | label | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
