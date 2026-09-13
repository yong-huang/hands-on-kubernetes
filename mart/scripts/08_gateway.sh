#!/usr/bin/env bash
# 项目 8：API 网关（认证/限流/灰度）—— 部署 / 三项验收 / 清理
# 全部请求经 ingress-nginx 控制器（集群内直达，Host: mart.local）
# 用法: ./08_gateway.sh [build|apply|observe|verify-auth|verify-ratelimit|verify-canary|clean|all]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig-kind}"

NS="mart"
ING="ingress-nginx-controller.ingress-nginx.svc"   # 集群内直达控制器
KIND_CLUSTER="${KIND_CLUSTER:-$(kind get clusters 2>/dev/null | grep -qx kind && echo kind || kind get clusters 2>/dev/null | head -1)}"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"   # kind API 偶发抖动时的兜底

step() { echo; echo "=====> [$1] $2"; }

gw() {  # 经 product Pod 访问网关；$1=path $2=额外 header(可空) $3=额外值
    local path="$1" hdr="${2:-}" val="${3:-}" pod
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request
req = urllib.request.Request('http://$ING$path', headers={'Host': 'mart.local'$([ -n "$hdr" ] && echo ", '$hdr': '$val'")})
try:
    r = urllib.request.urlopen(req, timeout=10)
    print(r.status, r.read().decode()[:160])
except urllib.error.HTTPError as e:
    print(e.code, e.read().decode()[:160])
"
}

get_token() {  # 从 auth 服务取一个合法 JWT
    local pod
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request, json
d = json.load(urllib.request.urlopen('http://auth.mart.svc:8000/token?sub=acceptance', timeout=5))
print(d['token'])
"
}

do_build() {
    step "build" "构建 auth:0.1.0"
    docker build -q -t mart/auth:0.1.0 -f services/auth/Dockerfile services/auth
    kind load docker-image mart/auth:0.1.0 --name "$KIND_CLUSTER"
}

do_apply() {
    step "apply" "部署 auth / product-v2 / 网关 Ingress 规则"
    kubectl apply -f deploy/auth/manifests.yaml
    kubectl -n "$NS" rollout status deployment/auth --timeout=180s
    kubectl apply -f deploy/gateway/manifests.yaml
    kubectl -n "$NS" rollout status deployment/product-v2 --timeout=180s
    kubectl -n "$NS" get ingress
}

do_observe() {
    step "observe" "网关连通性（无 token 应 401）"
    gw /version
}

# 验收①：无 token 401，合法 JWT 200
do_verify_auth() {
    step "verify-auth" "无 token 访问 /version"
    local r
    r=$(gw /version); echo "  -> $r"
    echo "$r" | grep -q '^401' || { echo "❌ 无 token 应 401"; exit 1; }
    local token r2
    token=$(get_token)
    r2=$(gw /version "Authorization" "Bearer $token"); echo "  -> $r2"
    echo "$r2" | grep -q '^200' || { echo "❌ 合法 token 应 200"; exit 1; }
    echo "✅ 验收①通过：无 token 401 / 合法 JWT 200（external auth 模式）"
}

# 验收②：限流 5 r/s，超限 429
do_verify_ratelimit() {
    local token
    token=$(get_token)
    step "verify-ratelimit" "携带合法 token 连发 40 个请求（超 5r/s + burst），统计 429/503"
    local pod codes429=0 i s
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    s=$(kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request
token = '''$token'''
codes = []
for i in range(40):
    req = urllib.request.Request('http://$ING/version',
        headers={'Host': 'mart.local', 'Authorization': 'Bearer ' + token})
    try:
        codes.append(urllib.request.urlopen(req, timeout=5).status)
    except urllib.error.HTTPError as e:
        codes.append(e.code)
print(' '.join(str(c) for c in codes))
")
    echo "  -> $s"
    for c in $s; do { [ "$c" = "429" ] || [ "$c" = "503" ]; } && codes429=$((codes429+1)); done
    if [ "$codes429" -ge 1 ]; then
        echo "✅ 验收②通过：限流生效，出现 ${codes429} 次拒绝（429/503，nginx 默认 burst=25 需要打满）"
    else
        echo "❌ 未出现限流拒绝"; exit 1
    fi
    sleep 3
}

# 验收③：X-Canary: true 100% 进 v2，不带 header 100% v1
do_verify_canary() {
    local token
    token=$(get_token)
    step "verify-canary" "带 X-Canary: true 连打 5 次"
    local pod
    pod=$(kubectl -n "$NS" get pods -l app=product -o jsonpath='{.items[0].metadata.name}')
    local out
    out=$(kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request, time
token = '''$token'''
for i in range(5):
    req = urllib.request.Request('http://$ING/version',
        headers={'Host': 'mart.local', 'Authorization': 'Bearer ' + token, 'X-Canary': 'true'})
    try:
        r = urllib.request.urlopen(req, timeout=5)
        print(r.status, r.read().decode()[:80])
    except urllib.error.HTTPError as e:
        print(e.code)
    time.sleep(1.1)   # 避开限流
")
    echo "$out"
    local v2
    v2=$(echo "$out" | grep -c '0.4.0-canary')
    [ "$v2" = "5" ] || { echo "❌ 灰度 header 未 100% 命中 v2（$v2/5）"; exit 1; }
    step "verify-canary" "不带 header 连打 5 次（间隔避开限流）"
    out=$(kubectl -n "$NS" exec "$pod" -- python -c "
import urllib.request, time
token = '''$token'''
for i in range(5):
    req = urllib.request.Request('http://$ING/version',
        headers={'Host': 'mart.local', 'Authorization': 'Bearer ' + token})
    try:
        r = urllib.request.urlopen(req, timeout=5)
        print(r.status, r.read().decode()[:80])
    except urllib.error.HTTPError as e:
        print(e.code)
    time.sleep(1.1)
")
    echo "$out"
    local v1
    v1=$(echo "$out" | grep -c '"version":"0.3.0"')
    [ "$v1" = "5" ] || { echo "❌ 基线未 100% 命中 v1（$v1/5）"; exit 1; }
    echo "✅ 验收③通过：X-Canary: true 100% 进 v2，无 header 100% v1"
}

do_clean() {
    step "clean" "删除灰度与网关规则（保留 auth 服务）"
    kubectl -n "$NS" delete -f deploy/gateway/manifests.yaml --ignore-not-found
}

main() {
    local target="${1:-all}"
    case "$target" in
        build) do_build ;; apply) do_apply ;; observe) do_observe ;;
        verify-auth) do_verify_auth ;;
        verify-ratelimit) do_verify_ratelimit ;;
        verify-canary) do_verify_canary ;;
        clean) do_clean ;;
        all) do_build; do_apply; do_observe; do_verify_auth; do_verify_ratelimit; do_verify_canary ;;
        *) echo "可用: build|apply|observe|verify-auth|verify-ratelimit|verify-canary|clean|all" >&2; exit 1 ;;
    esac
}
main "$@"
