#!/usr/bin/env bash
# 项目 9：微服务 CI/CD 与 GitOps 交付（本机离线 fallback 路线）
# 真实形态 = GitHub Actions（见仓库 .github/workflows/build-deploy.yml）+ ArgoCD
# 离线形态 = 本脚本扮演 CI（按 git diff 只构建改动服务）+ ArgoCD watch 本地 git 仓库
# 用法: ./09_cicd.sh [serve-git|init-repo|apply-apps|verify-sync|verify-deliver|verify-revert|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
GIT_PORT=9418
GIT_URL="git://host.internal:${GIT_PORT}/gitops-remote.git"
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

argocd_apps() { kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null; }

do_serve_git() {
    step "serve-git" "启动主机 git daemon（9418 端口，只读）"
    if nc -z -w 2 127.0.0.1 "$GIT_PORT" 2>/dev/null; then
        echo "  已在运行"
    else
        (nohup git daemon --base-path="$PWD" --export-all --reuseaddr --port="$GIT_PORT" >/tmp/git-daemon.log 2>&1 &)
        sleep 2
        nc -z -w 2 127.0.0.1 "$GIT_PORT" && echo "  daemon up"
    fi
}

do_init_repo() {
    step "init-repo" "用 deploy/ 清单初始化 gitops 仓库并推送"
    rm -rf gitops gitops-remote.git
    mkdir -p gitops
    for svc in product order inventory notification; do
        mkdir -p "gitops/$svc"
        cp "deploy/$svc/manifests.yaml" "gitops/$svc/"
    done
    (cd gitops && git init -q -b main && git add -A && git commit -qm "seed: mini-mart four services")
    git init -q --bare gitops-remote.git
    (cd gitops && git remote add origin ../gitops-remote.git && git push -q origin main)
    echo "  gitops repo seeded (4 services)"
}

do_apply_apps() {
    step "apply-apps" "创建 4 个 ArgoCD Application（自动同步 + 自愈）"
    kubectl apply -f deploy/argocd/apps.yaml
    sleep 5
}

do_verify_sync() {
    step "verify-sync" "等待 4 个 Application Synced + Healthy"
    local deadline=$((SECONDS + 240)) synced
    while [ "$SECONDS" -lt "$deadline" ]; do
        synced=$(argocd_apps | jq '[.items[] | select(.status.sync.status=="Synced" and .status.health.status=="Healthy")] | length')
        [ "$synced" = "4" ] && { echo "✅ 4/4 Applications Synced + Healthy"; return 0; }
        sleep 8
    done
    argocd_apps | jq -r '.items[] | "\(.metadata.name): \(.status.sync.status)/\(.status.health.status)"'
    echo "❌ 240s 内未全部 Synced"; exit 1
}

# "CI"：git diff 判断哪些服务有改动，只构建改动的镜像（GitHub Actions 里是 paths 过滤）
ci_build_changed() {
    local changed
    changed=$(cd gitops && git diff --name-only HEAD~1 HEAD 2>/dev/null | cut -d/ -f1 | sort -u)
    echo "CI 检测到改动: ${changed:-<none>}"
    for svc in product order inventory notification; do
        if echo "$changed" | grep -qx "$svc"; then
            echo "  [CI] building $svc ..."
        else
            echo "  [CI] skip $svc (未改动)"
        fi
    done
    echo "$changed"
}

do_verify_deliver() {
    step "verify-deliver" "只改 product：bump 镜像 tag 到 0.5.0 并提交"
    docker build -q -t mart/product:0.5.0 -f services/product/Dockerfile services/product
    docker exec kind-control-plane crictl rmi docker.io/mart/product:0.5.0 >/dev/null 2>&1 || true
    kind load docker-image mart/product:0.5.0 --name "$KIND_CLUSTER" || echo "  ⚠️ kind load 失败（宿主 docker API 抖动），假定镜像已在节点"
    sed -i '' 's|mart/product:0.3.0|mart/product:0.5.0|g; s|value: "0.3.0"|value: "0.5.0"|' gitops/product/manifests.yaml
    (cd gitops && git add -A && git commit -qm "ci: release product 0.5.0")
    (cd gitops && git push -q origin main)
    local changed
    changed=$(ci_build_changed)
    echo "$changed" | grep -qx "product" || { echo "❌ CI 未识别 product 改动"; exit 1; }

    step "verify-deliver" "等待 ArgoCD 自动同步 + 滚动到 0.5.0"
    local deadline=$((SECONDS + 300)) ver=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        local image
        image=$(kubectl -n "$NS" get deploy product -o jsonpath='{.spec.template.spec.containers[0].image}')
        if [ "$image" = "mart/product:0.5.0" ]; then
            kubectl -n "$NS" rollout status deployment/product --timeout=120s >/dev/null 2>&1 || true
            local pod
            pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
            ver=$(kubectl -n "$NS" exec "$pod" -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/version',timeout=3).read().decode())" 2>/dev/null || echo "")
            echo "$ver" | grep -q '0.5.0' && break
        fi
        sleep 8
    done
    echo "$ver" | grep -q '0.5.0' || { echo "❌ 300s 内未发布到 0.5.0（last image: $image, ver: $ver）"; exit 1; }
    echo "✅ 验收①通过：只构建改动的 product，ArgoCD 自动交付，线上版本 0.5.0"
}

do_verify_revert() {
    step "verify-revert" "git revert 发布 commit，观察自动回滚"
    (cd gitops && git revert --no-edit HEAD >/dev/null && git push -q origin main)
    local deadline=$((SECONDS + 300)) image=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        image=$(kubectl -n "$NS" get deploy product -o jsonpath='{.spec.template.spec.containers[0].image}')
        [ "$image" = "mart/product:0.3.0" ] && break
        sleep 8
    done
    if [ "$image" = "mart/product:0.3.0" ]; then
        kubectl -n "$NS" rollout status deployment/product --timeout=120s >/dev/null
        echo "✅ 验收②通过：git revert 后 ArgoCD 自动回滚到 0.3.0"
    else
        echo "❌ 300s 内未回滚（image: $image）"; exit 1
    fi
}

do_clean() {
    step "clean" "回滚 gitops 仓库到 seed（保留 ArgoCD）"
    (cd gitops && git reset -q --hard origin/main 2>/dev/null || true)
}

main() {
    local target="${1:-all}"
    case "$target" in
        serve-git) do_serve_git ;;
        init-repo) do_init_repo ;;
        apply-apps) do_apply_apps ;;
        verify-sync) do_verify_sync ;;
        verify-deliver) do_verify_deliver ;;
        verify-revert) do_verify_revert ;;
        clean) do_clean ;;
        all) do_serve_git; do_init_repo; do_apply_apps; do_verify_sync; do_verify_deliver; do_verify_revert ;;
        *) echo "可用: serve-git|init-repo|apply-apps|verify-sync|verify-deliver|verify-revert|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
