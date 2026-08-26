#!/usr/bin/env bash
# =============================================================================
# Helm Chart 开发全流程: lint(静态检查) -> template(本地渲染) -> install(部署)
#                       -> upgrade(改值升级) -> rollback(回滚) -> package(打包)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效
CHART="manifests/demo-chart"
RELEASE="demo"
step() { echo; echo "=====> [$1] $2"; }

do_lint() {
    step "lint" "helm lint: 静态检查模板与 values"
    helm lint "$CHART"

    step "lint" "helm template: 不进集群, 本地渲染看产物"
    helm template "$RELEASE" "$CHART" --set ingress.enabled=false | head -30
}

do_install() {
    step "install" "安装 chart"
    helm upgrade --install "$RELEASE" "$CHART" \
        --set image.tag=1.25.3 \
        --set config.features.FEATURE_A=off --wait

    step "install" "查看 release 与渲染出的资源"
    helm list; kubectl get deploy,svc,cm,ingress -l app.kubernetes.io/instance="$RELEASE"
}

do_upgrade() {
    step "upgrade" "改值升级: 副本 2->3 (helm3 默认复用上次 release 的值, 这里 --reuse-values 显式表达意图)"
    helm upgrade "$RELEASE" "$CHART" \
        --set replicaCount=3 --set image.tag=1.25.3 --reuse-values --wait
    helm get values "$RELEASE"

    step "upgrade" "回滚到上一版本"
    helm rollback "$RELEASE" 1 && helm history "$RELEASE"
}

do_package() {
    step "package" "打包成 .tgz 可发布到 Chart Museum/OCI registry"
    helm package "$CHART"
    helm show chart demo-chart-0.1.0.tgz
}

case "${1:-all}" in
    lint) do_lint ;; install) do_install ;; upgrade) do_upgrade ;;
    package) do_package ;;
    all) do_lint; do_install ;;
esac
