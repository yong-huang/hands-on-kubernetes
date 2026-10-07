#!/usr/bin/env bash
# 项目 30 综合限时排障 · 故障注入脚本
# 用法: bash chaos-30.sh            # 默认注入到 kind-cka-netpol
#       bash chaos-30.sh kind-k8s-learn   # 无 NP 执行能力的集群 → F5 失效，verify 按 4/5 计
# 规则: 注入后 60 分钟内修复全部 5 处，bash verify-30.sh 判分
set -euo pipefail
CTX="${1:-kind-cka-netpol}"
kubectl config use-context "$CTX"

kubectl create ns shop --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create ns pay  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n shop delete deploy,svc,pvc,pod,netpol --all --ignore-not-found >/dev/null
kubectl -n pay  delete deploy,svc,pvc,pod,netpol --all --ignore-not-found >/dev/null

echo "==> [F1] shop/web: 镜像 tag 不存在 (ImagePullBackOff)"
kubectl -n shop create deploy web --image=busybox:9.9.9-nonexist --replicas=1 -- sh -c "sleep 3600" >/dev/null

echo "==> [F2] shop/api-svc: selector 与 pod label 不匹配 (ep 为空)"
kubectl -n shop create deploy api --image=busybox:1.36 --replicas=1 -- sh -c "mkdir -p /www && echo api-ok > /www/index.html && httpd -f -p 80 -h /www" >/dev/null
kubectl -n shop rollout status deploy/api --timeout=120s >/dev/null
kubectl -n shop expose deploy api --name=api-svc --port=80 --target-port=80 >/dev/null
kubectl -n shop patch svc api-svc -p '{"spec":{"selector":{"app":"api-broken"}}}' >/dev/null
kubectl -n shop run client --image=busybox:1.36 --labels=app=client --command -- sleep 7200 >/dev/null   # verify 用测试 Pod

echo "==> [F3] shop/probe: 双探针指向不存在的 /ready (404 循环重启)"
kubectl -n shop create deploy probe --image=busybox:1.36 --replicas=1 -- sh -c "mkdir -p /www && echo probe-ok > /www/index.html && httpd -f -p 80 -h /www" >/dev/null
kubectl -n shop patch deploy probe --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"busybox","readinessProbe":{"httpGet":{"path":"/ready","port":80}},"livenessProbe":{"httpGet":{"path":"/ready","port":80}}}]}}}}' >/dev/null

echo "==> [F4] shop/data-claim: storageClassName 指向不存在的 SC (PVC/Pod 双 Pending)"
kubectl -n shop create -f - >/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-claim, namespace: shop}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
  storageClassName: faast
---
apiVersion: v1
kind: Pod
metadata: {name: data-user, namespace: shop}
spec:
  containers: [{name: u, image: busybox:1.36, command: ["sleep","3600"], volumeMounts: [{name: d, mountPath: /data}]}]
  volumes: [{name: d, persistentVolumeClaim: {claimName: data-claim}}]
EOF

echo "==> [F5] pay: default-deny + 放行规则端口写错 9999 (真实漏放行 8080)"
kubectl -n pay run cache --image=busybox:1.36 --labels=app=cache --port=8080 -- sh -c "mkdir -p /www && echo cache-ok > /www/index.html && httpd -f -p 8080 -h /www" >/dev/null
kubectl -n pay expose pod cache --name=cache-svc --port=80 --target-port=8080 >/dev/null
kubectl -n pay run client --image=busybox:1.36 --labels=app=client --command -- sleep 7200 >/dev/null
kubectl -n pay create -f - >/dev/null <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: cache-ingress, namespace: pay}
spec:
  podSelector: {matchLabels: {app: cache}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: client}}}]
    ports: [{protocol: TCP, port: 9999}]     # 端口写错：容器实际听 8080
EOF

kubectl -n shop rollout status deploy/api --timeout=60s >/dev/null 2>&1 || true
echo ""
echo "⚡ 注入完成，计时开始（60 分钟，每个故障 12 分钟封顶）。修复后跑:"
echo "   bash $(dirname "$0")/verify-30.sh $CTX"
