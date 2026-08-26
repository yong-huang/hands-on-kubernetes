#!/usr/bin/env bash
# =============================================================================
# ArgoCD GitOps 演示脚本
# 覆盖: install(安装) -> app(注册应用) -> status(状态) -> sync(同步) -> clean(清理)
# 用法: ./argocd.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 sync)只执行该步骤
#
# 【离线安装说明】
#   ArgoCD 官方安装清单约 7000 行, 本仓库不 vendor, 安装时按优先级尝试:
#     1) 本目录下的 argocd-install.yaml (若你已手动保存, 走本地文件, 最可靠)
#     2) curl raw.githubusercontent.com (github 直连不稳定, 可能超时)
#   手动缓存方法(任选其一, 保存为 ./argocd-install.yaml 即可):
#     curl -fsSL -o argocd-install.yaml \
#       https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
#     # 或在能访问 github 的机器上下载后拷贝过来
#
# 【镜像预载说明】ArgoCD 组件镜像托管在 quay.io, 国内常 TLS 超时。
#   清单里的关键镜像(以 stable 实际 tag 为准, 可 grep quay.io argocd-install.yaml):
#     quay.io/argoproj/argocd            (server / repo-server / applicationset / dex 共用)
#     quay.io/argoproj/argocd-applicationset-controller  (较新版本单拆)
#     docker.io/library/redis            (argocd-redis, 可用 ../../scripts/load_images.sh 预载)
#     ghcr.io/dexidp/dex                 (SSO 登录组件, 新版本镜像源)
#   预载方法(参考系列根目录 scripts/load_images.sh: 宿主机拉 -> save -> ctr import):
#     docker pull docker.m.daocloud.io/quay.io/argoproj/argocd:v2.13.3
#     docker tag  docker.m.daocloud.io/quay.io/argoproj/argocd:v2.13.3 \
#                quay.io/argoproj/argocd:v2.13.3
#     for n in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
#       docker save quay.io/argoproj/argocd:v2.13.3 \
#         | docker exec --privileged -i "${n}" ctr --namespace=k8s.io images import -
#     done
#   注意: 版本号要与清单里的一致(先 grep 清单再拉), redis 走 docker.m.daocloud.io/library/redis。
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
ARGOCD_NS="argocd"                          # ArgoCD 自身所在命名空间
APP_NS="guestbook"                          # 示例应用所在命名空间
APP_FILE="manifests/app-of-apps.yaml"                 # Application 定义文件
LOCAL_MANIFEST="manifests/argocd-install.yaml"        # 本地缓存的安装清单(优先使用)
REMOTE_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }
hr()   { echo "--------------------------------------------------"; }

# ----------------------------- 0. 安装 ArgoCD -----------------------------
do_install() {
    step "install" "创建命名空间 ${ARGOCD_NS}"
    kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -

    step "install" "应用安装清单 (本地缓存 > jsdelivr CDN > github 直连)"
    if [[ -f "${LOCAL_MANIFEST}" ]]; then
        echo "[info] 使用本地缓存 ${LOCAL_MANIFEST}"
        kubectl apply -n "${ARGOCD_NS}" -f "${LOCAL_MANIFEST}"
    else
        # 实测: raw.githubusercontent.com 直连常超时, jsdelivr CDN 基本可用
        echo "[info] 无本地缓存, 依次尝试 jsdelivr CDN 与 github 直连..."
        if curl -fsSL --connect-timeout 10 --max-time 120 \
              "https://cdn.jsdelivr.net/gh/argoproj/argo-cd@stable/manifests/install.yaml" \
              -o "${LOCAL_MANIFEST}" 2>/dev/null && [[ -s "${LOCAL_MANIFEST}" ]]; then
            echo "[info] jsdelivr 下载成功, 已缓存为 ${LOCAL_MANIFEST}"
            kubectl apply -n "${ARGOCD_NS}" -f "${LOCAL_MANIFEST}"
        else
            rm -f "${LOCAL_MANIFEST}"
            echo "[info] jsdelivr 失败, 尝试 github 直连 (可能超时)..."
            curl -fsSL "${REMOTE_MANIFEST}" | kubectl apply -n "${ARGOCD_NS}" -f -
        fi
    fi

    step "install" "修补 argocd-redis: 清单里 imagePullPolicy=Always 且镜像在 docker.io"
    # 实测坑: argocd-redis 的 redis 镜像在 docker.io, 节点常拉不到, 且策略为
    # Always —— 即使 ../../scripts/load_images.sh 预载了节点也不会用本地镜像。
    # 补丁只改 imagePullPolicy=IfNotPresent; 镜像 tag 不硬编码,
    # 优先从缓存的安装清单里解析, 拿不到再读当前 Deployment 的实际值。
    REDIS_IMAGE=""
    if [[ -f "${LOCAL_MANIFEST}" ]]; then
        REDIS_IMAGE="$(grep -m1 -oE 'image: *redis:[0-9][0-9a-zA-Z._-]*' "${LOCAL_MANIFEST}" \
            | head -1 | sed 's/^image: *//')"
    fi
    REDIS_IMAGE="${REDIS_IMAGE:-$(kubectl -n "${ARGOCD_NS}" get deployment argocd-redis \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)}"
    if [[ -n "${REDIS_IMAGE}" ]]; then
        echo "[info] redis 镜像: ${REDIS_IMAGE}"
        REDIS_PATCH="$(printf \
            '{"spec":{"template":{"spec":{"$setElementOrder/containers":[{"name":"redis"}],"containers":[{"name":"redis","image":"%s","imagePullPolicy":"IfNotPresent"}]}}}}' \
            "${REDIS_IMAGE}")"
        kubectl patch deployment argocd-redis -n "${ARGOCD_NS}" --type=strategic \
            -p "${REDIS_PATCH}" \
            2>/dev/null || echo "[hint] patch 失败(可能已改过), 手动处理见脚本注释"
    else
        echo "[hint] 未能确定 redis 镜像 tag, 跳过 patch; 可手动执行:"
        echo "  kubectl -n ${ARGOCD_NS} patch deploy argocd-redis --type=strategic \\"
        echo "    -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"redis\",\"imagePullPolicy\":\"IfNotPresent\"}]}}}}'"
    fi

    step "install" "等待 ArgoCD 核心组件就绪 (application-controller 为领头组件)"
    kubectl rollout status deployment/argocd-server -n "${ARGOCD_NS}"
    kubectl rollout status deployment/argocd-repo-server -n "${ARGOCD_NS}"
    kubectl rollout status statefulset/argocd-application-controller -n "${ARGOCD_NS}"

    step "install" "查看组件 Pod (镜像来自 quay.io, 若 Pending/ImagePullBackOff 见头部镜像预载说明)"
    kubectl get pods -n "${ARGOCD_NS}" -o wide

    hr
    echo "初始 admin 密码(随机生成):"
    echo "  kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NS} \\"
    echo "    -o jsonpath='{.data.password}' | base64 -d; echo"
    echo "Web UI 端口转发(另开终端):"
    echo "  kubectl port-forward svc/argocd-server -n ${ARGOCD_NS} 8080:443"
    echo "浏览器访问 https://localhost:8080 (用户名 admin)"
}

