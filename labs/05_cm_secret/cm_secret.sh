#!/usr/bin/env bash
# =============================================================================
# Kubernetes 05: ConfigMap 与 Secret 实战演示脚本
#
# 演示内容：
#   1. kubectl 命令行创建 ConfigMap (from-literal / from-file)
#   2. kubectl 命令行创建 Secret (generic)
#   3. 应用 YAML 中的 Pod，验证 4 种注入方式 (env / volume)
#   4. ConfigMap 更新后挂载文件的热更新 (subPath 不会热更新)
#   5. 清理资源
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"
NS="default"
PAUSE_SECS=3          # 等待资源就绪的间隔

# ---------- 工具函数 ----------
hr()  { printf '\n\033[1;36m========== %s ==========\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
wait_pod_running() {  # 等待 Pod 进入 Running 状态
  kubectl -n "$NS" wait --for=condition=Ready "pod/$1" --timeout=60s
}

hr "步骤 1/5: 命令行创建 ConfigMap"
# 方式 A: --from-literal 逐个传入键值对
kubectl create configmap cli-config \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=APP_MODE=test
ok "cli-config 创建成功 (from-literal)"

# 方式 B: --from-file 把整个文件内容作为值 (键名默认为文件名)
TMP_CONF="/tmp/app-conf-$$.conf"
cat > "$TMP_CONF" <<'EOF'
timeout = 30
retries = 3
EOF
kubectl create configmap cli-file-config --from-file="$TMP_CONF"
ok "cli-file-config 创建成功 (from-file, 键名 = $(basename "$TMP_CONF"))"
kubectl get configmap -o name | sed 's/^/  /'

hr "步骤 2/5: 命令行创建 Secret"
# generic 即 Opaque 类型；--from-literal 传明文，k8s 自动 base64 编码
kubectl create secret generic cli-db-secret \
  --from-literal=DB_USERNAME=admin \
  --from-literal=DB_PASSWORD='cli-P@ss-456'
ok "cli-db-secret 创建成功"
echo "  -- Secret 存储的是 base64 (注意：编码不等于加密!)"
kubectl get secret cli-db-secret \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | sed 's/^/     解码后: /'; echo

hr "步骤 3/5: 应用 YAML 中的 Pod 并验证 4 种注入方式"
kubectl apply -f "manifests/cm_secret.yaml"
wait_pod_running app-pod

echo "  [①/③] 环境变量注入 (ConfigMap env + Secret env):"
kubectl exec app-pod -- sh -c \
  'env | grep -E "LOG_LEVEL|DB_PASSWORD"' | sed 's/^/     /'

echo "  [②/④] 卷挂载注入 (ConfigMap volume + Secret volume):"
kubectl exec app-pod -- sh -c \
  'ls -l /etc/config /etc/secret && echo "--- app.conf 内容 ---" && cat /etc/config/app.conf' \
  | sed 's/^/     /'

hr "步骤 4/5: ConfigMap 热更新演示 (volume 会自动同步, env 不会)"
echo "  -- 修改前文件内容:"
kubectl exec app-pod -- cat /etc/config/app.conf | sed 's/^/     /'
# 直接 patch ConfigMap，改变挂载文件内容
kubectl patch configmap app-file-config \
  --type merge -p '{"data":{"app.conf":"timeout = 60\nretries = 5\n"}}'
echo "  -- 已 patch ConfigMap，轮询等待 kubelet 同步 (同步周期最长约 1 分钟)..."
# kubelet 对 ConfigMap 卷的同步周期最长 60s, 固定 sleep 不够; 轮询直到内容变化
n=0
until kubectl exec app-pod -- cat /etc/config/app.conf 2>/dev/null | grep -q "timeout = 60"; do
    n=$((n + 1))
    if [ "$n" -ge 30 ]; then
        echo "  [WARN] 等了 90s 还没同步, 跳过 (可稍后手动 cat 验证)"
        break
    fi
    sleep 3
done
echo "  -- 修改后文件内容 (volume 挂载自动更新):"
kubectl exec app-pod -- cat /etc/config/app.conf | sed 's/^/     /'
echo "  -- 但环境变量 LOG_LEVEL 仍是创建时的值 (env 注入不会更新):"
kubectl exec app-pod -- sh -c 'echo $LOG_LEVEL' | sed 's/^/     /'
echo "  -- 陷阱: 如果挂载时用了 subPath, 即使 volume 方式也不会热更新!"

hr "步骤 5/5: 清理资源"
kubectl delete -f "manifests/cm_secret.yaml" --ignore-not-found
kubectl delete configmap cli-config cli-file-config --ignore-not-found
kubectl delete secret cli-db-secret --ignore-not-found
rm -f "$TMP_CONF"
ok "全部资源已清理，演示结束"
