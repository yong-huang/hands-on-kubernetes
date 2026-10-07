#!/usr/bin/env bash
# 考官专用：T16 控制面故障注入（考生做到最后一题时执行）
set -euo pipefail
kubectl config use-context kind-k8s-learn >/dev/null
docker exec k8s-learn-control-plane mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/exam-scheduler.yaml
sleep 10
kubectl -n kube-system get pods -o name | grep -c kube-scheduler | xargs echo "scheduler 剩余 pod 数:"
echo "⚡ T16 故障已注入：集群新 Pod 将永远 Pending。恢复由考生完成（判分见 grade.sh）。"
