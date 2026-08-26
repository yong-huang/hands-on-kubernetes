#!/usr/bin/env bash
# =============================================================================
# Kubernetes NetworkPolicy 全流程演示脚本
# 覆盖: CNI 检查 -> 部署 -> 隔离前连通性 -> 应用策略 -> 隔离后验证 -> 清理
# 用法: ./network_policy.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 isolate)只执行该步骤
# 注意: NetworkPolicy 由 CNI 插件执行, kind 默认 kindnet 不支持!
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="demo-netpol"         # 演示用的 namespace
YAML_FILE="manifests/network_policy.yaml" # 本目录下的多文档 YAML
BACKEND_URL="http://backend"    # 同命名空间内可用 Service 短名
EVIL_POD="evil"                 # 无匹配标签的"恶意" Pod (kubectl run 创建)
TIMEOUT_SEC=3                   # wget 超时: 被策略拦截时表现为超时而非拒绝

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 0. CNI 检查 -----------------------------
check_cni() {
    step "cni" "检测 CNI 插件 (NetworkPolicy 的真正执行者)"
    if kubectl -n kube-system get ds calico-node >/dev/null 2>&1 \
       || kubectl -n kube-system get pods -l k8s-app=calico-node \
              -o name 2>/dev/null | grep -q .; then
        echo "[OK] 检测到 Calico, 策略会被真正执行"
    elif kubectl -n kube-system get ds kindnet >/dev/null 2>&1; then
        echo "[警告] 检测到 kindnet (kind 默认 CNI): 不支持 NetworkPolicy!"
        echo "  策略对象能创建成功(API server 只做格式校验), 但没有任何隔离效果;"
        echo "  本次演示中 evil Pod 的 wget 不会超时 —— 这是 CNI 的锅, 不是策略写错。"
        echo "  如需真实隔离, 为 kind 安装 Calico 的参考步骤 (镜像需预先进节点):"
        cat <<'CALICO_HINT'
    # 1) 拉取并导出镜像 (国内建议配镜像加速, docker.io/calico/*)
    #    docker pull calico/node:v3.28.0
    #    docker pull calico/cni:v3.28.0
    #    docker pull calico/pod2daemon-flexvol:v3.28.0
    #    docker save calico/node calico/cni calico/pod2daemon-flexvol -o calico.tar
    # 2) 把镜像加载进 kind 节点
    #    kind load image-archive calico.tar --name <kind集群名>
    # 3) 安装 Calico 并等待 calico-node 全部 Ready (可顺手删掉 kindnet DS)
    #    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
    #    kubectl -n kube-system rollout status ds/calico-node
CALICO_HINT
    else
        echo "[提示] 未识别出 CNI (非 kindnet/Calico), 请自行确认是否支持 NetworkPolicy"
    fi
}

# ----------------------------- 1. 部署 -----------------------------
do_deploy() {
    check_cni
    step "deploy" "创建 Namespace + backend/frontend (只 apply tier=workload 组)"
    kubectl apply -f "${YAML_FILE}" -l tier=workload
    kubectl -n "${NAMESPACE}" rollout status deployment/backend
    kubectl -n "${NAMESPACE}" rollout status deployment/frontend

    step "deploy" "创建无标签的 evil Pod (用于验证白名单外的访问被拦截)"
    kubectl -n "${NAMESPACE}" run "${EVIL_POD}" --image=busybox:1.36 \
        --restart=Never --command -- sleep 3600 >/dev/null
    kubectl -n "${NAMESPACE}" wait --for=condition=Ready \
        "pod/${EVIL_POD}" --timeout=60s
    kubectl -n "${NAMESPACE}" get pods -o wide
}

# ----------------------------- 连通性探测 (可复用) -----------------------------
probe() { # $1=展示名  $2=exec 目标 (deployment/frontend 或 pod/evil)
    if kubectl -n "${NAMESPACE}" exec "${2}" -- \
        timeout "${TIMEOUT_SEC}" wget -qO- --timeout=2 \
        "${BACKEND_URL}" >/dev/null 2>&1; then
        echo "  [${1}] wget ${BACKEND_URL} => 成功 (HTTP 可达)"
    else
        echo "  [${1}] wget ${BACKEND_URL} => 超时/失败 (被 NetworkPolicy 拦截)"
    fi
}

# ----------------------------- 2. 隔离前连通性 -----------------------------
do_test() {
    step "test" "隔离前 (还没有任何 NetworkPolicy): 所有 Pod 互访畅通"
    probe "frontend (合法客户端) " deployment/frontend
    probe "evil     (恶意客户端) " "pod/${EVIL_POD}"
}

# ----------------------------- 3. 应用隔离策略 -----------------------------
do_isolate() {
    step "isolate" "应用策略: default-deny-ingress + allow-frontend-to-backend"
    kubectl apply -f "${YAML_FILE}" -l tier=policy
    kubectl -n "${NAMESPACE}" get networkpolicy
}

# ----------------------------- 4. 隔离后验证 -----------------------------
do_verify() {
    check_cni
    step "verify" "隔离后: frontend 放行 / evil 拦截"
    probe "frontend (app=frontend, 匹配白名单)" deployment/frontend
    probe "evil     (无标签, 不在白名单内)  " "pod/${EVIL_POD}"

    step "verify" "观察 frontend 容器日志 (wget 循环应持续输出 OK)"
    kubectl -n "${NAMESPACE}" logs deployment/frontend --tail=3 || true
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除整个 namespace (evil Pod 与策略随命名空间一起消失)"
    kubectl delete namespace "${NAMESPACE}" --wait=true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        deploy)  do_deploy ;;
        test)    do_test ;;
        isolate) do_isolate ;;
        verify)  do_verify ;;
        clean)   do_clean ;;
        all)
            do_deploy; do_test; do_isolate; do_verify; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: deploy | test | isolate | verify | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
