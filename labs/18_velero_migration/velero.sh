#!/usr/bin/env bash
# =============================================================================
# Kubernetes 有状态应用迁移演示脚本 (Velero)
# 覆盖: 环境检查 -> 安装 Velero -> 部署有状态应用 -> 备份 -> 恢复到新 namespace -> 清理
# 用法: ./velero.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 backup)只执行该步骤
#
# 重要前提 (诚实声明):
#   Velero 必须有一个对象存储类型的 BackupStorageLocation (S3/MinIO/OSS...)
#   本机没有 S3 环境时, install/backup/restore 只打印"教学输出"不做真实操作。
#   设置以下环境变量即可切到真实模式:
#     VELERO_S3_BUCKET / VELERO_S3_REGION / VELERO_S3_ENDPOINT(可选, MinIO 用)
#
# 镜像预加载 (国内网络):
#   docker pull docker.io/velero/velero:v1.14.0
#   docker pull docker.io/velero/velero-plugin-for-aws:v1.10.0
#   ../../scripts/load_images.sh velero/velero:v1.14.0 \
#       velero/velero-plugin-for-aws:v1.10.0   # kind load 进集群 (无参调用只载默认清单, 不含 velero)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NS_SRC="velero-demo"                  # 源 namespace (被备份)
NS_DST="velero-demo-restored"         # 目标 namespace (恢复到新名字)
BACKUP="demo-backup"                  # 备份名
VELERO_NS="velero"                    # velero 自身所在 namespace
VELERO_VERSION="v1.14.0"              # CLI 与服务端版本保持一致

step() { echo; echo "=====> [$1] $2"; }

# velero CLI 是否可用
have_velero() { command -v velero >/dev/null 2>&1; }

# 真实模式: 需要 velero CLI + 用户提供了 S3 bucket
real_mode() {
    have_velero && [[ -n "${VELERO_S3_BUCKET:-}" ]]
}

# ----------------------------- 1. check -----------------------------
do_check() {
    step "check" "检查 velero CLI"
    if have_velero; then
        velero version --client-only 2>/dev/null || velero version || true
    else
        echo "未安装 velero CLI。安装方式:"
        echo "  brew install velero"
        echo "  或 GitHub release: https://github.com/vmware-tanzu/velero/releases"
        echo "  (下载 velero-${VELERO_VERSION}-darwin-amd64.tar.gz, 解压后放入 PATH)"
        echo "国内下载慢时可用 ghproxy 之类代理, 注意校验 checksum"
    fi

    step "check" "检查 velero 命名空间 (服务端是否已安装)"
    if kubectl get ns "${VELERO_NS}" >/dev/null 2>&1; then
        kubectl get pod -n "${VELERO_NS}" -o wide
        kubectl get backupstoragelocation -n "${VELERO_NS}" || true
    else
        echo "namespace ${VELERO_NS} 不存在, 服务端未安装 (执行 ./velero.sh install)"
    fi

    step "check" "检查运行模式"
    if real_mode; then
        echo "真实模式: VELERO_S3_BUCKET=${VELERO_S3_BUCKET}"
    else
        echo "学习模式 (无 S3 配置): install/backup/restore 只打印命令不执行"
    fi
}

# ----------------------------- 2. install -----------------------------
do_install() {
    step "install" "安装 Velero 服务端"
    if ! have_velero; then
        echo "velero CLI 未安装, 打印生产环境完整命令 (教学输出):"
        cat <<'EOF'
# --- 生产路径: S3/MinIO 对象存储 ---
# (注释单独成行: 行尾续行符 \ 后面不能再跟注释, 否则复制执行会报错)
# --use-node-agent                        DaemonSet: 文件系统备份
# --default-volumes-to-filesystem-backup  所有 PVC 默认走文件级备份
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket MY_BUCKET --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --use-node-agent \
  --default-volumes-to-filesystem-backup \
  --namespace velero
# MinIO 自建: 上面再加 --backup-location-config s3ForcePathStyle=true,s3Url=http://minio:9000
# (MinIO 需先建好 bucket, 并用 credentials 文件 --secret-file ./cloud-creds 传 AK/SK)
EOF
        return 0
    fi
    if [[ -z "${VELERO_S3_BUCKET:-}" ]]; then
        echo "检测到 velero CLI 但未设置 VELERO_S3_BUCKET, 走学习模式 (打印命令):"
        echo "  velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.10.0 \\"
        echo "    --bucket <name> --use-node-agent --default-volumes-to-filesystem-backup"
        return 0
    fi
    # 真实安装
    local extra=""
    [[ -n "${VELERO_S3_ENDPOINT:-}" ]] && \
        extra="s3ForcePathStyle=true,s3Url=${VELERO_S3_ENDPOINT}"
    velero install \
        --provider aws \
        --plugins "velero/velero-plugin-for-aws:v1.10.0" \
        --bucket "${VELERO_S3_BUCKET}" \
        --backup-location-config "region=${VELERO_S3_REGION:-us-east-1}${extra:+,${extra}}" \
        --use-node-agent \
        --default-volumes-to-filesystem-backup \
        --namespace "${VELERO_NS}"
    kubectl wait --for=condition=Ready -n "${VELERO_NS}" \
        pod -l deploy=velero --timeout=300s
    kubectl get backupstoragelocation -n "${VELERO_NS}"
}

