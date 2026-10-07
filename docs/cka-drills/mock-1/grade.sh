#!/usr/bin/env bash
# CKA 全真模考 #1 · 自动判分（16 题，权重合计 100）
set -u
P=0; SCORE=0
ok()  { echo "✅ $1 (+${2})"; P=$((P+1)); SCORE=$((SCORE+$2)); }
bad() { echo "❌ $1 (+0)"; }

# ---------- kind-k8s-learn ----------
kubectl config use-context kind-k8s-learn >/dev/null

# T1 RBAC (7)
A=$(kubectl auth can-i list pods --as=system:serviceaccount:audit:scanner -n audit 2>/dev/null)
B=$(kubectl auth can-i delete pods --as=system:serviceaccount:audit:scanner -n audit 2>/dev/null)
[ "$A" = "yes" ] && [ "$B" = "no" ] && ok "T1 RBAC 最小权限" 7 || bad "T1 RBAC 最小权限"

# T2 kubeconfig (6)
CC=$(kubectl config --kubeconfig=/tmp/exam/config current-context 2>/dev/null)
N=$(kubectl --kubeconfig=/tmp/exam/config get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$CC" = "staging" ] && [ "${N:-0}" -ge 1 ] && ok "T2 kubeconfig 合并与切换" 6 || bad "T2 kubeconfig 合并与切换"

# T3 PSA (5)
E=$(kubectl get ns secure -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
REJ=$(kubectl -n secure run pri-check --image=busybox:1.36 --restart=Never --overrides='{"spec":{"containers":[{"name":"c","image":"busybox:1.36","securityContext":{"privileged":true}}]}}' --dry-run=server 2>&1 || true)
echo "$REJ" | grep -q "PodSecurity" && [ "$E" = "baseline" ] && ok "T3 PSA baseline 加固" 5 || bad "T3 PSA baseline 加固"

# T4 节点维护 (7)
L=$(kubectl get node k8s-learn-worker2 -o jsonpath='{.metadata.labels.disk}' 2>/dev/null)
T=$(kubectl get node k8s-learn-worker2 -o jsonpath='{.spec.taints[?(@.key=="special")].effect}' 2>/dev/null)
C=$(kubectl get node k8s-learn-worker2 -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
[ "$L" = "ssd" ] && [ "$T" = "NoSchedule" ] && { [ "$C" = "false" ] || [ -z "$C" ]; } && ok "T4 drain+label+taint+uncordon" 7 || bad "T4 drain+label+taint+uncordon"

# T5 滚动更新与回滚 (5)
IMG=$(kubectl -n apps get deploy fe -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
MS=$(kubectl -n apps get deploy fe -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)
MU=$(kubectl -n apps get deploy fe -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
[ "$IMG" = "nginx:1.25" ] && [ "$MS" = "1" ] && [ "$MU" = "0" ] && ok "T5 滚动更新+回滚+策略" 5 || bad "T5 滚动更新+回滚+策略"

# T6 ConfigMap/Secret 注入 (5)
PE=$(kubectl -n apps exec pod/web -- env 2>/dev/null | grep -c "pass=secret123")
CF=$(kubectl -n apps exec pod/web -- cat /etc/cfg/index_content 2>/dev/null)
[ "$PE" -ge 1 ] 2>/dev/null && [ "$CF" = "hello-cka" ] && ok "T6 CM/Secret 双注入" 5 || bad "T6 CM/Secret 双注入"

# T7 定向调度 (5)
PN=$(kubectl -n apps get pod pinned -o jsonpath='{.spec.nodeName}' 2>/dev/null)
TL=$(kubectl -n apps get pod tolerant -o jsonpath='{.spec.nodeName}' 2>/dev/null)
TR=$(kubectl -n apps get pod tolerant -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$PN" = "k8s-learn-worker2" ] && [ "$TL" = "k8s-learn-worker2" ] && [ "$TR" = "Running" ] && ok "T7 nodeName+toleration 定向" 5 || bad "T7 nodeName+toleration 定向"

# T8 Service (6)
NP=$(kubectl -n apps get svc api-np -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
EP=$(kubectl -n apps get ep api-svc -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
W=$(kubectl -n apps exec pod/$(kubectl -n apps get pod -l app=api2 -o jsonpath='{.items[0].metadata.name}') -- wget -qO- -T 3 http://api-svc 2>/dev/null)
[ "$NP" = "30080" ] && [ -n "$EP" ] && echo "$W" | grep -q api2-ok && ok "T8 ClusterIP+NodePort 暴露" 6 || bad "T8 ClusterIP+NodePort 暴露"

# T10 Ingress (7)
NIP=$(kubectl -n ingress-nginx get pod -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.hostIP}' 2>/dev/null)
RA=$(curl -s -m 5 -H "Host: a.exam.local" "http://$NIP/a" 2>/dev/null)
RB=$(curl -s -m 5 -H "Host: a.exam.local" "http://$NIP/" 2>/dev/null)
echo "$RA" | grep -q content-a && echo "$RB" | grep -q content-b && ok "T10 Ingress 路由与默认后端" 7 || bad "T10 Ingress 路由与默认后端"

# T11 静态 PV/PVC (5)
B=$(kubectl -n apps get pvc exam-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
F=$(kubectl -n apps exec pv-user -- cat /data/it-works.txt 2>/dev/null)
[ "$B" = "Bound" ] && [ "$F" = "cka-pass" ] && ok "T11 静态 PV 绑定与挂载" 5 || bad "T11 静态 PV 绑定与挂载"

# T12 动态供给与默认 SC (5)
D=$(kubectl get sc exam-fast -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
SCN=$(kubectl -n apps get pvc dyn-pvc -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
S=$(kubectl -n apps get pvc dyn-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$D" = "true" ] && [ "$SCN" = "exam-fast" ] && [ "$S" = "Bound" ] && ok "T12 SC 动态供给" 5 || bad "T12 SC 动态供给"

# T13 四大故障修复 (7)
FIX=0
for p in bad-image bad-cmd stuck-pending oom-loop; do
  R=$(kubectl -n broken get pod $p -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$R" = "Running" ] && FIX=$((FIX+1))
done
[ "$FIX" -eq 4 ] && ok "T13 四态全修" 7 || bad "T13 四态全修（$FIX/4）"

# T14 PVC 排障 (6)
SB=$(kubectl -n store get pvc data-claim -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$SB" = "Bound" ] && ok "T14 PVC Pending 修复" 6 || bad "T14 PVC Pending 修复"

# T16 控制面 (9)
SCH=$(kubectl -n kube-system get pod 2>/dev/null | grep -c kube-scheduler)
[ "${SCH:-0}" -ge 1 ] && ok "T16 控制面组件恢复" 9 || bad "T16 控制面组件恢复"

# ---------- kind-cka-netpol ----------
kubectl config use-context kind-cka-netpol >/dev/null

# T9 NetworkPolicy (7)
CL=$(kubectl -n np-exam exec client -- wget -qO- -T 3 http://api-svc 2>/dev/null)
OT=$(kubectl -n np-exam exec other -- wget -qO- -T 3 http://api-svc 2>&1)
echo "$CL" | grep -q api-ok && echo "$OT" | grep -q "timed out" && ok "T9 NP 默认拒绝+白名单" 7 || bad "T9 NP 默认拒绝+白名单"

# T15 双故障修复 (8)
CY=$(kubectl -n pay exec $(kubectl -n pay get pod -l app=client -o jsonpath='{.items[0].metadata.name}') -- wget -qO- -T 4 http://cache-svc 2>/dev/null)
echo "$CY" | grep -q cache-ok && ok "T15 Service 全链路修复" 8 || bad "T15 Service 全链路修复"

kubectl config use-context kind-k8s-learn >/dev/null
echo ""
echo "══════════════════════════════"
echo "通过题数: $P/16   得分: $SCORE/100 ($SCORE%)"
[ "$SCORE" -ge 66 ] && echo "🏆 PASS（≥66）" || echo "📚 FAIL（<66），错题回炉重练"
exit 0
