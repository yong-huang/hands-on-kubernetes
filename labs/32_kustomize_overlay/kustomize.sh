#!/usr/bin/env bash
# =============================================================================
# 32_kustomize_overlay 演示脚本:
#   build(渲染对比) -> deploy(apply -k) -> change(改配置触发哈希滚动) -> clean
# 用法: ./kustomize.sh [build|deploy|verify|change|clean|all]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"
NS="kustomize-demo"

step() { echo; echo "=====> [$1] $2"; }

# 等待 exec 输出变为期望值 (kubelet 同步 ConfigMap 卷有 ~1min 延迟)
wait_response() {  # $1=deployment $2=期望内容
    for _ in $(seq 1 30); do
        R=$(kubectl -n "${NS}" exec "deploy/$1" -- curl -s localhost:80 2>/dev/null || true)
        [ "${R}" = "$2" ] && return 0
        sleep 5
    done
    echo "警告: $1 在 150s 内未同步到 $2 (实际: ${R})"
    return 1
}

# ----------------------------- 1. 渲染对比 -----------------------------
do_build() {
    step "build" "渲染 dev 与 staging 两个 overlay, 对比差异"
    echo "--- kubectl kustomize overlays/dev (节选) ---"
    kubectl kustomize overlays/dev | grep -E "hello-from|replicas:|image:|namespace:|web-config-" | head -12
    echo ""
    echo "--- kubectl kustomize overlays/staging (节选) ---"
    kubectl kustomize overlays/staging | grep -E "hello-from|replicas:|image:|namespace:|web-config-" | head -12
    echo ""
    echo "观察点: dev 有 nameSuffix -dev / 副本 1 / 响应体 hello-from-dev;"
    echo "        staging 无后缀 / 副本 2 / 响应体 hello-from-staging;"
    echo "        ConfigMap 名带哈希后缀(configMapGenerator), 内容一变哈希就变"
}

# ----------------------------- 2. 部署 dev -----------------------------
do_deploy() {
    step "deploy" "kubectl apply -k overlays/dev (命名空间 ${NS} 自动创建)"
    kubectl apply -k overlays/dev
    kubectl -n "${NS}" rollout status deployment/web-dev --timeout=120s
    kubectl -n "${NS}" get deploy,pod,svc,cm
}

# ----------------------------- 3. 改配置触发哈希滚动 -----------------------------
do_change() {
    step "change" "部署 staging -> 改其 default.conf 内容 -> 哈希变化触发滚动"
    kubectl apply -k overlays/staging
    kubectl -n "${NS}" rollout status deployment/web --timeout=120s
    BEFORE=$(kubectl -n "${NS}" get deploy web -o jsonpath='{.spec.template.spec.volumes[0].configMap.name}')
    sed -i.bak 's/hello-from-staging/hello-from-staging-v2/' overlays/staging/default.conf
    kubectl apply -k overlays/staging
    AFTER=$(kubectl -n "${NS}" get deploy web -o jsonpath='{.spec.template.spec.volumes[0].configMap.name}')
    mv overlays/staging/default.conf.bak overlays/staging/default.conf   # 先还原磁盘(内容已进哈希, 不影响集群)
    kubectl -n "${NS}" rollout status deployment/web --timeout=120s || true
    wait_response web "hello-from-staging-v2"   # kubelet 同步 ConfigMap 卷有 ~1min 延迟, 轮询到位
    echo "ConfigMap 引用: ${BEFORE}  ->  ${AFTER}"
    echo "观察点: 只改了 ConfigMap 内容, Deployment 的配置哈希引用跟着变, Pod 自动滚动——"
    echo "        这就是 configMapGenerator 解决'改了配置 Pod 不知道'的方式(对照 labs/05 的热更新三句话)"
}

# ----------------------------- 4. 验证 -----------------------------
do_verify() {
    step "verify" "验证 dev 环境响应/副本/镜像, staging 响应与副本"
    wait_response web-dev "hello-from-dev"
    echo -n "dev  响应: "; kubectl -n "${NS}" exec deploy/web-dev -- curl -s localhost:80 || true
    kubectl -n "${NS}" get deploy web-dev -o jsonpath='dev 规格: {.spec.replicas} 副本 / {.spec.template.spec.containers[0].image}{"\n"}'
    echo -n "staging 响应: "; kubectl -n "${NS}" exec deploy/web -- curl -s localhost:80 || true
    echo "(staging 服务的是上一步修改后的 v2 内容——文件已还原, 集群仍收敛在最新声明)"
    kubectl -n "${NS}" get deploy web -o jsonpath='staging 规格: {.spec.replicas} 副本 / {.spec.template.spec.containers[0].image}{"\n"}'
    echo "成功判据: dev 返回 hello-from-dev(1 副本), staging 返回 hello-from-staging-v2(2 副本)——同一 base 渲染出两个环境, 且 staging 服务的是 change 步骤修改后的内容(以实际运行为准)"
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除命名空间 (overlay 生成的资源一并清理)"
    kubectl delete namespace "${NS}" --ignore-not-found
}

case "${1:-all}" in
    build)  do_build ;;
    deploy) do_deploy ;;
    verify) do_verify ;;
    change) do_change ;;
    clean)  do_clean ;;
    all)    do_build; do_deploy; do_change; do_verify ;;
    *) echo "用法: $0 [build|deploy|verify|change|clean|all]"; exit 1 ;;
esac