# ----------------------------- 3. deploy -----------------------------
do_deploy() {
    step "deploy" "部署有状态应用 (StatefulSet + 动态 PVC)"
    kubectl apply -f manifests/velero_demo.yaml
    kubectl wait --for=condition=Ready -n "${NS_SRC}" \
        pod -l app=web --timeout=120s
    kubectl get pvc,pod -n "${NS_SRC}" -o wide

    step "deploy" "写入备份前的标记数据"
    kubectl exec web-0 -n "${NS_SRC}" -- \
        sh -c "echo marker-before-backup-$(date +%s) >> /data/marker.log; cat /data/marker.log"
}

# ----------------------------- 4. backup -----------------------------
do_backup() {
    step "backup" "备份整个 ${NS_SRC} namespace (API 对象 + PV 文件数据)"
    if ! real_mode; then
        echo "学习模式, 实际将执行 (教学输出):"
        echo "  velero backup create ${BACKUP} --include-namespaces ${NS_SRC} --wait"
        echo "  velero backup describe ${BACKUP} --details   # 看每个卷的备份状态"
        echo "  velero backup logs ${BACKUP}                  # 排错"
        return 0
    fi
    velero backup create "${BACKUP}" \
        --include-namespaces "${NS_SRC}" --wait
    step "backup" "查看备份详情 (关注 VOLUMES BACKED UP 与错误信息)"
    velero backup describe "${BACKUP}" --details
    velero backup logs "${BACKUP}" | tail -20 || true
}

# ----------------------------- 5. restore -----------------------------
do_restore() {
    step "restore" "恢复到新 namespace ${NS_DST} (namespace 映射 = 迁移)"
    if ! real_mode; then
        echo "学习模式, 实际将执行 (教学输出):"
        echo "  velero restore create restore-${BACKUP} \\"
        echo "    --from-backup ${BACKUP} --namespace-mappings ${NS_SRC}:${NS_DST} --wait"
        echo "  # 其他常用开关: --exclude-resources=events,endpoints"
        echo "  #            --selector app=web        (只恢复带标签的资源)"
        return 0
    fi
    velero restore create "restore-${BACKUP}" \
        --from-backup "${BACKUP}" \
        --namespace-mappings "${NS_SRC}:${NS_DST}" \
        --wait
    velero restore describe "restore-${BACKUP}" --details
    step "restore" "验证新 namespace 的数据"
    kubectl wait --for=condition=Ready -n "${NS_DST}" \
        pod -l app=web --timeout=120s
    kubectl exec web-0 -n "${NS_DST}" -- \
        sh -c "cat /data/marker.log && echo '--- 迁移成功: 备份前写入的标记文件已在新 namespace 出现 ---'"
}

# ----------------------------- 6. clean -----------------------------
do_clean() {
    step "clean" "删除演示资源 (源/恢复 namespace)"
    kubectl delete ns "${NS_SRC}" --ignore-not-found --wait=true
    kubectl delete ns "${NS_DST}" --ignore-not-found --wait=true
    if real_mode; then
        velero backup delete "${BACKUP}" --confirm 2>/dev/null || true
        velero restore delete "restore-${BACKUP}" --confirm 2>/dev/null || true
    else
        echo "(学习模式: 无备份/恢复对象可删; 想卸载 velero 服务端:"
        echo "  kubectl delete ns ${VELERO_NS}"
        echo "  kubectl delete crd -l app.kubernetes.io/name=velero)"
    fi
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        check)   do_check ;;
        install) do_install ;;
        deploy)  do_deploy ;;
        backup)  do_backup ;;
        restore) do_restore ;;
        clean)   do_clean ;;
        all)
            do_check; do_deploy
            echo "(install/backup/restore 依赖 S3 配置, all 模式不自动执行, 请单独运行)"
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: check | install | deploy | backup | restore | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
