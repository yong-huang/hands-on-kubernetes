#!/usr/bin/env bash
# mini-mart 全量回归：按顺序跑 10 个项目的全部验收，输出汇总表
# 用法: ./scripts/regression.sh
set -uo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

SUMMARY=/tmp/mart-regression.txt
: > "$SUMMARY"

note() { echo "[$1] $2" | tee -a "$SUMMARY"; }

run_case() {  # $1=项目 $2=用例名 $3=命令...
    local proj="$1" case_name="$2"; shift 2
    echo "---- [$proj] $case_name" >&2
    if "$@" >/tmp/mart-regression-last.log 2>&1; then
        note "PASS" "$proj / $case_name"
    else
        note "FAIL" "$proj / $case_name （日志: /tmp/mart-regression-last.log）"
    fi
}

S=scripts

# 项目 1：滚动验收会把 product 拨到 0.1/0.2，结束后恢复 0.3.0 再测后续项目
run_case 01 "滚动更新零中断"   bash $S/01_product_k8s.sh verify-rolling
run_case 01 "坏探针自动中止"   bash $S/01_product_k8s.sh verify-readiness
kubectl -n mart apply -f deploy/product/manifests.yaml >/dev/null 2>&1
kubectl -n mart rollout status deployment/product --timeout=180s >/dev/null 2>&1 || note "FAIL" "01/product 恢复 0.3.0"

run_case 02 "gRPC 实时查价"     bash $S/02_order_grpc.sh verify-price
run_case 02 "超时快速失败"      bash $S/02_order_grpc.sh verify-timeout
run_case 03 "配置热加载"        bash $S/03_config_hotreload.sh verify-config
run_case 03 "Secret 轮换"       bash $S/03_config_hotreload.sh verify-secret
run_case 04 "熔断状态机"        bash $S/04_resilience.sh verify-breaker
run_case 05 "事件送达"          bash $S/05_kafka_events.sh verify-delivery
run_case 05 "重试进 DLQ"        bash $S/05_kafka_events.sh verify-dlq
run_case 05 "幂等去重"          bash $S/05_kafka_events.sh verify-idempotent
run_case 06 "跨库一致"          bash $S/06_saga_db.sh verify-consistency
run_case 06 "库存不足补偿"      bash $S/06_saga_db.sh verify-insufficient
run_case 06 "杀Pod收敛"         bash $S/06_saga_db.sh verify-kill
run_case 07 "Jaeger 全链路"     bash $S/07_otel_tracing.sh verify-jaeger
run_case 07 "Prometheus 指标"   bash $S/07_otel_tracing.sh verify-prometheus
run_case 07 "Grafana 看板"      bash $S/07_otel_tracing.sh verify-grafana
run_case 08 "JWT 认证"          bash $S/08_gateway.sh verify-auth
run_case 08 "限流"              bash $S/08_gateway.sh verify-ratelimit
run_case 08 "灰度"              bash $S/08_gateway.sh verify-canary
run_case 09 "ArgoCD 同步"       bash $S/09_cicd.sh verify-sync
run_case 09 "定向交付"          bash $S/09_cicd.sh verify-deliver
run_case 09 "revert 回滚"       bash $S/09_cicd.sh verify-revert
run_case 10 "基线压测 200rps"   bash $S/10_load_chaos.sh baseline
run_case 10 "混沌杀Pod"         bash $S/10_load_chaos.sh chaos
run_case 10 "报告生成"          bash $S/10_load_chaos.sh report

echo; echo "========== 回归汇总 =========="
pass=$(grep -c '^PASS' "$SUMMARY"); fail=$(grep -c '^FAIL' "$SUMMARY")
cat "$SUMMARY"
echo "--------------------------------"
echo "PASS=$pass FAIL=$fail"
