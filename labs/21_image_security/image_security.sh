#!/usr/bin/env bash
# =============================================================================
# 镜像安全与漏洞扫描全流程演示
# 覆盖: install(装 Trivy Operator + Kyverno) -> deploy(部署带漏洞应用, tier=app)
#       -> scan(等报告生成并汇总) -> policy(Audit 模式上策略观察, tier=policy)
#       -> deny(切 Enforce, 现场演示准入拦截) -> sign(cosign 签名与校验) -> clean
# 用法: ./image_security.sh [step]   不带参数依次执行全部步骤
# 依赖: kind/k3s 等本地集群, helm, (可选 cosign)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

NS="imgsec-demo"
POLICY="block-critical-vuln-images"
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 安装组件 -----------------------------
do_install() {
    step "install" "安装 trivy-operator (漏洞扫描器)"
    helm repo add aqua https://aquasecurity.github.io/helm-charts >/dev/null 2>&1 || true
    # 默认 DB 源 mirror.gcr.io 在国内常下载失败 (unexpected EOF)。
    # 改用 ghcr.io 上的正确仓库名 aquasecurity/trivy-db (注意不是 aquasec!)。
    # 若 ghcr.io 也不可达, 可换成你的镜像源 (如 <mirror>/aquasecurity/trivy-db)。
    helm upgrade --install trivy-operator aqua/trivy-operator \
        --namespace trivy-system --create-namespace \
        --set trivy.ignoreUnfixed=true \
        --set trivy.dbRegistry=ghcr.io \
        --set trivy.dbRepository=aquasecurity/trivy-db \
        --set trivy.javaDbRegistry=ghcr.io \
        --set trivy.javaDbRepository=aquasecurity/trivy-java-db

    step "install" "安装 kyverno (策略引擎)"
    helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
    helm upgrade --install kyverno kyverno/kyverno \
        -n kyverno --create-namespace --wait
}

# ----------------------------- 2. 部署带漏洞的应用 (tier=app) -----------------------------
do_deploy() {
    step "deploy" "部署 demo 应用 (tier=app; 此刻策略尚未安装, 应用能正常进来)"
    kubectl apply -l tier=app -f manifests/image_security.yaml
    kubectl -n "$NS" rollout status deploy/vulnerable-app --timeout=90s
}

# ----------------------------- 3. 自动漏洞扫描 -----------------------------
do_scan() {
    step "scan" "等待 trivy-operator 生成 VulnerabilityReport (首次扫描需数分钟)"
    # trivy-operator 拉起后要下载 CVE 库并逐个扫描镜像, 报告不会立刻出现;
    # 轮询最多 5 分钟, 每 15s 重试一次
    local waited=0
    until kubectl -n "$NS" get vulnerabilityreport \
            -l trivy-operator.resource.kind=Deployment -o name \
            | grep -q .; do
        if [[ ${waited} -ge 300 ]]; then
            echo "!! 5 分钟内未见报告; 排查:" >&2
            echo "  kubectl -n trivy-system get pods" >&2
            echo "  kubectl -n trivy-system logs deploy/trivy-operator" >&2
            return 1
        fi
        echo "  尚无报告 (${waited}s / 300s), 15s 后重试..."
        sleep 15; waited=$((waited + 15))
    done

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

# ----------------------------- 4. 上策略: 先 Audit 观察 -----------------------------
do_policy() {
    step "policy" "安装 Kyverno 策略 (tier=policy, Audit 模式: 只记违规不拦截)"
    kubectl apply -l tier=policy -f manifests/image_security.yaml
    kubectl get clusterpolicy "${POLICY}" \
        -o jsonpath='{.metadata.name}: validationFailureAction={.spec.validationFailureAction}'; echo
    echo "(Audit 模式下违规请求只产生 PolicyReport 记录, 不会拒绝 —— "
    echo " 生产灰度路径: Audit 收集违规面 -> 确认豁免清单 -> 切 Enforce)"
}

# ----------------------------- 5. 切 Enforce, 现场演示拦截 -----------------------------
do_deny() {
    step "deny" "把策略切到 Enforce (违规直接拒绝)"
    kubectl patch clusterpolicy "${POLICY}" \
        --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
    kubectl get clusterpolicy "${POLICY}" \
        -o jsonpath='现在 validationFailureAction={.spec.validationFailureAction}'; echo

    step "deny" "尝试部署带高危漏洞的 nginx:1.14.x -> 应被 Kyverno 拒绝"
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
    install) do_install ;;
    deploy)  do_deploy  ;;
    scan)    do_scan    ;;
    policy)  do_policy  ;;
    deny)    do_deny    ;;
    sign)    do_sign    ;;
    clean)   do_clean   ;;
    all)     do_install; do_deploy; do_scan; do_policy; do_deny; do_sign ;;
esac
