#!/usr/bin/env bash
# =============================================================================
# Karmada 全流程: install(host集群) -> join(注册两个成员) -> apply(分发)
#                 -> scale(改总副本看再平衡) -> failover(拔线演练) -> clean
# 本地实验可用 karmadactl + 两个 kind 集群模拟
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效
step() { echo; echo "=====> [$1] $2"; }

# 访问成员集群: 优先用默认 kubeconfig 里的 <cluster> context;
# 没有则回退到 kind export 出来的 ~/.kube/kind-config-<cluster> (context 名为 kind-<cluster>)
member_kubectl() {
    local cluster="$1"; shift
    if kubectl config get-contexts -o name 2>/dev/null | grep -qx "$cluster"; then
        kubectl --context "$cluster" "$@"
    elif [ -f "$HOME/.kube/kind-config-$cluster" ]; then
        kubectl --kubeconfig "$HOME/.kube/kind-config-$cluster" "$@"
    else
        echo "[error] 找不到成员集群 $cluster 的 kubeconfig" >&2
        return 1
    fi
}

do_install() {
    step "install" "安装 Karmada 控制面 (karmadactl 一键)"
    # curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/local-up-karmada.sh | bash
    kubectl --context karmada-apiserver config current-context || {
        echo "请先执行 local-up-karmada.sh 或 karmadactl init"; exit 1; }
}

do_join() {
    step "join" "注册成员集群"
    karmadactl join member-us --cluster-kubeconfig="$HOME/.kube/kind-config-member-us"
    karmadactl join member-ap --cluster-kubeconfig="$HOME/.kube/kind-config-member-ap"

    step "join" "查看已注册集群与状态"
    kubectl --context karmada-apiserver get clusters
}

# OrbStack/Docker 重启后容器 IP 会变, 成员端点会失效 -> READY=False。
# 本步骤自动探测成员 control-plane 容器的当前 IP 并回写 Cluster.apiEndpoint。
do_endpoints() {
    step "endpoints" "自动修正成员集群端点 (应对容器 IP 变化)"
    for cluster in member-us member-ap; do
        local cid="${cluster}-control-plane" ip
        ip="$(docker inspect "$cid" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || true)"
        if [ -z "$ip" ]; then
            echo "  [warn] 探测不到容器 $cid (集群是否已创建?)" >&2
            continue
        fi
        kubectl --context karmada-apiserver patch cluster "$cluster" --type merge \
            -p "{\"spec\":{\"apiEndpoint\":\"https://${ip}:6443\"}}" >/dev/null
        echo "  ${cluster} -> https://${ip}:6443"
    done
    echo "  等 15s 让状态控制器刷新..."
    sleep 15
    kubectl --context karmada-apiserver get clusters
}

do_apply() {
    step "apply" "提交应用 + 分发策略 (只提交一次)"
    kubectl --context karmada-apiserver create ns federation-demo \
        --dry-run=client -o yaml | kubectl --context karmada-apiserver apply -f -
    kubectl --context karmada-apiserver apply -f manifests/karmada.yaml

    step "apply" "ResourceBinding 展示调度结果 (us=4, ap=2)"
    kubectl --context karmada-apiserver get resourcebinding \
        -n federation-demo -o wide

    step "apply" "分别到两个成员集群验证实际副本"
    member_kubectl member-us -n federation-demo get deploy geo-app
    member_kubectl member-ap -n federation-demo get deploy geo-app
}

do_scale() {
    step "scale" "总副本 6 -> 12, 权重不变则按比例自动再平衡"
    kubectl --context karmada-apiserver -n federation-demo \
        patch deploy geo-app --type=json \
        -p='[{"op":"replace","path":"/spec/replicas","value":12}]'
}

do_failover() {
    step "failover" "模拟 member-ap 失联 -> 60s 后份额迁移"
    # 真实模拟: 直接停掉 member-ap 的 kind 控制面容器。
    # (只改本地 kubeconfig 的 current-context 对 Karmada 控制面毫无影响 ——
    #  它访问成员集群用的是注册时保存的凭据, 与本机配置无关)
    AP_NODE="member-ap-control-plane"
    echo "  停止成员集群节点容器: docker stop ${AP_NODE}"
    docker stop "$AP_NODE"
    echo "  member-ap 已失联; tolerationSeconds=60, 观察下面 ResourceBinding 的变化"
    echo "  (gracefulEvctionTasks 出现 -> ap 的份额被迁往 member-us)"
    kubectl --context karmada-apiserver get resourcebinding \
        -n federation-demo -w &
    W=$!; sleep 90; kill $W 2>/dev/null || true
    echo "  恢复成员集群: docker start ${AP_NODE}"
    docker start "$AP_NODE"
    echo "  member-ap 回来后, 下个调度周期会按 4:2 权重重新平衡副本"
}

case "${1:-all}" in
    install) do_install ;; join) do_join ;; endpoints) do_endpoints ;;
    apply)   do_apply  ;; scale) do_scale  ;; failover) do_failover ;;
    all)     do_install; do_join; do_endpoints; do_apply ;;
esac
