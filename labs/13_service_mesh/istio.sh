#!/usr/bin/env bash
# =============================================================================
# Service Mesh (Istio) 金丝雀发布全流程演示脚本
# 覆盖: install(装 Istio) -> deploy(部署应用+验证注入) -> test(压测分流) -> clean
# 用法: ./istio.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 test)只执行该步骤
# 注意: 国内网络下 istioctl 下载与 Istio 镜像拉取均可能失败, 详见 do_install;
#       若安装失败, service_mesh.yaml 与 README.md 仍可作为学习材料
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="canary-demo"          # 演示用的 namespace (YAML 里定义)
SERVICE="canary-web"             # 演示服务名
ISTIO_VERSION="1.23.0"           # istioctl / Istio 版本
ISTIOCTL="/usr/local/bin/istioctl"
MIRROR="docker.m.daocloud.io"    # 国内镜像源

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装 Istio -----------------------------
# Istio 需要先装控制面 istiod, 再给业务 Pod 注入 sidecar
do_install() {
    step "install" "检查 istioctl 命令行工具"
    if ! command -v istioctl >/dev/null 2>&1; then
        echo "istioctl 未安装, 尝试自动安装 (两种途径, 均可能因网络失败)..."
        # 途径 1: brew (macOS 推荐)
        if command -v brew >/dev/null 2>&1; then
            echo "[try] brew install istioctl"
            brew install istioctl || echo "[warn] brew 安装失败, 回退到 curl" >&2
        fi
        # 途径 2: 从 github release 下载 (国内网络不稳定, 失败只能手动安装)
        if ! command -v istioctl >/dev/null 2>&1; then
            echo "[try] curl 下载 istioctl ${ISTIO_VERSION} (github 直连易超时)"
            curl -fsSL "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-osx.tar.gz" \
                -o /tmp/istioctl.tar.gz \
                && tar -xzf /tmp/istioctl.tar.gz -C /tmp \
                && sudo mv /tmp/istioctl "${ISTIOCTL}" \
                || { echo "[error] istioctl 安装失败: 请手动安装后再运行本步骤;" \
                     echo "        YAML 清单与 README.md 仍可作为学习材料" >&2; return 1; }
        fi
    fi
    istioctl version

    step "install" "kind 集群镜像预载 (Istio 组件 ~10 个镜像, 节点无法直连 docker.io)"
    echo "Istio 需要的核心镜像 (istiod 用 pilot, sidecar/gateway 用 proxyv2):"
    echo "  docker pull ${MIRROR}/istio/pilot:${ISTIO_VERSION}"
    echo "  docker pull ${MIRROR}/istio/proxyv2:${ISTIO_VERSION}"
    echo "  docker tag  ${MIRROR}/istio/pilot:${ISTIO_VERSION}   docker.io/istio/pilot:${ISTIO_VERSION}"
    echo "  docker tag  ${MIRROR}/istio/proxyv2:${ISTIO_VERSION} docker.io/istio/proxyv2:${ISTIO_VERSION}"
    echo "然后导入所有 kind 节点: ../../scripts/load_images.sh istio/pilot:${ISTIO_VERSION} istio/proxyv2:${ISTIO_VERSION}"
    echo "(demo profile 之外, istioctl 还可能拉取 ext-authz 等附加镜像, 按报错补齐即可)"

    step "install" "安装 Istio 控制面 (demo profile: 单副本 istiod, 资源占用最小)"
    istioctl install --set profile=demo --skip-confirmation
    kubectl get pods -n istio-system
}

# ----------------------------- 2. 部署应用并验证注入 -----------------------------
do_deploy() {
    step "deploy" "应用清单 (namespace 带 istio-injection=enabled 标签)"
    kubectl apply -f manifests/service_mesh.yaml

    step "deploy" "等待两个版本全部就绪"
    kubectl rollout status deployment/canary-web-v1 -n "${NAMESPACE}"
    kubectl rollout status deployment/canary-web-v2 -n "${NAMESPACE}"

    step "deploy" "验证 sidecar 已注入: 每个 Pod 应有 2 个容器 (业务容器 + istio-proxy)"
    kubectl get pods -n "${NAMESPACE}" -o custom-columns=\
'NAME:.metadata.name,CONTAINERS:.spec.containers[*].name'
    # jsonpath 版本: 打印容器名列表, 形如 "web,istio-proxy" 即注入成功
    for pod in $(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}'); do
        kubectl get pod "${pod}" -n "${NAMESPACE}" \
            -o jsonpath='{.spec.containers[*].name}'; echo "  <- ${pod}"
    done

    step "deploy" "查看 VirtualService / DestinationRule 当前分流规则"
    kubectl get virtualservice,destinationrule -n "${NAMESPACE}"
}

# ----------------------------- 3. 金丝雀分流测试 -----------------------------
do_test() {
    step "test" "发起 20 次请求, 统计 v1 / v2 命中次数 (期望约 90% / 10%)"
    kubectl run mesh-test --rm -i --restart=Never --image=busybox:1.36 -n "${NAMESPACE}" -- \
        sh -c 'v1=0; v2=0;
               for i in $(seq 1 20); do
                   r=$(wget -qO- http://'"${SERVICE}"':8080/);
                   case "$r" in
                       *v1*) v1=$((v1+1));;
                       *v2*) v2=$((v2+1));;
                   esac;
               done;
               echo "web-v1 命中: $v1 次 / web-v2 命中: $v2 次 (共 20)"'
    # 注: 20 次请求下 90/10 意味着 v2 平均 2 次, 少量随机波动属正常;
    #     想验证 header 路由, 参考 service_mesh.yaml 备选方案 B 中的 wget --header 示例
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除演示资源 (namespace 一并删除, sidecar 随 Pod 销毁)"
    kubectl delete -f manifests/service_mesh.yaml --wait=true
    echo "Istio 本体保留在 istio-system; 彻底卸载可执行:"
    echo "  istioctl uninstall --purge && kubectl delete namespace istio-system"
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        install) do_install ;;
        deploy)  do_deploy ;;
        test)    do_test ;;
        clean)   do_clean ;;
        all)
            do_install; do_deploy; do_test; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: install | deploy | test | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
