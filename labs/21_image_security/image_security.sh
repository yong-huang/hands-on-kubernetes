#!/usr/bin/env bash
# =============================================================================
# 镜像安全与漏洞扫描全流程演示
# 覆盖: install(装 Trivy Operator + Kyverno) -> scan(自动扫描出报告)
#       -> deny(准入策略拦截) -> sign(cosign 签名与校验) -> clean
# 用法: ./image_security.sh [step]   不带参数依次执行全部步骤
# 依赖: kind/k3s 等本地集群, helm, (可选 cosign)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

NS="imgsec-demo"
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装组件 -----------------------------
do_install() {
    step "install" "安装 trivy-operator (漏洞扫描器)"
    helm repo add aqua https://aquasecurity.github.io/helm-charts >/dev/null 2>&1 || true
    helm upgrade --install trivy-operator aqua/trivy-operator \
        --namespace trivy-system --create-namespace \
        --set trivy.ignoreUnfixed=true          # 只报有修复版本的 CVE

    step "install" "安装 kyverno (策略引擎)"
    helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
    helm upgrade --install kyverno kyverno/kyverno \
        -n kyverno --create-namespace --wait

    kubectl apply -f manifests/image_security.yaml
}

# ----------------------------- 2. 自动漏洞扫描 -----------------------------
do_scan() {
    step "scan" "等待 vulnerable-app 就绪, 触发 Trivy 扫描"
    kubectl -n "$NS" rollout status deploy/vulnerable-app --timeout=90s

    step "scan" "查看 VulnerabilityReport 汇总 (jq 提取 severity 计数)"
    kubectl -n "$NS" get vulnerabilityreport \
        -l trivy-operator.resource.kind=Deployment -o name | head -1 | xargs -I{} \
        kubectl -n "$NS" get {} -o jsonpath='{.report.summary}' | python3 -m json.tool

    step "scan" "列出 HIGH 及以上的 CVE (前 5 条)"
    kubectl -n "$NS" get vulnerabilityreport -o json \
      | jq -r '.items[].report.vulnerabilities[]?
               | select(.severity=="HIGH" or .severity=="CRITICAL")
               | "\(.vulnerabilityID)\t\(.severity)\t\(.title)"' | head -5
}

# ----------------------------- 3. 准入拦截 -----------------------------
do_deny() {
    step "deny" "尝试部署带 Critical 漏洞的 nginx:1.14.x -> 应被 Kyverno 拒绝"
    if kubectl -n "$NS" run bad-pod --image=nginx:1.14.2 --restart=Never 2>/tmp/deny.err; then
        echo "!! 预期被拒绝, 但成功了 —— 检查 ClusterPolicy 是否 Enforce"; kubectl -n "$NS" delete pod bad-pod --force --grace-period=0 2>/dev/null || true
    else
        echo "已拦截:"; sed 's/^/    /' /tmp/deny.err
    fi
}

# ----------------------------- 4. 签名与验签 -----------------------------
do_sign() {
    step "sign" "(可选) cosign 签名示例 —— 需先 export COSIGN_KEY/REGISTRY 凭证"
    command -v cosign >/dev/null || { echo "未安装 cosign, 跳过 (brew install cosign)"; return 0; }
    echo "  cosign sign --key cosign.key registry.example.com/app:v1"
    echo "  集群侧由 verify-image-signatures 策略在准入时自动 verify"
}

# ----------------------------- 清理 -----------------------------
do_clean() {
    step "clean" "删除演示资源"
    kubectl delete ns "$NS" --ignore-not-found
}

case "${1:-all}" in
    install) do_install ;; scan) do_scan ;; deny) do_deny ;;
    sign)    do_sign    ;; clean) do_clean ;;
    all)     do_install; do_scan; do_deny; do_sign ;;
esac
