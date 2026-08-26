#!/usr/bin/env bash
# =============================================================================
# Kubernetes RBAC 权限验证全流程演示脚本
# 覆盖: deploy(创建身份) -> verify(auth can-i 正向验证) -> deny(真实拒绝报错) -> clean
# 用法: ./rbac.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 verify)只执行该步骤
# 核心工具: kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> (模拟身份, 无需真实凭据)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="rbac-demo"
VIEWER="system:serviceaccount:${NAMESPACE}:dev-viewer"   # 只读身份 (模拟用完整用户名)
DEPLOYER="system:serviceaccount:${NAMESPACE}:deployer"   # 部署身份

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# can-i 的友好封装: 打印问题描述 + 结果
can_i() {
    local who="$1"; shift
    printf '  can-i %-42s : ' "$*"
    kubectl auth can-i "$@" --as="${who}" 2>/dev/null || true
}

# ----------------------------- 1. 创建身份与授权 -----------------------------
do_deploy() {
    step "deploy" "创建 Namespace / ServiceAccount / Role / RoleBinding (apply)"
    kubectl apply -f manifests/rbac.yaml

    step "deploy" "查看两个身份 (ServiceAccount)"
    kubectl get sa -n "${NAMESPACE}"

    step "deploy" "查看角色与绑定"
    kubectl get role,rolebinding -n "${NAMESPACE}"

    step "deploy" "等待 demo-app Pod Running (供后续 get pods / logs 验证)"
    kubectl wait deployment/demo-app -n "${NAMESPACE}" \
        --for=condition=Available --timeout=60s
}

# ----------------------------- 2. 正向验证: 权限矩阵 -----------------------------
do_verify() {
    step "verify" "dev-viewer 权限矩阵 (auth can-i --as 模拟身份)"

    can_i "${VIEWER}" get pods -n "${NAMESPACE}"
    echo "    ^ 只读 Role 授权过: yes"

    can_i "${VIEWER}" get pods -n default
    echo "    ^ Role 是 ns 级的, 出了 rbac-demo 就没权限: no"

    can_i "${VIEWER}" delete pods -n "${NAMESPACE}"
    echo "    ^ verbs 只有 get/list/watch, 没有 delete: no"

    can_i "${VIEWER}" create deployments -n "${NAMESPACE}"
    echo "    ^ 只读者不能写: no"

    can_i "${VIEWER}" get pods/log -n "${NAMESPACE}"
    echo "    ^ pods/log 是独立子资源, 必须单独授权: yes"
    echo "--- 实际拉一次日志证明子资源权限真的生效 ---"
    kubectl logs deployment/demo-app -n "${NAMESPACE}" --tail=2 \
        --as="${VIEWER}"

    step "verify" "deployer 权限矩阵 (对比: 权限分离)"
    can_i "${DEPLOYER}" create deployments -n "${NAMESPACE}"
    echo "    ^ app-deployer Role 授权了 create: yes"
    can_i "${DEPLOYER}" delete deployments -n "${NAMESPACE}"
    echo "    ^ verbs 里没给 delete: no"
    can_i "${DEPLOYER}" get pods -n "${NAMESPACE}"
    echo "    ^ deployer 只有 deployments 权限, 没有 pods: no"

    step "verify" "describe rolebinding 查看完整绑定链"
    kubectl describe rolebinding dev-viewer-read-pods -n "${NAMESPACE}"
}

# ----------------------------- 3. 反向验证: 真实的拒绝 -----------------------------
do_deny() {
    step "deny" "RBAC 是 default-deny: 未授权的操作会被 apiserver 拒绝"
    echo "--- dev-viewer 尝试读 Secrets (Role 里根本没授权) ---"
    kubectl get secrets -n "${NAMESPACE}" --as="${VIEWER}" || true
    echo
    echo "解读 Error 中的三要素:"
    echo "  1. Who    : User \"system:serviceaccount:rbac-demo:dev-viewer\" (身份)"
    echo "  2. What   : get secrets (verb + resource, 还有 APIGroup 空字符串)"
    echo "  3. Where  : rbac-demo namespace (Role 生效范围)"
    echo "排查思路: 就是这条链上缺了一环 —— 没有 Binding? Role 缺这条 rule?"
    echo "          还是 Role 的 namespace 和请求的 namespace 不匹配?"

    step "deny" "deployer 越权删 Pod 同样被拒"
    kubectl delete pod -n "${NAMESPACE}" -l app=demo-app --as="${DEPLOYER}" || true
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除整个 namespace (Role/Binding/SA 全部随之消失)"
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found --wait=true
    kubectl get ns || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        deploy)  do_deploy ;;
        verify)  do_verify ;;
        deny)    do_deny ;;
        clean)   do_clean ;;
        all)
            do_deploy; do_verify; do_deny; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: deploy | verify | deny | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
