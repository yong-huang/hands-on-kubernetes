#!/usr/bin/env bash
# Operator 系列一键部署：构建镜像 → 灌入 kind → 安装 CRD → 集群内部署 Controller
# 用法: ./deploy.sh <NN> [build|load|install|deploy|status|undeploy|all]
#   NN = 项目编号（01-10）
# 示例: ./deploy.sh 01 all
set -uo pipefail
cd "$(dirname "$0")"
export KUBECONFIG="${KUBECONFIG:-$(cd .. && pwd)/mart/kubeconfig-kind}"   # 绝对路径：make 子进程 cwd 会变

R=$(cd .. && pwd)   # 仓库根（labs/kubeconfig 定位用）

step() { echo; echo "=====> [$1] $2"; }

# 集群 API 预检：宿主机 API 周期性抽风，最长等 10 分钟
wait_api() {
    local i=0
    until kubectl --request-timeout=10s get nodes >/dev/null 2>&1; do
        i=$((i+15)); [ "$i" -ge 600 ] && { echo "❌ API 持续不可达（${i}s）"; return 1; }
        echo "  [runner] API 不可达，${i}s..." >&2
        sleep 15
    done
    return 0
}

# kind 集群名自动探测 + 兜底
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"

resolve() {  # NN -> dir / image / short / system-ns
    case "$1" in
        01) P=01_app_operator;        SHORT=app;        ;;
        02) P=02_mysql_operator;      SHORT=mysql;      ;;
        03) P=03_redis_operator;      SHORT=redis;      ;;
        04) P=04_ops_automation;      SHORT=ops;        ;;
        05) P=05_canary_operator;     SHORT=canary;     ;;
        06) P=06_nginx_operator;      SHORT=nginx;      ;;
        07) P=07_kafka_topic_operator; SHORT=kafkatopic; ;;
        08) P=08_gpu_job_operator;    SHORT=gpujob;     ;;
        09) P=09_pytorch_operator;    SHORT=pytorch;    ;;
        10) P=10_microservice_operator; SHORT=microsvc; ;;
        *) echo "未知项目编号: $1（01-10）" >&2; exit 1 ;;
    esac
    DIR="$R/operators/$P"
    IMG="operators/op-$1-$SHORT:dev"
    SYSTEM_NS=$(grep -m1 '^namespace:' "$DIR/config/default/kustomization.yaml" | awk '{print $2}')
}

do_build() {  # $1=NN
    resolve "$1"
    step "build" "宿主机构建 manager + distroless 打包（${IMG}）"
    # 容器内 go mod download 会被 Go 代理 EOF 卡死；宿主机模块缓存是热的，
    # 所以在宿主机构建二进制，再用极简 Dockerfile 打包（绕开容器内下载）
    (cd "$DIR" && GOOS=linux CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/manager-local ./cmd/main.go) || \
        { echo "❌ 宿主机构建失败"; return 1; }
    # 在项目目录内打包：构建上下文 = 项目目录，COPY 路径才对得上
    # -f - 从 stdin 读 Dockerfile；上下文显式给项目目录（`-` 会被当成 tar 上下文）
    (cd "$DIR" && printf 'FROM alpine:3.19\nCOPY --chmod=0755 bin/manager-local /manager\nUSER 65532:65532\n' | \
        docker build -f - -t "${IMG}" . >/dev/null) || { echo "❌ 镜像打包失败"; return 1; }
}

do_load() {  # 镜像同 tag 重建时 kind load 不覆盖节点旧内容，先清后灌
    resolve "$1"
    step "load" "清旧 + 灌入 kind（${KIND_CLUSTER}）"
    docker exec "kind-control-plane" crictl rmi "docker.io/$IMG" >/dev/null 2>&1 || true
    kind load docker-image "$IMG" --name "$KIND_CLUSTER" 2>&1 | tail -1 || \
        echo "  ⚠️ kind load 失败（宿主 docker API 抖动），若镜像已在节点可继续"
}

do_install() {  # CRD
    resolve "$1"
    step "install" "安装 CRD（make install）"
    (cd "$DIR" && make install >/tmp/op-deploy-install.log 2>&1) || \
        { echo "❌ make install 失败"; tail -5 /tmp/op-deploy-install.log; return 1; }
}

do_deploy() {  # $1=NN
    resolve "$1"
    step "deploy" "集群内部署 Controller（${SYSTEM_NS}，镜像 ${IMG}）"
    (cd "$DIR" && make deploy IMG="$IMG" >/tmp/op-deploy-deploy.log 2>&1) || \
        { echo "❌ make deploy 失败"; tail -8 /tmp/op-deploy-deploy.log; return 1; }
    step "wait" "等待 Controller 就绪（${SYSTEM_NS}）"
    kubectl -n "$SYSTEM_NS" rollout status deployment --timeout=300s
    kubectl -n "$SYSTEM_NS" get pods
}

do_status() {  # $1=NN
    resolve "$1"
    step "status" "$P 部署状态（${SYSTEM_NS}）"
    kubectl -n "$SYSTEM_NS" get deploy,pods 2>&1
    kubectl get crd 2>/dev/null | grep example.com | head -3
}

do_undeploy() {  # $1=NN
    resolve "$1"
    step "undeploy" "卸载 Controller（保留 CRD）"
    (cd "$DIR" && make undeploy >/dev/null 2>&1) && echo "  已卸载" || echo "  卸载失败或本就未部署"
}

main() {
    local nn="${1:-}"; [ -z "$nn" ] && { grep -q '^' /dev/null; sed -n '2,3p' "$0"; exit 1; }
    local target="${2:-all}"
    wait_api || exit 1
    case "$target" in
        build)        do_build "$nn" ;;
        load)         do_load "$nn" ;;
        install)      do_install "$nn" ;;
        deploy)       do_deploy "$nn" ;;
        status)       do_status "$nn" ;;
        undeploy)     do_undeploy "$nn" ;;
        all)          do_build "$nn" && do_load "$nn" && do_install "$nn" && do_deploy "$nn" && do_status "$nn" ;;
        *) sed -n '2,3p' "$0"; exit 1 ;;
    esac
}
main "$@"
