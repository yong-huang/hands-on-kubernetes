#!/usr/bin/env bash
# ============================================================
# Pod 实操脚本：apply / watch / describe / log / exec / label / 清理
# 前置条件: 已有可用的 K8s 集群 (minikube/kind/云集群)，kubectl 已配好
# 用法: ./pod.sh [ns]   (默认 namespace: default)
# ============================================================
set -euo pipefail

# 统一切换到实验根目录, 使 manifests/ 等相对路径生效
cd "$(dirname "$0")"
NS="${1:-default}"
MANIFEST="manifests/pod.yaml"

# ---------- 工具函数 ----------
header() {  # 打印分节标题
    echo
    echo "=================================================="
    echo "  $*"
    echo "=================================================="
}

step() {    # 打印单步说明
    echo "--- $*"
}

# ---------- 0. 环境检查 ----------
header "0. 环境检查"
kubectl cluster-info | head -1
kubectl get nodes -o wide

# ---------- 1. 应用清单并观察状态变化 ----------
header "1. 创建 Pod（apply）"
step "应用 pod.yaml，包含 4 个 Pod 示例"
kubectl apply -f "$MANIFEST" -n "$NS"

step "轮询 Pod 状态：Pending → ContainerCreating → Running"
# Pod 调度流程: 待调度(Pending) → 拉镜像+建容器(ContainerCreating) → 运行(Running)
for i in 1 2 3 4 5 6; do
    kubectl get pods -n "$NS" -o wide
    sleep 3
done

# ---------- 2. describe：排查 Pod 问题第一站 ----------
header "2. kubectl describe —— 事件与探针状态"
step "查看 nginx Pod 详情（关注 Events 段）"
kubectl describe pod nginx-pod -n "$NS" | head -40

step "查看 init Pod：确认 initContainers 状态已变为 Initialized/True"
kubectl describe pod init-demo-pod -n "$NS" | grep -A 5 "Init Containers\|Conditions"

# ---------- 3. 日志：单容器与多容器 (-c) ----------
header "3. kubectl logs"
step "sidecar Pod：分别看主容器和 sidecar 容器的日志（-c 指定容器）"
kubectl logs nginx-sidecar-pod -c nginx      -n "$NS" --tail=5 || true
kubectl logs nginx-sidecar-pod -c log-tailer -n "$NS" --tail=5 || true

step "跟踪式日志 (-f)，后台跟踪几秒后自动结束 (脚本里不便 Ctrl+C)"
kubectl logs -f nginx-sidecar-pod -c log-tailer -n "$NS" --tail=3 &
LOG_PID=$!
sleep 5
# 演示结束, 杀掉后台日志进程, 避免它一直挂着污染后续步骤的输出
kill "${LOG_PID}" 2>/dev/null || true
wait "${LOG_PID}" 2>/dev/null || true

# ---------- 4. exec：进入容器执行命令 ----------
header "4. kubectl exec"
step "在 nginx 容器内执行命令（非交互）"
kubectl exec nginx-pod -n "$NS" -- nginx -v

step "验证 sidecar 共享卷：从 log-tailer 侧确认能看到 nginx 的日志文件"
kubectl exec nginx-sidecar-pod -c log-tailer -n "$NS" -- ls -la /var/log/nginx

step "交互式进入容器（演示用，脚本里不执行）: kubectl exec -it nginx-pod -- sh"

# ---------- 5. 标签与选择器 ----------
header "5. labels 与 selector"
step "查看所有 Pod 的标签"
kubectl get pods -n "$NS" --show-labels

step "用 -l 选择器筛选: app=nginx（同时命中 nginx-pod 和 sidecar pod）"
kubectl get pods -n "$NS" -l app=nginx

step "多条件筛选: app=nginx 且 tier=frontend"
kubectl get pods -n "$NS" -l "app=nginx,tier=frontend"

step "运行时打标签/改标签"
kubectl label pod nginx-pod -n "$NS" env=demo --overwrite
kubectl get pod nginx-pod -n "$NS" -L env      # -L 把标签值显示成一列

# ---------- 6. 探针与重启计数 ----------
header "6. 探针与重启计数"
step "RESTARTS 列: 0 表示探针健康；持续增长通常意味着 CrashLoopBackOff"
kubectl get pods -n "$NS"

step "以 JSON 输出查看容器状态与重启原因 (Last State)"
kubectl get pod probe-demo-pod -n "$NS" \
    -o jsonpath='{range .status.containerStatuses[*]}{.name}{"  restarts="}{.restartCount}{"  ready="}{.ready}{"\n"}{end}'

# ---------- 7. 清理 ----------
header "7. 清理资源"
step "删除本次创建的所有 Pod"
kubectl delete -f "$MANIFEST" -n "$NS"

step "确认清理完成"
kubectl get pods -n "$NS"
echo "Done."