# ----------------------------- 1. 注册应用 -----------------------------
do_app() {
    step "app" "apply ${APP_FILE}: 把 Git 仓库与集群目标的映射声明给 ArgoCD"
    kubectl apply -n "${ARGOCD_NS}" -f "${APP_FILE}"

    step "app" "查看 Application CR"
    kubectl get applications -n "${ARGOCD_NS}"
    echo "[info] automated + selfHeal 已开启, ArgoCD 会自动把 guestbook 目录同步到集群"
}

# ----------------------------- 2. 查看状态 -----------------------------
do_status() {
    step "status" "ArgoCD 视角的应用健康/同步状态"
    kubectl get applications -n "${ARGOCD_NS}" \
        -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

    step "status" "实际部署出来的资源 (期望状态已被拉取到集群)"
    kubectl get all -n "${APP_NS}"

    hr
    echo "纯 kubectl 之外, 也可用 argocd CLI (需另装):"
    echo "  argocd app list            # 应用列表"
    echo "  argocd app get guestbook   # 单应用详情(Synced/Healthy)"
    echo "  argocd app diff guestbook  # 查看 Git 与集群的差异"
}

# ----------------------------- 3. 同步的三种方式 -----------------------------
do_sync() {
    step "sync" "方式 1: 自动同步 (本示例默认): Git 变更后 ~3 分钟内 ArgoCD 自动拉取并 apply"
    echo "[info] syncPolicy.automated 开启时无需任何人工动作, 这就是 Pull 模型"

    step "sync" "方式 2: 手动触发 (CLI / UI), 集群凭据不出集群, 无需 kubectl 权限下发"
    echo "  argocd app sync guestbook          # 立即同步, 不等轮询周期"

    step "sync" "方式 3: kubectl 注解强制刷新 (无 CLI 时的土办法)"
    echo "  kubectl patch application guestbook -n ${ARGOCD_NS} --type merge \\"
    echo "    -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}'"

    step "sync" "同步结果: guestbook 命名空间的 Pod"
    kubectl get pods -n "${APP_NS}" -o wide
}

# ----------------------------- 4. 清理 -----------------------------
do_clean() {
    step "clean" "删除 Application (finalizer 会连带清理它创建出的资源)"
    kubectl delete -n "${ARGOCD_NS}" -f "${APP_FILE}" --ignore-not-found

    step "clean" "删除应用命名空间"
    kubectl delete namespace "${APP_NS}" --ignore-not-found

    step "clean" "(可选) 卸载 ArgoCD 本体, 需要时再执行"
    echo "  kubectl delete namespace ${ARGOCD_NS}   # 会连 CRD 里的 Application 一起清掉"
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        install) do_install ;;
        app)     do_app ;;
        status)  do_status ;;
        sync)    do_sync ;;
        clean)   do_clean ;;
        all)
            do_install; do_app; do_status; do_sync; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: install | app | status | sync | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
