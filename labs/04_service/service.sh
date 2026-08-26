#!/usr/bin/env bash
# =====================================================================
# 04_service 演示脚本：Service 四种类型的部署、访问与验证
# 用法: ./service.sh [deploy|test|clean|all]   （默认 all）
# =====================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ---------- 工具函数 ----------
LINE="------------------------------------------------------------"
info()  { echo -e "\e[32m[INFO]\e[0m $*"; }         # 绿色提示
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }         # 黄色警告
step()  { echo -e "\n\e[36m==>\e[0m $*"; }

# ---------- 部署：Deployment + 4 种 Service ----------
deploy() {
    step "应用 Deployment + Service（service.yaml）"
    kubectl apply -f manifests/service.yaml

    step "等待 Deployment 的 3 个 Pod 就绪"
    kubectl rollout status deployment/nginx-deploy --timeout=60s

    step "查看 Service 列表（注意 TYPE / CLUSTER-IP / PORT(S) 列）"
    kubectl get svc
    # 预期：
    #   nginx-clusterip     ClusterIP   10.96.x.x    80/TCP
    #   nginx-nodeport      NodePort    10.96.x.x    80:30080/TCP
    #   nginx-loadbalancer  LoadBalancer 10.96.x.x   80:31xxx/TCP (EXTERNAL-IP <pending> 本地环境)
    #   nginx-headless      ClusterIP   None         80/TCP  ← 无 VIP！
}

# ---------- 测试：访问 / 服务发现 / Endpoints ----------
test_access() {
    step "1) ClusterIP 访问：启动一个临时 curl Pod 从集群内部访问"
    kubectl run curl-test --rm -it --restart=Never \
        --image=curlimages/curl:8.8.0 --command -- \
        curl -s -o /dev/null -w "HTTP %{http_code}\n" http://nginx-clusterip/ || true

    step "2) NodePort 访问：通过节点 IP:30080（需要本地集群，minikube/kind）"
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    if [[ -n "${NODE_IP}" ]]; then
        curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/" || warn "节点 IP 不可达（可能是 kind/docker 网络）"
    else
        warn "拿不到节点 InternalIP，可用 kubectl port-forward svc/nginx-nodeport 8080:80 自行验证"
    fi

    step "3) DNS 服务发现：从 Pod 内 nslookup Service 名"
    # ClusterIP Service → 返回 VIP；Headless Service → 直接返回 3 个 Pod IP
    kubectl run dns-test --rm -it --restart=Never \
        --image=busybox:1.36 --command -- \
        sh -c 'echo "--- nginx-clusterip (VIP) ---"; nslookup nginx-clusterip;
               echo "--- nginx-headless (Pod IPs) ---"; nslookup nginx-headless' || true

    step "4) Endpoints 检查：Service 背后到底挂了哪些 Pod"
    kubectl get endpoints nginx-clusterip nginx-headless
    # 每个 Ready 的 Pod IP:targetPort 都会出现在列表里
    kubectl describe endpoints nginx-clusterip | tail -5
}

# ---------- 清理 ----------
clean() {
    step "删除本例创建的所有资源"
    kubectl delete -f manifests/service.yaml --ignore-not-found=true
    info "清理完成"
}

# ---------- 主入口 ----------
main() {
    echo "$LINE"
    echo " Kubernetes 04_service 演示"
    echo "$LINE"
    local action="${1:-all}"
    case "$action" in
        deploy) deploy ;;
        test)   test_access ;;
        clean)  clean ;;
        all)    deploy; test_access; clean ;;
        *)      echo "用法: $0 [deploy|test|clean|all]"; exit 1 ;;
    esac
    echo "$LINE"
    info "完成"
}

main "$@"
