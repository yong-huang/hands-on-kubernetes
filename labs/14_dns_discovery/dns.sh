#!/usr/bin/env bash
# =============================================================================
# Kubernetes DNS 与服务发现演示脚本
# 覆盖: ClusterIP 解析 / Headless 解析 / Pod 级 DNS / 短名与 FQDN / DNS 服务器自身
# 用法: ./dns.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 test)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"              # 演示用的 namespace
TEST_POD="dns-test"              # 发起 nslookup 的 busybox 测试 Pod
MANIFEST="manifests/dns_discovery.yaml"    # 本目录下的多文档 YAML

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# 在测试 Pod 里执行命令; busybox nslookup 查不到部分搜索域时 exit 1 属正常
# (答案已打印), 不能让 set -e 中断脚本
dns_exec() { kubectl exec -n "${NAMESPACE}" "${TEST_POD}" -- "$@" || true; }

# ----------------------------- 1. 部署 -----------------------------
do_deploy() {
    step "deploy" "应用 YAML (Headless Service + StatefulSet + ClusterIP Service + 自定义 DNS Pod)"
    kubectl apply -f "${MANIFEST}"

    step "deploy" "等待 StatefulSet (web, replicas=2) 有序就绪"
    kubectl rollout status "statefulset/web" -n "${NAMESPACE}"

    step "deploy" "创建 busybox 测试 Pod (DNS 查询客户端)"
    # 幂等: 上次运行的测试 Pod 可能还在, 删干净再建 (等待删除完成, 避免撞上 Terminating)
    if kubectl get pod "${TEST_POD}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl delete pod "${TEST_POD}" -n "${NAMESPACE}" --wait=true >/dev/null
    fi
    kubectl run "${TEST_POD}" -n "${NAMESPACE}" \
        --image=busybox:1.36 --restart=Never -- sh -c 'sleep 3600'
    kubectl wait --for=condition=Ready "pod/${TEST_POD}" \
        -n "${NAMESPACE}" --timeout=60s

    step "deploy" "查看 Pod IP, 稍后与 DNS 解析结果对照"
    kubectl get pods -n "${NAMESPACE}" -o wide
}

# ----------------------------- 2. DNS 测试 -----------------------------
do_test() {
    step "test" "a) 普通 ClusterIP Service: nslookup web -> 只返回一个 VIP"
    dns_exec nslookup web

    step "test" "b) Headless Service: nslookup web-h -> 返回所有 Pod IP (无 VIP)"
    dns_exec nslookup web-h

    step "test" "c) Pod 级 DNS: nslookup web-0.web-h -> 只返回 web-0 的 IP"
    dns_exec nslookup web-0.web-h
    dns_exec nslookup web-1.web-h

    step "test" "d) 短名 vs FQDN: 观察 search 域逐级展开"
    echo "--- d1) web (最短, 依赖 search 域补全) ---"
    dns_exec nslookup web
    echo "--- d2) web.default ---"
    dns_exec nslookup web.default
    echo "--- d3) web.default.svc ---"
    dns_exec nslookup web.default.svc
    echo "--- d4) web.default.svc.cluster.local (完整 FQDN, 结尾点表示绝对域名) ---"
    dns_exec nslookup web.default.svc.cluster.local.

    step "test" "e) 解析 DNS 服务本身 (kube-dns 即 CoreDNS 的 Service 名)"
    dns_exec nslookup kube-dns.kube-system.svc.cluster.local

    step "test" "附加) 查看 dns-custom Pod 注入的 resolv.conf (dnsConfig 效果)"
    kubectl exec -n "${NAMESPACE}" dns-custom -- cat /etc/resolv.conf
}

# ----------------------------- 3. 清理 -----------------------------
do_clean() {
    step "clean" "删除本演示创建的所有资源"
    kubectl delete -f "${MANIFEST}" --wait=true
    kubectl delete pod "${TEST_POD}" -n "${NAMESPACE}" --wait=true || true
    kubectl get svc,statefulset,pods -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        deploy) do_deploy ;;
        test)   do_test ;;
        clean)  do_clean ;;
        all)    do_deploy; do_test; do_clean ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: deploy | test | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
