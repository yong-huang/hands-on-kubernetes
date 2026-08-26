#!/usr/bin/env bash
# =============================================================================
# HashiCorp Vault + Secrets Store CSI 全流程演示
# 覆盖: install(Vault+CSI) -> config(启用数据库动态引擎/K8s认证) -> run(Pod取凭证)
#       -> rotate(轮换验证) -> clean
# 用法: ./vault_setup.sh [step]
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

NS_VAULT="vault"; NS_APP="vault-demo"
step() { echo; echo "=====> [$1] $2"; }

do_install() {
    step "install" "部署 Vault(dev 模式) 与 Secrets Store CSI Driver"
    helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
    helm upgrade --install vault hashicorp/vault -n "$NS_VAULT" --create-namespace \
        --set "server.dev.enabled=true" --wait

    helm repo add secrets-store-csi-driver \
        https://kubernetes-sigs.github.io/secrets-store-csi-driver >/dev/null 2>&1 || true
    helm upgrade --install csi-secrets-store \
        secrets-store-csi-driver/secrets-store-csi-driver \
        -n kube-system --set syncSecret.enabled=true --wait

    kubectl create ns "$NS_APP" --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n "$NS_APP" create sa demo-app --dry-run=client -o yaml | kubectl apply -f -
}

do_config() {
    step "config" "端口转发并在 Vault 中启用 K8s 认证 + 数据库动态引擎"
    kubectl -n "$NS_VAULT" port-forward svc/vault 8200:8200 >/dev/null 2>&1 &
    PF=$!; sleep 2
    export VAULT_ADDR="http://127.0.0.1:8200"
    export VAULT_TOKEN="root"                       # dev 模式固定 root token

    # K8s 认证: 让 Pod 的 SA Token 可换 Vault token
    # 注意: 本脚本在宿主机运行, 没有 KUBERNETES_SERVICE_* 环境变量,
    # 从当前 kubeconfig 读取 API Server 地址 (kind 集群即控制面容器暴露的端口)
    kubernetes_host="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
    vault auth enable kubernetes 2>/dev/null || true
    vault write auth/kubernetes/config \
        kubernetes_host="$kubernetes_host"
    vault write auth/kubernetes/role/demo-app \
        bound_service_account_names=demo-app \
        bound_service_account_namespaces="$NS_APP" \
        policies=demo-app ttl=1h

    # 数据库动态引擎: 每次"租约"生成一组临时 DB 凭证(TTL 1h, 自动回收)
    # 先部署演示用 PostgreSQL(清单里自带, 见 manifests/vault_secrets.yaml 末尾),
    # 引擎要用管理员账号连上去执行 CREATE ROLE
    kubectl apply -f manifests/vault_secrets.yaml >/dev/null
    kubectl -n "$NS_APP" rollout status deploy/postgres --timeout=180s

    vault secrets enable database 2>/dev/null || true
    vault write database/config/my-postgres \
        plugin_name=postgresql-database-plugin \
        allowed_roles=demo-app \
        username="vaultadmin" password="vaultadminpass" \
        connection_url="postgresql://{{username}}:{{password}}@postgres.vault-demo.svc.cluster.local:5432/app?sslmode=disable"
    vault write database/roles/demo-app \
        db_name=my-postgres \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}';" \
        default_ttl=1h max_ttl=24h

    vault policy write demo-app - <<'POLICY'
path "database/creds/demo-app" { capabilities = ["read"] }
POLICY
    kill $PF 2>/dev/null || true
}

do_run() {
    step "run" "部署应用 Pod, 观察 CSI 挂载的动态凭证"
    kubectl apply -f manifests/vault_secrets.yaml
    kubectl -n "$NS_APP" rollout status deploy/demo-app --timeout=120s
    sleep 3
    kubectl -n "$NS_APP" logs deploy/demo-app --tail=5

    step "run" "同步出来的原生 Secret(供 env 方式消费)"
    kubectl -n "$NS_APP" get secret db-creds-synced -o jsonpath='{.data.db_user}' | base64 -d; echo
}

do_rotate() {
    step "rotate" "凭证轮换: 删除 Pod 强制重新挂载 -> Vault 签发全新用户名"
    kubectl -n "$NS_APP" delete pod -l app=demo-app
    kubectl -n "$NS_APP" rollout status deploy/demo-app --timeout=120s
    kubectl -n "$NS_APP" logs deploy/demo-app --tail=3 | tail -2
}

do_clean() {
    step "clean" "删除演示资源"
    kubectl delete ns "$NS_APP" --ignore-not-found
}

case "${1:-all}" in
    install) do_install ;; config) do_config ;; run) do_run ;;
    rotate)  do_rotate  ;; clean) do_clean ;;
    all)     do_install; do_config; do_run ;;
esac
