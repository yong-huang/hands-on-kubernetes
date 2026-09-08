#!/usr/bin/env bash
# =====================================================================
# 04_service 演示脚本：Service 四种类型的部署、访问与验证
# 用法: ./service.sh [deploy|test|clean|all]   （默认 all）
# 兼容 sh 调用: 颜色输出用 printf, 不用 bash 专属的 echo -e
# =====================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ---------- 工具函数 ----------
LINE="------------------------------------------------------------"
info()  { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }   # 绿色提示
warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }   # 黄色警告
step()  { printf '\n\033[36m==>\033[0m %s\n' "$*"; }

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
    # 交互式等价写法: kubectl run curl-test --rm -it --image=curlimages/curl:8.8.0 -- curl ...
    # 脚本里用 run -> 等待跑完 -> logs -> delete: 等 phase=Succeeded 再取日志, 输出不会丢
    kubectl delete pod curl-test --ignore-not-found=true >/dev/null
    kubectl run curl-test --restart=Never \
        --image=curlimages/curl:8.8.0 --command -- \
        curl -s -o /dev/null -w "HTTP %{http_code}\n" http://nginx-clusterip/ >/dev/null || true
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/curl-test --timeout=60s >/dev/null 2>&1 || true
    kubectl logs curl-test 2>/dev/null || true
    kubectl delete pod curl-test --ignore-not-found=true >/dev/null

    step "2) NodePort 访问：通过节点 IP:30080（需要本地集群，minikube/kind）"
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    if [ -n "${NODE_IP}" ]; then
        curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/" || warn "节点 IP 不可达（可能是 kind/docker 网络）"
    else
        warn "拿不到节点 InternalIP，可用 kubectl port-forward svc/nginx-nodeport 8080:80 自行验证"
    fi

    step "3) DNS 服务发现：从 Pod 内 nslookup Service 名"
    # ClusterIP Service → 返回 VIP；Headless Service → 直接返回 3 个 Pod IP
    # 注意: 查得太早会拿到 NXDOMAIN, 且被 CoreDNS 负缓存约 30s (cache 30),
    # 所以重试预算要盖过负缓存 TTL, 否则整个 Service 生命周期内都查不到
    # nslookup 输出中的 NXDOMAIN 行是 busybox 逐个试 search 后缀的正常现象, 看最后的 Name/Address 即可
    kubectl delete pod dns-test --ignore-not-found=true >/dev/null
    kubectl run dns-test --restart=Never \
        --image=busybox:1.36 --command -- \
        sh -c 'i=1; until nslookup nginx-clusterip >/dev/null 2>&1; do
                   [ "$i" -ge 21 ] && break
                   [ $((i % 5)) -eq 0 ] && echo "(DNS 尚未生效, 已等 $((i * 2))s, 继续重试...)"
                   i=$((i+1)); sleep 2
               done
               echo "--- nginx-clusterip (VIP) ---";    nslookup nginx-clusterip
               echo "--- nginx-headless (Pod IPs) ---"; nslookup nginx-headless' || true
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-test --timeout=60s >/dev/null 2>&1 || true
    kubectl logs dns-test 2>/dev/null || true
    kubectl delete pod dns-test --ignore-not-found=true >/dev/null

    step "4) Endpoints 检查：Service 背后到底挂了哪些 Pod"
    kubectl get endpoints nginx-clusterip nginx-headless 2>/dev/null || true   # 旧 API: v1.33+ 废弃, 保留作概念对照
    kubectl get endpointslices -l kubernetes.io/service-name=nginx-clusterip   # 现行 API: EndpointSlice
    kubectl get endpointslices -l kubernetes.io/service-name=nginx-headless
}

# ---------- 清理 ----------
clean() {
    step "删除本例创建的所有资源"
    kubectl delete -f manifests/service.yaml --ignore-not-found=true
    kubectl delete pod curl-test dns-test --ignore-not-found=true
    info "清理完成"
}

# ---------- 主入口 ----------
main() {
    printf '%s\n' "$LINE"
    echo " Kubernetes 04_service 演示"
    printf '%s\n' "$LINE"
    local action="${1:-all}"
    case "$action" in
        deploy) deploy ;;
        test)   test_access ;;
        clean)  clean ;;
        all)    deploy; test_access; clean ;;
        *)      echo "用法: $0 [deploy|test|clean|all]"; exit 1 ;;
    esac
    printf '%s\n' "$LINE"
    info "完成"
}

main "$@"
