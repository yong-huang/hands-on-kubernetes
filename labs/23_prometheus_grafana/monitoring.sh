#!/usr/bin/env bash
# =============================================================================
# 监控栈部署与验证: install -> verify -> query -> alert -> clean
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

step() { echo; echo "=====> [$1] $2"; }

do_install() {
    step "install" "helm 安装 kube-prometheus-stack (含 Prometheus Operator/CRA/Grafana)"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        -n monitoring --create-namespace \
        --set grafana.adminPassword=admin \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false --wait

    step "install" "部署示例应用 + ServiceMonitor + 告警规则"
    kubectl create ns monitoring-demo --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f manifests/monitoring.yaml
}

do_verify() {
    step "verify" "组件就绪检查"
    kubectl -n monitoring get pods | grep -E 'prometheus|grafana|operator'
}

do_query() {
    step "query" "port-forward Prometheus 并查询 demo 指标"
    kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 &
    PF=$!; sleep 2
    echo "  浏览器打开 http://localhost:9090"
    echo "  查询: demo_requests_total   /   up"
    kill $PF 2>/dev/null || true

    step "query" "port-forward Grafana (admin/admin)"
    kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80 &
    GP=$!; sleep 2
    echo "  浏览器打开 http://localhost:3000 -> Dashboards 导入 1860 (Node Exporter Full)"
    kill $GP 2>/dev/null || true
}

do_alert() {
    step "alert" "查看已加载的告警/录制规则"
    kubectl -n monitoring-demo get prometheusrule metrics-demo-alerts -o yaml | grep -A3 'alert:\|record:' | head -12
    echo "  触发路径: PrometheusRule -> Operator 加载 -> Prometheus eval -> Alertmanager 路由"
}

do_clean() { kubectl delete ns monitoring-demo --ignore-not-found; }

case "${1:-all}" in
    install) do_install ;; verify) do_verify ;; query) do_query ;;
    alert)   do_alert   ;; clean)  do_clean ;;
    all)     do_install; do_verify ;;
esac
