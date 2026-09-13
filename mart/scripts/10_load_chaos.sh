#!/usr/bin/env bash
# 项目 10：全链路压测 + 混沌实验 —— 基线压测 / 混沌注入 / 报告生成
# 用法: ./10_load_chaos.sh [prepare|baseline|chaos|report|all]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
REPORT="docs/load-test-report.md"

step() { echo; echo "=====> [$1] $2"; }

prepare_stock() {  # 压测前把 p1 库存放大，避免 409 干扰错误率
    kubectl -n "$NS" exec postgres-0 -- psql -U inv_user -d invdb -c \
        "UPDATE stock SET available=1000000 WHERE product_id='p1'" >/dev/null
    echo "  p1 stock -> 1000000"
}

run_k6_job() {  # $1=RATE $2=DURATION $3=job 名后缀
    local rate="$1" dur="$2" suffix="$3"
    kubectl -n "$NS" delete job "k6-load-$suffix" --ignore-not-found >/dev/null 2>&1
    kubectl -n "$NS" create configmap k6-script --from-file=tests/load/checkout_flow.js --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-load-$suffix
  namespace: $NS
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: k6
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: mart/k6:0.51.0
          env:
            - {name: RATE, value: "$rate"}
            - {name: DURATION, value: "$dur"}
          args: ["run", "/script/checkout_flow.js"]
          volumeMounts:
            - {name: script, mountPath: /script}
      volumes:
        - name: script
          configMap:
            name: k6-script
EOF
    kubectl -n "$NS" wait --for=condition=complete "job/k6-load-$suffix" --timeout=620s 2>/dev/null \
      || { echo "❌ k6 job 未成功完成"; kubectl -n "$NS" logs "job/k6-load-$suffix" --tail=20; exit 1; }
    kubectl -n "$NS" logs "job/k6-load-$suffix"
}

do_prepare() {
    step "prepare" "压测前置：库存放大 + 集群状态确认"
    prepare_stock
    kubectl -n "$NS" get pods --no-headers | awk '{print $1,$3}'
}

do_baseline() {
    step "baseline" "k6 恒压 200 rps × 5m（阈值 p99<300ms / err<0.1%）"
    run_k6_job 200 5m baseline | tee /tmp/o10-baseline.log | grep -E 'http_req_duration|http_req_failed|checks|✓|✗' | tail -8
    # 阈值写在 k6 Job 里：Job 成功完成 = 全部阈值通过（k6 任一阈值失败即非零退出）
    if kubectl -n "$NS" get job k6-load-baseline -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -q True; then
        echo "✅ 基线达标（p99<300ms 且 err<0.1%）"
    else
        echo "⚠️ 阈值未全过（结果已存 /tmp/o10-baseline.log，如实写进报告）"
    fi
}

do_chaos() {
    step "chaos" "100 rps 负载中杀 product Pod，观察错误率（<1%）"
    prepare_stock
    # 后台起 3 分钟压测
    run_k6_job 100 3m chaos > /tmp/o10-chaos.log 2>&1 &
    local k6pid=$!
    sleep 45   # 等恒压爬满
    local victim
    victim=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    echo "  杀掉 product Pod: $victim"
    kubectl -n "$NS" delete pod "$victim" >/dev/null 2>&1   # 优雅杀：走 SIGTERM+preStop+摘流，模拟真实单副本故障
    wait "$k6pid" || true
    grep -E 'http_req_duration|http_req_failed|checks' /tmp/o10-chaos.log | tail -4
    if kubectl -n "$NS" get job k6-load-chaos -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -q True; then
        echo "✅ 混沌验收通过：错误率 <0.1%（远优于 1% 目标），服务自愈无感"
    else
        echo "⚠️ 混沌期间错误率超阈值（详见报告）"
    fi
}

do_report() {
    step "report" "生成 docs/load-test-report.md"
    mkdir -p docs
    {
        echo "# mini-mart 全链路压测与混沌实验报告"
        echo
        echo "- 日期：$(date '+%Y-%m-%d %H:%M')"
        echo "- 环境：本机 kind 单节点（OrbStack VM，与宿主机共享 CPU）"
        echo "- 链路：GET /products/p1 + POST /orders（gRPC 查价 -> Saga 跨库 -> Kafka 事件）"
        echo
        echo "## SLO 表"
        echo
        echo "| 指标 | SLO | 基线(200rps×5m) | 混沌(100rps×3m, 杀 product) |"
        echo "|:---|:---|:---|:---|"
        local base99 baseerr chaos99 chaoserr
        base99=$(grep -oE "p\(99\)=.*" /tmp/o10-baseline.log 2>/dev/null | head -1 | awk '{print $2}')
        chaos99=$(grep -oE "p\(99\)=.*" /tmp/o10-chaos.log 2>/dev/null | head -1 | awk '{print $2}')
        baseerr=$(grep -A1 'http_req_failed' /tmp/o10-baseline.log 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1)
        chaoserr=$(grep -A1 'http_req_failed' /tmp/o10-chaos.log 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1)
        echo "| p99 延迟 | <300ms | ${base99:-见日志} | ${chaos99:-见日志} |"
        echo "| 错误率 | <0.1% 基线 / <1% 混沌 | ${baseerr:-见日志} | ${chaoserr:-见日志} |"
        echo
        echo "## 基线摘要"
        echo '```'
        grep -E 'http_req_duration|http_req_failed|checks|scenarios' /tmp/o10-baseline.log 2>/dev/null | head -8
        echo '```'
        echo
        echo "## 混沌实验摘要（Chaos: kill product 单副本）"
        echo '```'
        grep -E 'http_req_duration|http_req_failed|checks|scenarios' /tmp/o10-chaos.log 2>/dev/null | head -8
        echo '```'
        echo
        echo "## 瓶颈分析与结论"
        echo "- 基线/混沌原始日志见 /tmp/o10-baseline.log、/tmp/o10-chaos.log（脚本运行时）"
        echo "- 单节点 kind 与宿主机共享 CPU，绝对数值仅供相对比较；SLO 语义在生产应按容量规划重定"
    } > "$REPORT"
    echo "  报告已写入 $REPORT"
}

main() {
    local target="${1:-all}"
    case "$target" in
        prepare) do_prepare ;;
        baseline) do_baseline ;;
        chaos) do_chaos ;;
        report) do_report ;;
        all) do_prepare; do_baseline; do_chaos; do_report ;;
        *) echo "可用: prepare|baseline|chaos|report|all" >&2; exit 1 ;;
    esac
}
main "$@"
