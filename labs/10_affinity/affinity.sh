#!/usr/bin/env bash
# =============================================================================
# Kubernetes 亲和性与拓扑打散调度演示脚本 (kind 多节点集群)
# 覆盖: 节点打标签 -> podAntiAffinity 打散 -> nodeAffinity 选节点 -> topologySpread
# 用法: ./affinity.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 spread)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 节点打标签 -----------------------------
do_label() {
    step "label" "给节点打上 zone / disktype 标签 (nodeAffinity 依赖它们)"
    # 取前两个 worker 节点 (kind 集群 control-plane 不跑业务 Pod, 有污点)
    local nodes
    nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' \
        | tr ' ' '\n' | grep -v control-plane | head -2)
    for n in ${nodes}; do
        kubectl label node "${n}" disktype=ssd --overwrite
    done
    # 第一个节点再标为东区, 供 preferred 权重演示
    local first
    first=$(echo "${nodes}" | head -1)
    kubectl label node "${first}" zone=east --overwrite
    kubectl get nodes -L zone,disktype     # -L 直接展示这两列标签
}

# ----------------------------- 2. podAntiAffinity 打散 -----------------------------
do_antiaffinity() {
    step "antiaffinity" "应用硬性反亲和 Deployment (每节点最多 1 副本)"
    kubectl apply -f manifests/affinity.yaml

    step "antiaffinity" "观察 NODE 列: 副本已分散到不同节点"
    kubectl wait --for=condition=Ready pod -l app=web-required \
        --timeout=60s
    kubectl get pods -l app=web-required -o wide

    step "antiaffinity" "软性反亲和副本也应尽量分散 (节点不够时允许共存)"
    kubectl get pods -l app=web-preferred -o wide
}

# ----------------------------- 3. nodeAffinity 选节点 -----------------------------
do_nodeaffinity() {
    step "nodeaffinity" "确认 Pod 落在 disktype=ssd 的节点上"
    kubectl wait --for=condition=Ready pod/on-ssd-node --timeout=60s
    kubectl get pod on-ssd-node -o wide

    step "nodeaffinity" "对照节点标签: 所在节点应同时有 zone=east (preferred 权重)"
    kubectl get nodes -L zone,disktype
}

# ----------------------------- 4. topologySpreadConstraints -----------------------------
do_spread() {
    step "spread" "观察 web-spread 分布 (4 副本, 只有 2 个能跑)"
    sleep 10                                   # 等调度器决策并打事件
    kubectl get pods -l app=web-spread -o wide
    echo "--- 每节点副本数统计 ---"
    kubectl get pods -l app=web-spread -o jsonpath=\
'{range .items[*]}{.spec.nodeName}{"\n"}{end}' | awk 'NF' | sort | uniq -c
    echo "(Pending 的 Pod 没有 NODE, 所以不出现在统计里)"

    step "spread" "describe 查看 FailedScheduling 事件 (违反 maxSkew=1)"
    echo "原理: web-spread 不容忍 control-plane 污点, Pod 进不去控制面节点,"
    echo "      但控制面仍被计为 1 个拓扑域(0 副本)。两个 worker 各放 1 个后"
    echo "      (1/1/0), 第 3 个副本放任何 worker 都会让 skew=2 > maxSkew=1,"
    echo "      DoNotSchedule 直接拒绝 -> 剩余副本永远 Pending。"
    echo "对比: 若给全部 3 个节点都加了容忍, 调度器总能均衡放置 (如 4 副本 -> 2/1/1),"
    echo "      单纯加副本数不会触发拒绝 —— 拒绝只发生在'有域进不去'时。"
    kubectl describe pod -l app=web-spread | grep -A3 -B1 "FailedScheduling" || true
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源"
    kubectl delete -f manifests/affinity.yaml --wait=true

    step "clean" "移除节点标签 (还原现场)"
    kubectl get nodes -o jsonpath=\
'{range .items[*]}{.metadata.name}{"\n"}{end}' \
        | xargs -I{} kubectl label node {} disktype- zone- 2>/dev/null || true
    kubectl get nodes -L zone,disktype
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        label)        do_label ;;
        antiaffinity) do_antiaffinity ;;
        nodeaffinity) do_nodeaffinity ;;
        spread)       do_spread ;;
        clean)        do_clean ;;
        all)
            do_label; do_antiaffinity; do_nodeaffinity; do_spread; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: label | antiaffinity | nodeaffinity | spread | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
