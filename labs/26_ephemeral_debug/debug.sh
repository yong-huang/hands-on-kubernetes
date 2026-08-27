#!/usr/bin/env bash
# =============================================================================
# 高级排障: Ephemeral Container / kubectl debug 三种姿势
#   1) container : 给无 shell 的崩溃容器挂工具箱 (ephemeral container)
#   2) copy      : 复制一份克隆 Pod 调试 (原 Pod 不动, 适合探针互斥场景)
#   3) node      : 节点级调试 (chroot 进宿主机文件系统)
# 生命周期: 临时容器不能 restart/暴露端口/探针, Pod 不重建则一直存在
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效
NS="debug-demo"
step() { echo; echo "=====> [$1] $2"; }

do_setup() {
    step "setup" "部署故障现场"
    kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f manifests/broken_pod.yaml
    sleep 5
    kubectl -n "$NS" get pods || true
}

do_container() {
    step "container" "姿势1a: CrashLoop 容器 + --target -> 真实世界的坑"
    kubectl -n "$NS" debug broken-app --image=busybox:1.36 \
        --target=app -- sh -c 'ps aux' 2>&1 | tail -1 || true
    echo "  ^ containerd 上 --target 要求目标容器处于 Running:"
    echo "    崩溃容器(Exit 状态)会 CreateContainerError。CrashLoop 的正确诊断"
    echo "    工具是 kubectl logs / describe, 或用姿势2的 --copy-to 改命令起克隆。"

    step "container" "姿势1b: 对 Running 的容器 --target -> 共享 PID 看进程与文件系统"
    kubectl -n "$NS" debug net-victim --image=busybox:1.36 \
        --target=app -- sh -c 'echo "== 看到 target 的进程 =="; ps | head -4;
                               echo "== 经 /proc/1/root 读 target 根文件系统 ==";
                               ls /proc/1/root/etc/ | head -3' || true
    echo "  ^ --target=app 后无需重启 Pod 即可注入工具箱(distroless 也能查)"

    step "container" "临时容器记录在 spec.ephemeralContainers"
    kubectl -n "$NS" get pod net-victim \
        -o jsonpath='{.spec.ephemeralContainers[*].name}'; echo
}

do_copy() {
    step "copy" "姿势2: 复制克隆 Pod 调试 (--copy-to, 原 Pod 保持原样)"
    # distroless 无 shell, 克隆时连镜像带命令一起换 (老版 --sleep-forever 已移除):
    # --container=app 定位原容器, --set-image 换镜像, 位置参数覆盖启动命令
    kubectl -n "$NS" debug broken-app --copy-to=broken-app-debug \
        --container=app --set-image=app=ubuntu:22.04 -- sh -c 'sleep infinity' || true
    kubectl -n "$NS" wait --for=condition=Ready pod/broken-app-debug --timeout=180s || true
    kubectl -n "$NS" exec broken-app-debug -- sh -c 'echo clone-ok; ls /etc | head -3' || true
    echo "  ^ 克隆 Pod 已常驻, 可 kubectl exec -it broken-app-debug -- bash 进入排查"
    # 打上 app=net-victim 标签: 让 deny-egress-all NetworkPolicy 也选中这个
    # 调试 Pod, 与原 net-victim 配对演示"断网现场 + 抓包诊断"
    kubectl -n "$NS" run net-victim-dbg --rm -it --restart=Never \
        -l app=net-victim --image=nicolaka/netshoot:v0.12 -- \
        nslookup kubernetes.default || true
    echo "  ^ netshoot 抓包/诊断工具箱: tcpdump dig traceroute mtr ..."
}

do_node() {
    step "node" "姿势3: 节点调试 (chroot 宿主机)"
    NODE=$(kubectl -n "$NS" get pod broken-app -o jsonpath='{.spec.nodeName}')
    echo "  目标节点: $NODE"
    echo "  命令: kubectl debug node/$NODE -it --image=ubuntu:22.04"
    echo "  进入后: chroot /host 可操作宿主机文件系统(systemctl/journalctl/ipvsadm)"
}

do_clean() { kubectl delete ns "$NS" --ignore-not-found; }

case "${1:-all}" in
    setup) do_setup ;; container) do_container ;; copy) do_copy ;;
    node)  do_node   ;; clean) do_clean ;;
    all)   do_setup; do_container ;;
esac
