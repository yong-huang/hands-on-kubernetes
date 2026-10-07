#!/usr/bin/env bash
# CKA 全真模考 #1 · 环境准备（幂等，可重考）——T16 由考官单独注入
set -euo pipefail

echo "==> [k8s-learn] 通用素材与命名空间"
kubectl config use-context kind-k8s-learn >/dev/null

# T2 素材：主 kubeconfig 拷贝 + 外来 staging-config
mkdir -p /tmp/exam
kubectl config view --minify --flatten --context kind-k8s-learn > /tmp/exam/config
kubectl config view --minify --flatten --context kind-ai-infra > /tmp/exam/staging-config

for ns in audit secure ops apps ing store; do
  kubectl create ns $ns --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

# T4/T7 前置重置：worker2 无目标标签/taint（考生自己加）
kubectl label node k8s-learn-worker2 disk- >/dev/null 2>&1 || true
kubectl label node k8s-learn-worker2 special- >/dev/null 2>&1 || true
kubectl taint node k8s-learn-worker2 special=true:NoSchedule- >/dev/null 2>&1 || true
kubectl -n ops create deployment ds-demo --image=busybox:1.36 --replicas=2 -- sh -c "sleep 3600" >/dev/null 2>&1 || true

# T5 素材：fe @ nginx:1.25
kubectl -n apps create deployment fe --image=nginx:1.25 --replicas=3 >/dev/null 2>&1 || true
kubectl -n apps rollout status deploy/fe --timeout=180s >/dev/null

# T8 素材：api2 监听 8080
kubectl -n apps create deployment api2 --image=busybox:1.36 --replicas=2 \
  -- sh -c "mkdir -p /www && echo api2-ok > /www/index.html && httpd -f -p 8080 -h /www" >/dev/null 2>&1 || true

# T10 素材：svc-a / svc-b
kubectl -n ing create deployment svc-a --image=busybox:1.36 --replicas=1 \
  -- sh -c "mkdir -p /www && echo content-a > /www/index.html && httpd -f -p 80 -h /www" >/dev/null 2>&1 || true
kubectl -n ing create deployment svc-b --image=busybox:1.36 --replicas=1 \
  -- sh -c "mkdir -p /www && echo content-b > /www/index.html && httpd -f -p 80 -h /www" >/dev/null 2>&1 || true
kubectl -n ing expose deployment svc-a --name=svc-a --port=80 --target-port=80 >/dev/null 2>&1 || true
kubectl -n ing expose deployment svc-b --name=svc-b --port=80 --target-port=80 >/dev/null 2>&1 || true
kubectl -n ing rollout status deploy/svc-a --timeout=120s >/dev/null
kubectl -n ing rollout status deploy/svc-b --timeout=120s >/dev/null

# T14 故障：PVC 指向不存在的 SC + 消费 Pod 在场
kubectl -n store delete pod store-user pvc data-claim --ignore-not-found --now >/dev/null
kubectl -n store apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-claim, namespace: store}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
  storageClassName: faast
---
apiVersion: v1
kind: Pod
metadata: {name: store-user, namespace: store}
spec:
  containers: [{name: u, image: busybox:1.36, command: ["sleep","3600"], volumeMounts: [{name: d, mountPath: /data}]}]
  volumes: [{name: d, persistentVolumeClaim: {claimName: data-claim}}]
EOF

# T13 故障：四大状态
kubectl create ns broken --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n broken delete pod --all --ignore-not-found >/dev/null
kubectl apply -f "$(dirname "$0")/../scripts/chaos-22.yaml" >/dev/null

# T12/T11 前置清理（考生自己创建）
kubectl -n apps delete pvc/dyn-pvc pvc/exam-pvc pod/pv-user --ignore-not-found >/dev/null
kubectl delete pv exam-pv --ignore-not-found >/dev/null
kubectl delete sc exam-fast --ignore-not-found >/dev/null
DSC=$(kubectl get sc -o json | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name' | head -1)
if [ "$DSC" != "standard" ] && [ -n "$DSC" ]; then
  kubectl patch sc "$DSC" -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":null}}}' >/dev/null
  kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null
fi

echo "==> [cka-netpol] T9 / T15 故障与素材"
kubectl config use-context kind-cka-netpol >/dev/null
kubectl create ns np-exam --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n np-exam delete pod,svc,netpol --all --ignore-not-found >/dev/null
kubectl -n np-exam run api --image=busybox:1.36 --labels=app=api --port=80 -- sh -c "mkdir -p /www && echo api-ok > /www/index.html && httpd -f -p 80 -h /www" >/dev/null
kubectl -n np-exam run client --image=busybox:1.36 --labels=app=client --command -- sleep 7200 >/dev/null
kubectl -n np-exam run other --image=busybox:1.36 --command -- sleep 7200 >/dev/null
kubectl -n np-exam expose pod api --name=api-svc --port=80 --target-port=80 >/dev/null

kubectl create ns pay --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n pay delete pod,svc,netpol --all --ignore-not-found >/dev/null
kubectl -n pay run cache --image=busybox:1.36 --labels=app=cache --port=8080 -- sh -c "mkdir -p /www && echo cache-ok > /www/index.html && httpd -f -p 8080 -h /www" >/dev/null
kubectl -n pay expose pod cache --name=cache-svc --port=80 --target-port=9090 >/dev/null     # 故障①
kubectl -n pay run client --image=busybox:1.36 --labels=app=client --command -- sleep 7200 >/dev/null
kubectl -n pay create -f - >/dev/null <<'EOF'                                                # 故障②
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: cache-ingress, namespace: pay}
spec:
  podSelector: {matchLabels: {app: cache}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: client}}}]
    ports: [{protocol: TCP, port: 9999}]
EOF

kubectl -n np-exam wait --for=condition=Ready pod --all --timeout=180s >/dev/null
kubectl -n pay wait --for=condition=Ready pod --all --timeout=180s >/dev/null
kubectl config use-context kind-k8s-learn >/dev/null
echo "✅ 模考环境就绪。考试：docs/cka-drills/mock-1/EXAM.md ｜ 判分：bash grade.sh"
