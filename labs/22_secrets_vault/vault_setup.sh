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

    # CSI 驱动: 官方 chart 仓库已迁移(github pages 404, OCI 在 ghcr 上国内不可达),
    # 改用仓库内的 raw 清单(含 CRD/RBAC/DaemonSet), raw 不通时走 jsdelivr CDN
    local base_raw="https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy"
    local base_cdn="https://cdn.jsdelivr.net/gh/kubernetes-sigs/secrets-store-csi-driver@main/deploy"
    for f in secrets-store.csi.x-k8s.io_secretproviderclasses.yaml \
             secrets-store.csi.x-k8s.io_secretproviderclasspodstatuses.yaml \
             rbac-secretproviderclass.yaml rbac-secretprovidersyncing.yaml \
             csidriver.yaml secrets-store-csi-driver.yaml; do
        kubectl apply -f "${base_raw}/${f}" || kubectl apply -f "${base_cdn}/${f}"
    done
    kubectl -n kube-system rollout status ds/csi-secrets-store --timeout=180s

    # CSI 驱动是通用的, Vault 后端由独立的 provider 提供:
    # 用 hashicorp/vault chart 的 csi 子图表装 provider 本体(server/injector 关掉,
    # externalVaultAddr 指向上面部署的 Vault)
    helm upgrade --install vault-csi hashicorp/vault -n "$NS_VAULT" \
        --set server.enabled=false --set injector.enabled=false --set csi.enabled=true \
        --set "global.externalVaultAddr=http://vault.${NS_VAULT}.svc:8200" --wait

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
    # 注意: kubernetes_host 必须是 Vault 服务端(Pod 内)可达的地址。
    # kubeconfig 里的 127.0.0.1:PORT 是宿主机映射端口, 集群内不通,
    # 用集群内 Service 地址(Vault Pod 自带访问 API Server 的 SA 与 CA)
    vault auth enable kubernetes 2>/dev/null || true
    vault write auth/kubernetes/config \
        kubernetes_host="https://kubernetes.default.svc:443"
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
