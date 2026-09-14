#!/usr/bin/env bash
# =============================================================================
# Kubernetes HPA 自动扩缩容全流程演示脚本
# 覆盖: 装 metrics-server -> 部署应用+HPA -> 压测触发扩容 -> 撤压测看缩容 -> 清理
# 用法: ./hpa.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 load)只执行该步骤
# =============================================================================
set -euo pipefail

# ----------------------------- 全局配置 -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"
NAMESPACE="default"                 # 演示用的 namespace
DEPLOY="cpu-stress-app"             # 被扩缩容的 Deployment
HPA="${DEPLOY}-hpa"                 # HPA 名称
LABEL="app=${DEPLOY}"               # 标签选择器, 便于过滤 Pod

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装 metrics-server -----------------------------
do_metrics() {
    step "metrics" "安装 metrics-server (HPA 的 CPU/内存指标来源)"
    # 官方组件清单; 已装会报错, 故先判断
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        echo "metrics-server 已存在, 跳过安装"
    else
        # 优先用本地清单 (github 直连可能超时); 清单版本 v0.9.0
        local manifest="manifests/metrics-server.yaml"
        if [ ! -f "$manifest" ]; then
            kubectl apply -f \
              https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        else
            kubectl apply -f "$manifest"
        fi
        # kind/minikube 等本地集群, kubelet 证书无 CA 签名, 不加此参数 metrics-server
        # 会因 x509 验证失败而崩溃, 必须打补丁:
        kubectl patch deployment metrics-server -n kube-system \
            --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
        # 镜像拉取失败时, 先在宿主机走镜像源并导入节点:
        #   ../../scripts/load_images.sh registry.k8s.io/metrics-server/metrics-server:v0.9.0
    fi
    kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s

    step "metrics" "验证: kubectl top (能出数说明指标链路已通)"
    kubectl top nodes           # kubelet cAdvisor -> metrics-server -> API
    kubectl top pods -n kube-system | head -5
}

# ----------------------------- 2. 部署应用 + HPA -----------------------------
do_apply() {
    step "apply" "创建 Deployment (requests.cpu=100m) 与 HPA (1~10 副本, 目标 50%)"
    kubectl apply -f manifests/hpa.yaml

    step "apply" "等待应用就绪, 再看 HPA 初始状态 (TARGETS 可能显示 <unknown>)"
    kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}"
    kubectl get hpa "${HPA}" -n "${NAMESPACE}"
    # <unknown> 常见原因: metrics-server 未就绪 / Pod 没设 resources.requests
}

# ----------------------------- 3. 制造负载, 触发扩容 -----------------------------
do_load() {
    step "load" "启动压测 Pod: 持续请求目标应用的 /cgi-bin/spin (每个请求在目标 Pod 内烧 CPU)"
    # ★ 压测必须打到目标应用且让其消耗 CPU: CGI 脚本会在 app Pod 内执行 CPU 循环
    #   (打静态页 CPU 永远 0%, HPA 不会扩容; 真实压测可换 hey/wrk)
    kubectl run load-gen --image=busybox:1.36 --restart=Never -n "${NAMESPACE}" -- \
      /bin/sh -c 'while true; do wget -q -O- http://'"${DEPLOY}"':8080/cgi-bin/spin >/dev/null; done'

    step "load" "观察 HPA 扩容 (15s 一个周期; CPU 超过 50% 就扩副本)"
    kubectl get hpa "${HPA}" -n "${NAMESPACE}" -w --request-timeout=120s || true
    # 期望现象: REPLICAS 从 1 涨到接近 10; TARGETS 列 (CPU%/requests) 向 50% 收敛
}

# ----------------------------- 4. 撤掉负载, 观察缩容 -----------------------------
do_unload() {
    step "unload" "删除压测 Pod, 负载归零"
    kubectl delete pod load-gen --ignore-not-found -n "${NAMESPACE}" --wait=false

    step "unload" "观察缩容: 需先熬过 300s 稳定窗口 (防抖动)"
    kubectl get hpa "${HPA}" -n "${NAMESPACE}" -w --request-timeout=360s || true
    # 期望现象: CPU 归零后 HPA 并不立刻缩容, ~5 分钟后才开始逐步降副本
    kubectl top pods -l "${LABEL}" -n "${NAMESPACE}"
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源 (HPA 与应用一并清掉)"
    kubectl delete -f manifests/hpa.yaml --wait=true --ignore-not-found=true
    kubectl delete pod load-gen --ignore-not-found -n "${NAMESPACE}" || true
    # --wait 只覆盖清单里的 Deployment/HPA；级联删除的 Pod 是异步的，等它们真正消失
    kubectl wait --for=delete pod -l "${LABEL}" -n "${NAMESPACE}" --timeout=120s || true
    kubectl get deploy,hpa,pods -l "${LABEL}" -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        metrics) do_metrics ;;
        apply)   do_apply ;;
        load)    do_load ;;
        unload)  do_unload ;;
        clean)   do_clean ;;
        all)
            do_metrics; do_apply; do_load; do_unload; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: metrics | apply | load | unload | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
