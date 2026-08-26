#!/usr/bin/env bash
# =============================================================================
# Kubernetes Deployment 全流程演示脚本
# 覆盖: 创建 -> 扩缩容 -> 滚动更新 -> 回滚 -> 暂停/恢复 -> 清理
# 用法: ./deploy.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 scale)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"              # 演示用的 namespace
DEPLOY="nginx-rolling"           # 主 Deployment 名称
LABEL="app=${DEPLOY}"            # 标签选择器, 便于过滤 Pod
NEW_IMAGE="nginx:1.26"           # 滚动更新的目标镜像版本

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 创建 Deployment -----------------------------
do_apply() {
    step "apply" "创建 Deployment (replicas=3, RollingUpdate)"
    kubectl apply -f manifests/deploy.yaml                 # 声明式应用 YAML

    step "apply" "等待滚动发布完成 (rollout status 阻塞直到就绪)"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"

    step "apply" "查看 Deployment / ReplicaSet / Pod 三层结构"
    kubectl get deploy,rs,pods -l "${LABEL}" -n "${NAMESPACE}" \
        -o wide
}

# ----------------------------- 2. 扩缩容 -----------------------------
do_scale() {
    step "scale" "扩容: 3 -> 5 副本"
    kubectl scale "deployment/${DEPLOY}" --replicas=5 -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"

    step "scale" "缩容: 5 -> 2 副本"
    kubectl scale "deployment/${DEPLOY}" --replicas=2 -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"

    step "scale" "恢复为 3 副本"
    kubectl scale "deployment/${DEPLOY}" --replicas=3 -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"
}

# ----------------------------- 3. 滚动更新 -----------------------------
do_update() {
    step "update" "记录更新前的 ReplicaSet (新 RS 会被创建, 旧 RS 被缩容)"
    kubectl get rs -l "${LABEL}" -n "${NAMESPACE}"

    step "update" "触发滚动更新: nginx:1.25 -> ${NEW_IMAGE}"
    kubectl set image "deployment/${DEPLOY}" "nginx=${NEW_IMAGE}" \
        -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"

    step "update" "查看 rollout 历史 (每行对应一个 ReplicaSet 修订版)"
    kubectl rollout history "deployment/${DEPLOY}" -n "${NAMESPACE}"

    step "update" "更新后对比: 旧 RS desired=0, 新 RS desired=3"
    kubectl get rs -l "${LABEL}" -n "${NAMESPACE}"
}

# ----------------------------- 4. 回滚演示 -----------------------------
do_rollback() {
    step "rollback" "回滚到上一个版本 (rollout undo)"
    kubectl rollout undo "deployment/${DEPLOY}" -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"

    step "rollback" "查看当前镜像, 确认已回到旧版本"
    kubectl get deploy "${DEPLOY}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

    step "rollback" "指定修订版回滚: --to-revision=2"
    kubectl rollout history "deployment/${DEPLOY}" -n "${NAMESPACE}"
    kubectl rollout undo "deployment/${DEPLOY}" \
        --to-revision=2 -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"
}

# ----------------------------- 5. 暂停 / 恢复发布 -----------------------------
do_pause() {
    step "pause" "暂停发布 (pause 后改动不触发 rollout, 可累积多处修改)"
    kubectl rollout pause "deployment/${DEPLOY}" -n "${NAMESPACE}"
    kubectl set image "deployment/${DEPLOY}" "nginx=nginx:1.27" \
        -n "${NAMESPACE}"
    echo "(已改镜像但未发布, rollout status 会一直等待)"
    kubectl get rs -l "${LABEL}" -n "${NAMESPACE}"

    step "pause" "恢复发布 (resume 后一次性应用累积的改动)"
    kubectl rollout resume "deployment/${DEPLOY}" -n "${NAMESPACE}"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"
}

# ----------------------------- 6. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源"
    kubectl delete -f manifests/deploy.yaml --wait=true
    kubectl get deploy,rs,pods -l "${LABEL}" -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        apply)   do_apply ;;
        scale)   do_scale ;;
        update)  do_update ;;
        rollback) do_rollback ;;
        pause)   do_pause ;;
        clean)   do_clean ;;
        all)
            do_apply; do_scale; do_update; do_rollback; do_pause; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: apply | scale | update | rollback | pause | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
