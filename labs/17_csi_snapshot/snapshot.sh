#!/usr/bin/env bash
# =============================================================================
# CSI 快照与还原演示脚本
# 覆盖: 装 CRD/controller -> 部署源数据(tier=app) -> 创建快照(tier=snapshot)
#    -> 还原演示(tier=restore) -> 诚实验证 -> 清理
# 用法: ./snapshot.sh [step]   (crd | deploy | snapshot | restore | verify | clean | all)
#
# 诚实预期: kind 默认 SC "standard" 是 rancher.io/local-path, 未实现 CSI
# 快照接口, VolumeSnapshot 永远不会 readyToUse。脚本会检测并解释,
# 而不是假装成功。生产环境 (EBS/Longhorn/Ceph...) 行为见 verify 步骤说明。
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

NAMESPACE="default"
PVC="snap-source"
POD="snap-source-pod"
SNAP="snap-demo"
SNAPCLASS="snapclass-demo"
BASE_RAW="https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0"
# github raw 下载不稳时的备用源 (jsdelivr CDN):
BASE_CDN="https://cdn.jsdelivr.net/gh/kubernetes-csi/external-snapshotter@v8.2.0"
# controller 镜像 registry.k8s.io/sig-storage/snapshot-controller:v8.2.0
# -> 先用 ../../scripts/load_images.sh 预载到 kind 节点, 否则拉取可能超时

step() { echo; echo "=====> [$1] $2"; }

