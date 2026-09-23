# 18 · Velero：有状态应用的备份与跨集群迁移

> 存储的"生前"问题（PV/PVC 绑定、动态供给、CSI 快照）解决之后，真实运维还有一个生死攸关的问题：**这台集群没了（升级/迁移/故障），我的数据库和它几十个 PVC 怎么办？** `kubectl apply` 只能重建"无状态"的那半边——Deployment、Service 这些 YAML 可以从 Git 里再来一遍，但 PV 里的数据不在 Git 里。

## What

Velero（原 Heptio Ark，现归 VMware Tanzu）把一个 namespace 的 **API 对象和 PV 数据一起打包到对象存储**，之后随时在任意集群恢复——它是"集群级 rsync + 时间机器"，也是跨集群迁移的标准工具。

一次 `velero backup create` 实际做两件事，两条数据平面：

1. **API 对象面**：velero controller（Deployment，单副本）watch 并导出目标范围内的所有 K8s 对象（Deployment/StatefulSet/Service/ConfigMap/PVC 定义...），打成 tarball 上传。这一步只依赖 API server，与存储类型无关。
2. **PV 数据面**，两条路线：

| 路线 | 机制 | 适用 |
|------|------|------|
| 文件系统备份（node agent） | 每节点一个 DaemonSet（restic/kopia 后端）把 PVC 挂载路径下的文件打包上传 | **通用性最好**，kind/自建/任何存储都能用，跨集群迁移的主力 |
| CSI 快照 | 调 VolumeSnapshot 走存储驱动的块级快照 | 速度最快，但快照留在**原存储系统**里，跨集群读不到，只适合同集群 PITR（lab 17 的主题） |

文件系统备份的启用方式：安装时加 `--use-node-agent` + `--default-volumes-to-filesystem-backup` 让所有 PVC 默认走这条路，或在 Pod 上打注解 `backup.velero.io/backup-volumes: "data"`。

## Why

`kubectl apply` 是声明式的，但它声明的只是期望状态，不搬运数据。数据库、消息队列这些有状态应用的业务数据活在 PV 里，集群升级失败、迁移、区域故障时，"对象能重建、数据回不来"等于灾难恢复只做了一半。Velero 把"应用 + 数据"整体搬进对象存储这个中立地带，restore 用 namespace mapping 还能顺手完成跨集群/跨环境迁移。

## How

```bash
cd labs/18_velero_migration
./velero.sh check    # 前置检查（CLI、kind 集群、镜像）
./velero.sh install  # 安装 velero（学习模式：无 S3 时只打印教学输出，不假装成功）
./velero.sh deploy   # 部署 StatefulSet + volumeClaimTemplates 演示应用
./velero.sh backup   # 创建备份（学习模式演示命令与预期输出）
./velero.sh restore  # 恢复到新 namespace（--namespace-mappings）
./velero.sh clean
```

关键字段（`manifests/velero_demo.yaml`）：

```yaml
# StatefulSet 的身份三件套
spec:
  serviceName: web                  # headless service, 提供 web-0.web... DNS
  volumeClaimTemplates:             # 每副本独立 PVC: data-web-0, data-web-1
    - metadata: { name: data }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 128Mi } }  # kind 默认 SC 动态供给

# Pod 模板注解: 告诉 node agent 备份哪些卷
metadata:
  annotations:
    backup.velero.io/backup-volumes: "data"
```

**国内网络注意**：镜像 `docker.io/velero/velero`、`velero/velero-plugin-for-aws`、node agent 镜像都在 docker.io，kind 环境先 `docker pull` 再用 `../../scripts/load_images.sh` 灌进节点；CLI 用 `brew install velero` 或 GitHub release 下载（darwin-amd64/arm64 tar.gz），release 下载慢可走代理但务必核对 checksum；CLI 版本与服务端保持一致（本实验按 v1.14）；对象存储可用 OSS 的 S3 兼容端点或自建 MinIO（`--backup-location-config s3ForcePathStyle=true,s3Url=http://minio:9000`）。

**真实模式（本地 S3 兼容对象存储）**：本机起一个 S3 兼容服务（ObjStor/MinIO/LocalStack 均可）后：

```bash
# 1. 起对象存储并建 bucket (任何 S3 兼容服务均可: ObjStor/MinIO/LocalStack)
aws --endpoint-url http://localhost:3020 s3api create-bucket --bucket velero

# 2. 写凭据文件后安装 (kind 节点经 host.docker.internal/宿主机 IP 访问 S3)
cat > /tmp/velero-creds <<'EOF2'
[default]
aws_access_key_id=test-access-key
aws_secret_access_key=test-secret-key
EOF2
velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.14.0 \
  --bucket velero \
  --backup-location-config region=us-east-1,s3ForcePathStyle=true,s3Url=http://<宿主机可达地址>:3020 \
  --secret-file /tmp/velero-creds \
  --use-node-agent --default-volumes-to-fs-backup -n velero --wait

# 3. 真实模式跑本脚本
VELERO_S3_BUCKET=velero VELERO_S3_ENDPOINT=http://<宿主机可达地址>:3020 ./velero.sh all
```

