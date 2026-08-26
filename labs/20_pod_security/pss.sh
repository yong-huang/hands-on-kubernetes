#!/usr/bin/env bash
# =============================================================================
# Pod Security Admission (PSA) 演示脚本
# 覆盖: 三等级 namespace 创建 -> 违规/合规 Pod 测试矩阵 -> warn 软模式 -> 清理
# 用法: ./pss.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 test)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
YAML="manifests/pod_security.yaml"          # 多文档 YAML: 3 个 ns + 4 个测试 Pod
NS_PRIV="psa-privileged"          # enforce: privileged
NS_BASE="psa-baseline"            # enforce: baseline
NS_RESTR="psa-restricted"         # enforce+audit+warn: restricted

step() { echo; echo "=====> [$1] $2"; }

# 从多文档 YAML 里按 metadata.name 抽取一个 Pod, 并替换 namespace
# 用法: extract_pod <pod名> <目标ns>  (输出到 stdout)
extract_pod() {
    awk -v pod="$1" 'BEGIN{RS="---"} $0 ~ ("\n  name: " pod "\n")' "${YAML}" \
        | sed "/^  namespace:/s|.*|  namespace: $2|"
}

# 抽取后 apply; 返回 0=通过 1=被拒
apply_pod() {
    extract_pod "$1" "$2" | kubectl apply -f - >/dev/null 2>&1
}

# 期望被拒绝的场景: 打印 Forbidden 的具体原因 (PSA 拒绝信息在 stderr)
expect_reject() {
    local pod="$1" ns="$2"
    step "test" "${pod} -> ${ns} (预期: 被 enforce 拒绝)"
    local err
    err=$(extract_pod "${pod}" "${ns}" | kubectl apply -f - 2>&1 >/dev/null) || true
    if echo "${err}" | grep -q "Forbidden"; then
        echo "[OK] 被拒绝, API Server 返回:"
        echo "${err}" | sed 's/^/    /'
    else
        echo "[FAIL] 竟然通过了! 输出:" && echo "${err}" | sed 's/^/    /'
    fi
}

# 期望通过的场景
expect_pass() {
    local pod="$1" ns="$2"
    step "test" "${pod} -> ${ns} (预期: 通过)"
    if apply_pod "${pod}" "${ns}"; then
        echo "[OK] 创建成功: $(kubectl get pod "${pod}" -n "${ns}" \
            --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status.phase)"
    else
        echo "[FAIL] 创建失败" >&2
    fi
}

# ----------------------------- 1. deploy: 建 ns + 打标签 -----------------------------
do_deploy() {
    step "deploy" "创建三个 namespace 并打 PSA 等级标签"
    # 只 apply YAML 里的 Namespace 文档 (按文档抽取, 记录间补 --- 分隔符)
    awk 'BEGIN{RS="---"; ORS="---\n"} $0 ~ /kind: Namespace/ {print}' "${YAML}" \
        | kubectl apply -f -

    step "deploy" "确认 namespace 标签 (enforce / audit / warn)"
    kubectl get ns "${NS_PRIV}" "${NS_BASE}" "${NS_RESTR}" \
        -o custom-columns='NS:.metadata.name,ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce,AUDIT:.metadata.labels.pod-security\.kubernetes\.io/audit,WARN:.metadata.labels.pod-security\.kubernetes\.io/warn'
}

# ----------------------------- 2. test: 测试矩阵 -----------------------------
do_test() {
    expect_pass pod-privileged "${NS_PRIV}"     # 特权 Pod 在 privileged ns 放行
    expect_reject pod-privileged "${NS_BASE}"   # 同一 Pod 在 baseline ns 被拒
    expect_reject pod-hostpath "${NS_BASE}"     # hostPath/hostNetwork 违反 baseline
    expect_reject pod-root "${NS_RESTR}"        # root Pod 违反 restricted
    expect_pass pod-compliant "${NS_RESTR}"     # 合规 Pod 在 restricted ns 放行

    step "test" "warn 软模式演示: root Pod 在 psa-baseline (warn 未启用, 静默通过)"
    apply_pod pod-root "${NS_BASE}" || true
    echo "(baseline 只 enforce 自己的等级, root 合规, 无警告)"

    step "test" "audit/warn 已在 ${NS_RESTR} 上配置: 再投一次 root Pod 观察 stderr 警告"
    extract_pod pod-root "${NS_RESTR}" \
        | kubectl apply -f - 2>&1 | sed 's/^/    /' || true
    echo "(enforce=restricted 时 warn 与拒绝信息同时出现; 若只有 warn=restricted,"
    echo " 则同样的提示会打印但 Pod 照常创建 —— 这就是灰度观察手段)"
}

# ----------------------------- 3. clean -----------------------------
do_clean() {
    step "clean" "删除三个演示 namespace (Pod 随 ns 一起消失)"
    kubectl delete ns "${NS_PRIV}" "${NS_BASE}" "${NS_RESTR}" \
        --ignore-not-found --wait=true
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