# 检测 PVC 供给驱动是否支持快照 (local-path 不支持)
driver_of_pvc() {
    local sc
    sc=$(kubectl get pvc "${PVC}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    [[ -n "${sc}" ]] || return 0
    kubectl get sc "${sc}" -o jsonpath='{.provisioner}' 2>/dev/null || echo ""
}

# ----------------------------- 1. 安装 CRD + snapshot-controller -----------------------------
do_crd() {
    step "crd" "安装 VolumeSnapshot 等 CRD (github raw, 失败自动换 jsdelivr CDN)"
    for f in volumesnapshotclasses volumesnapshots volumesnapshotcontents; do
        kubectl apply -f "${BASE_RAW}/client/config/crd/snapshot.storage.k8s.io_${f}.yaml" \
            || kubectl apply -f "${BASE_CDN}/client/config/crd/snapshot.storage.k8s.io_${f}.yaml"
    done

    step "crd" "部署 snapshot-controller (v8.x 清单固定装在 kube-system)"
    # 若 PullImage 失败: ../../scripts/load_images.sh registry.k8s.io/sig-storage/snapshot-controller:v8.2.0
    # v8.x 清单拆成 rbac + setup 两个文件 (旧单文件路径已 404),
    # 且 Deployment/RBAC 的 metadata 里写死了 namespace: kube-system
    CTRL_NS="kube-system"
    for f in rbac-snapshot-controller.yaml setup-snapshot-controller.yaml; do
        kubectl apply -f "${BASE_RAW}/deploy/kubernetes/snapshot-controller/${f}" \
            || kubectl apply -f "${BASE_CDN}/deploy/kubernetes/snapshot-controller/${f}"
    done
    kubectl -n "${CTRL_NS}" rollout status deploy/snapshot-controller --timeout=120s

    step "crd" "确认 CRD 就绪"
    kubectl get crd | grep volumesnapshot
}

# ----------------------------- 2. 部署源数据 -----------------------------
do_deploy() {
    step "deploy" "创建 PVC + Pod (tier=app), 并写入将被快照的标记数据"
    # 只 apply app 层: 快照/还原文档由各自步骤单独 apply, 避免
    # deploy 阶段就冒出一个永远 Pending 的还原 PVC
    kubectl apply -l tier=app -f manifests/csi_snapshot.yaml
    kubectl wait "pod/${POD}" -n "${NAMESPACE}" \
        --for=condition=Ready --timeout=90s
    kubectl exec "${POD}" -n "${NAMESPACE}" -- cat /data/marker.txt
    kubectl get pvc "${PVC}" -n "${NAMESPACE}"
    echo "(供给驱动: $(driver_of_pvc))"
}

# ----------------------------- 3. 创建快照并诚实轮询 -----------------------------
do_snapshot() {
    step "snapshot" "创建 VolumeSnapshotClass + VolumeSnapshot (tier=snapshot)"
    kubectl apply -l tier=snapshot -f manifests/csi_snapshot.yaml
    kubectl get volumesnapshotclass "${SNAPCLASS}"

    step "snapshot" "轮询快照状态 (最多 30s)"
    local ready=false i
    for i in $(seq 1 15); do
        local val
        val=$(kubectl get volumesnapshot "${SNAP}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "")
        if [[ "${val}" == "true" ]]; then ready=true; break; fi
        sleep 2
    done
    kubectl get volumesnapshot "${SNAP}" -n "${NAMESPACE}" -o wide || true

    if [[ "${ready}" == true ]]; then
        echo "快照 readyToUse=true, 可执行 verify 还原流程"
        return
    fi
    # ---- 诚实降级: 解释 local-path 限制 ----
    cat <<'EOF'
[!] readyToUse 永远不会变 true —— 这不是故障, 是预期行为:

    本 PVC 由 rancher.io/local-path (kind 默认 SC) 供给, 该 provisioner
    是最简化的 in-tree 风格供给器, 没有实现 CSI 的 CreateSnapshot gRPC 接口。
    snapshot-controller 监听到 VolumeSnapshot 后, 找不到能处理它的驱动,
    status 停留在空/False。

    在支持快照的驱动上 (EBS/Longhorn/Ceph RBD/Portworx...), 此时会发生:
      1. controller 调用驱动的 CreateSnapshot
      2. 存储后端创建增量快照 (秒级, 不复制全量数据)
      3. 生成集群级 VolumeSnapshotContent 并与 VolumeSnapshot 绑定
      4. status.readyToUse=true, restoreSize=1Gi

    排查命令: kubectl describe volumesnapshot snap-demo   (看 Events)
              kubectl -n kube-system logs deploy/snapshot-controller
EOF
}

# ----------------------------- 4. 验证/说明还原 -----------------------------
do_verify() {
    local ready
    ready=$(kubectl get volumesnapshot "${SNAP}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "")

    if [[ "${ready}" == "true" ]]; then
        step "verify" "支持的驱动上: 还原 PVC 应已由 restore 步骤创建, 对比数据"
        kubectl wait pvc/snap-restored -n "${NAMESPACE}" \
            --for=jsonpath='{.status.phase}'=Bound --timeout=120s \
            || { kubectl describe pvc snap-restored -n "${NAMESPACE}"; return 1; }
        kubectl exec "${POD}" -n "${NAMESPACE}" -- cat /data/marker.txt
        kubectl get pvc snap-restored -n "${NAMESPACE}" \
            -o jsonpath='{.spec.dataSource}'; echo
    else
        step "verify" "local-path 上无法真正还原 —— 打印还原 manifest 并讲解"
        cat <<'EOF'
还原清单 (csi_snapshot.yaml 第 4 段, restore 步骤会真正 apply 它):

    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata: { name: snap-restored }
    spec:
      storage: 1Gi                # 必须 >= 快照的 status.restoreSize
      storageClassName: <同源SC>
      dataSource:
        kind: VolumeSnapshot      # 另支持 PVC 克隆 / VolumeSnapshotContent
        name: snap-demo
        apiGroup: snapshot.storage.k8s.io

流程: 新 PVC(dataSource) -> 存储控制器从快照 clone 出新卷 -> 新 PV Bound。
在本集群 apply 它只会得到一个永远 Pending 的 PVC (事件报驱动不支持
ProvisionFromSnapshot), 因为 local-path 没实现对应 CSI 接口 —— 这本身
就是一次很好的错误演练 (restore 步骤可现场观察)。
EOF
    fi
}

# ----------------------------- 4.5 应用还原 PVC (tier=restore) -----------------------------
do_restore() {
    step "restore" "apply 还原 PVC (tier=restore, dataSource 指向快照)"
    # 诚实话术: 在 kind 的 local-path 上, 这个 PVC 会一直 Pending
    # (驱动未实现 ProvisionFromSnapshot), 属预期错误演练; 在支持快照的
    # 驱动上它会被从快照还原并 Bound
    kubectl apply -l tier=restore -f manifests/csi_snapshot.yaml
    kubectl get pvc snap-restored -n "${NAMESPACE}" -o wide || true
    echo "(local-path 上预期一直 Pending; 事件可用 kubectl describe pvc snap-restored 查看)"
}

# ----------------------------- 5. 清理 -----------------------------
do_clean() {
    step "clean" "删除快照/还原 PVC/Pod (deletionPolicy=Delete 时连后端快照一起删)"
    kubectl delete volumesnapshot "${SNAP}" -n "${NAMESPACE}" --ignore-not-found || true
    kubectl delete -f manifests/csi_snapshot.yaml --ignore-not-found --wait=true || true
    kubectl get volumesnapshot,pvc -n "${NAMESPACE}" || true
}

# ----------------------------- 入口 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        crd)      do_crd ;;
        deploy)   do_deploy ;;
        snapshot) do_snapshot ;;
        restore)  do_restore ;;
        verify)   do_verify ;;
        clean)    do_clean ;;
        all)      do_crd; do_deploy; do_snapshot; do_restore; do_verify; do_clean ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: crd | deploy | snapshot | restore | verify | clean | all" >&2
            exit 1 ;;
    esac
}
main "$@"
