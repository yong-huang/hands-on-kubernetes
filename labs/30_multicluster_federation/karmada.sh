#!/usr/bin/env bash
# =============================================================================
# Karmada 全流程: install(host集群) -> join(注册两个成员) -> apply(分发)
#                 -> scale(改总副本看再平衡) -> failover(拔线演练) -> clean
# 本地实验可用 karmadactl + 两个 kind 集群模拟
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效
step() { echo; echo "=====> [$1] $2"; }

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

do_apply() {
    step "apply" "提交应用 + 分发策略 (只提交一次)"
    kubectl --context karmada-apiserver create ns federation-demo \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl --context karmada-apiserver apply -f manifests/karmada.yaml

    step "apply" "ResourceBinding 展示调度结果 (us=4, ap=2)"
    kubectl --context karmada-apiserver get resourcebinding \
        -n federation-demo -o wide

    step "apply" "分别到两个成员集群验证实际副本"
    kubectl --context member-us -n federation-demo get deploy geo-app
    kubectl --context member-ap -n federation-demo get deploy geo-app
}

do_scale() {
    step "scale" "总副本 6 -> 12, 权重不变则按比例自动再平衡"
    kubectl --context karmada-apiserver -n federation-demo \
        patch deploy geo-app --type=json \
        -p='[{"op":"replace","path":"/spec/replicas","value":12}]'
}

do_failover() {
    step "failover" "模拟 member-ap 失联 -> 60s 后份额迁移"
    kubectl --context member-ap config unset current-context || true
    echo "  (实验中可 cordon/停掉 kind 节点模拟; 观察 ResourceBinding 变化)"
    kubectl --context karmada-apiserver get resourcebinding \
        -n federation-demo -w &
    W=$!; sleep 90; kill $W 2>/dev/null || true
}

case "${1:-all}" in
    install) do_install ;; join) do_join ;; apply) do_apply ;;
    scale)   do_scale   ;; failover) do_failover ;;
    all)     do_install; do_join; do_apply ;;
esac