## Deep Dive

**恢复语义：namespace mapping 是迁移的灵魂**。`velero restore create --from-backup demo-backup --namespace-mappings velero-demo:velero-demo-restored` 会把备份里所有 namespace 级对象改名后在新 namespace 重建；PVC 被重新动态供给，node agent 再把文件数据灌回去——`web-0` 的新 PVC 里出现了备份前写入的 `marker.log`，迁移闭环。其他常用开关：`--exclude-resources events,endpoints`（垃圾对象不要恢复）、`--selector app=web`（只恢复带标签的子集）、`--existing-resource-policy update`（目标已存在时是覆盖还是跳过）。

**生产对象存储**：Velero 必须有一个 BackupStorageLocation，**只认 S3 协议**：AWS S3、自建 MinIO、阿里 OSS（S3 兼容端点）都行。本机 kind 演习时通常没有 S3，`velero.sh` 的诚实做法是：没配 `VELERO_S3_BUCKET` 时只打印教学输出，不做假装成功的真实操作。

**node agent 怎么读到别的 Pod 的卷**：DaemonSet 在每个节点上以宿主挂载 `/var/lib/kubelet/pods`，通过 volumeMount 找到同节点 Pod 的 PVC 实际路径，直接读文件——所以它**不需要业务 Pod 配合**，但要求 Pod 的卷落在 agent 所在节点（DaemonSet 覆盖所有节点即满足）。

**真实模式实测结果（2026-08，kind v1.36 + velero 1.18 + ObjStor）**：

- backup `Completed`（0 错误）：API 对象 + 备份产物全部落入对象存储
  （`backups/demo-backup/*.tar.gz`、`velero-backup.json` 等齐套）；
- restore `Completed`：14 个对象恢复到 `velero-demo-restored`，Pod 重建、
  PVC 重新绑定，namespace 映射（velero-demo → velero-demo-restored）生效。

**已知环境限制（如实说明）**：kind 默认 StorageClass（local-path）创建的 PV
底层是 hostPath，**velero 会拒绝对其做文件级备份**（日志：
"Volume data in pod … is a hostPath volume which is not supported for pod
volume backup"），因此 PVC 里的业务数据（marker.log）不会随恢复带过去。
要完整演示卷数据迁移，需要 CSI 类存储驱动（或云盘）；本实验在 kind 上
验证的是 API 对象迁移 + 对象存储链路。

**踩坑记录（对 S3 兼容实现方也有参考价值）**：

1. S3 端点选宿主机可达地址（`host.docker.internal` 宿主机自身不解析，
   用局域网 IP；`velero backup logs` 在宿主机读日志也走该端点）；
2. kopia（node-agent 的备份引擎）用 `STREAMING-AWS4-HMAC-SHA256-PAYLOAD`
   分块上传——S3 兼容层必须解码 aws-chunked 帧，否则 blob 全部 403；
3. kopia 靠 `list-objects-v2?prefix=` 枚举索引——prefix 过滤必须实现，
   否则把格式 blob 当索引解析直接报 "blob id too short"；
4. `backup.velero.io/backup-volumes` 必须是 **annotation**——写成 label 时
   velero 静默跳过卷备份（本实验曾踩）；
5. 备份失败会在 bucket 留下半个 kopia repo，重试前需清 bucket 前缀 +
   删 `backuprepositories` CR，否则 "found existing data in storage location"。

## Q&A

**Q1: Velero、CSI 快照、etcd 备份怎么分工？**
Velero——应用级（按 namespace/label），API 对象 + 文件级卷数据，可跨集群，恢复粒度细；CSI 快照——存储级，同集群同存储的快速 PITR，不能跨存储厂商（lab 17）；etcd 备份——整集群最后手段（`etcdctl snapshot save`），恢复即回滚整个控制面，无应用粒度，且不含容器镜像/外部数据。

**Q2: 跨集群迁移的完整步骤是什么？**
目标集群装 Velero 并指向**同一个** BackupStorageLocation → `velero backup create --include-namespaces X --wait`（确认 Completed、无 volume 错误）→ 目标集群 `velero restore create --from-backup ... --namespace-mappings` → 验证 Pod Ready 与数据 → 切流量（DNS/Ingress）。前提：两边 StorageClass 名字匹配（可在 restore 时 `--snapshot-move-data` 或改 SC）。

**Q3: hooks 是干什么的？**
备份一致性。`pre` hook 在备份前执行（如 `pg_dump`、`FLUSH TABLES WITH READ LOCK`、fsync），`post` hook 在完成后解锁——文件级备份抓的是"正在写的文件"，数据库不 quiesce 可能拿到不一致的页。

**Q4: RTO/RPO 怎么算？**
RPO 取决于备份频率（`velero schedule create daily --schedule="0 2 * * *"` 即每日一份，RPO ≤ 24h；持续数据要靠应用层复制）；RTO ≈ 恢复对象 + 重供给 PVC + 回灌文件数据的时间，大 PVC 文件级恢复最慢——生产上"小 RTO"场景用 CSI 快照或 Volume Data Mover。
