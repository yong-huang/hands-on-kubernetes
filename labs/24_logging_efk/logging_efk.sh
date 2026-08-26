#!/usr/bin/env bash
# =============================================================================
# EFK 日志链路演示: deploy -> flow(验证日志进ES) -> search(Kibana查询) -> clean
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

step() { echo; echo "=====> [$1] $2"; }

do_deploy() {
    step "deploy" "创建命名空间并部署 EFK 全家桶"
    kubectl create ns logging-demo --dry-run=client -o yaml | kubectl apply -f -
    kubectl create ns logging --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f manifests/logging_efk.yaml

    step "deploy" "等待 Elasticsearch 就绪(首次较慢)"
    kubectl -n logging rollout status statefulset/elasticsearch --timeout=300s
}

do_flow() {
    step "flow" "验证数据流: 生成器 -> Fluent Bit -> ES 索引"
    sleep 30                                   # 等 Flush 周期
    kubectl -n logging run curl --rm -it --restart=Never \
        --image=curlimages/curl:8.5.0 --silent --rm -i -- \
        -s "http://elasticsearch.logging.svc:9200/_cat/indices/k8s-logs-*?v" || true
    echo "  ^ 出现 k8s-logs-YYYY.MM.DD 索引即代表链路通"
}

do_search() {
    step "search" "直接查 ES: 最近 5 条 ERROR 日志"
    kubectl -n logging run curlq --rm -q --restart=Never \
        --image=curlimages/curl:8.5.0 -- \
        -s "http://elasticsearch.logging.svc:9200/k8s-logs-*/_search?q=log.level:ERROR&size=5&pretty" >/dev/null 2>&1 || \
    echo "  或在 Kibana Discover 里输入: log.level:ERROR AND kubernetes.namespace_name:\"logging-demo\""

    step "search" "打开 Kibana UI"
    kubectl -n logging port-forward deploy/kibana 5601:5601 &
    PF=$!; sleep 2
    echo "  浏览器 http://localhost:5601 -> Discover -> 创建 data view: k8s-logs-*"
    kill $PF 2>/dev/null || true
}

do_clean() { kubectl delete ns logging-demo logging --ignore-not-found; }

case "${1:-all}" in
    deploy) do_deploy ;; flow) do_flow ;; search) do_search ;;
    clean)  do_clean  ;;
    all)    do_deploy; do_flow ;;
esac
