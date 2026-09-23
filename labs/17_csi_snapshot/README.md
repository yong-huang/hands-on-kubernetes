# 17 · CSI 快照与还原：VolumeSnapshot、dataSource 与诚实预期

> 有了 PV/PVC 和动态供给，数据的"存放"问题解决了，但"出事怎么办"没有：误执行 `DELETE FROM`、发布引入数据损坏、想给生产库克隆一份测试环境——这些场景的共同需求是**把某一时刻的卷状态保存下来，需要时再变回一个可用的卷**。这就是 CSI Snapshot 的使命：备份、回滚、克隆，三个场景一套机制。

## What

CSI 快照完全照搬了 PV/PVC 的"用户侧/集群侧 + Class"双层设计：

```
VolumeSnapshot (namespaced) ←绑定→ VolumeSnapshotContent (集群级)
        ↑ 引用 Class                          ↑ 引用
VolumeSnapshotClass (driver + 参数)    CSI driver → 存储后端快照
```

- **VolumeSnapshot**：用户的快照请求，`spec.source.persistentVolumeClaimName` 指向要拍快照的 PVC
- **VolumeSnapshotContent**：集群级对象，对应存储后端里真实存在的那份快照（类比 PV）
- **VolumeSnapshotClass**：快照的"配方"（类比 StorageClass），`driver` 字段指定用哪个 CSI 驱动、`deletionPolicy` 决定删对象时是否连带删后端快照（Delete/Retain，语义同 reclaimPolicy）

一句话心智模型：**PV/PVC 设计模式在"时间维度"上的复刻**——三层对象对应 StorageClass/PVC/PV，`dataSource` 对应"从模板供给新卷"。判断快照是否真的存在的标准只有一个：`status.readyToUse: true`。

## Why

快照的特殊之处在于它**发生在存储后端**而不是 Pod 里：增量、秒级、不占用 Pod 的计算资源。相比"把数据拷出来"的土办法，快照由存储系统用 COW/ROW 机制在块设备层完成，应用无需停机、无需感知。要理解它，关键是搞清楚"谁实现了什么"——这正好也是 kind 集群上最容易踩的认知坑。

## How

```bash
cd labs/17_csi_snapshot
./snapshot.sh crd        # 安装 snapshot CRD + snapshot-controller（快照控制面）
./snapshot.sh deploy     # 源 PVC + 写入数据（tier=app）
./snapshot.sh snapshot   # 创建 VolumeSnapshot，轮询 readyToUse（kind 上会如实报告"永不 ready"）
./snapshot.sh restore    # 创建 dataSource 还原 PVC（kind 上如实展示一直 Pending）
./snapshot.sh verify     # 还原后的数据校验（云上/Longhorn 环境可完整跑通）
./snapshot.sh clean
```

manifest 按 `tier` 标签分层（`tier=app` / `tier=snapshot` / `tier=restore`，同 lab 12 的套路），脚本各步骤用 `kubectl apply -l tier=...` 分批生效。关键字段（`manifests/csi_snapshot.yaml`）：

```yaml
# VolumeSnapshotClass —— 快照配方
driver: rancher.io/local-path   # 必须与供给源 PVC 的驱动一致，local-path 不支持快照
deletionPolicy: Delete          # 删对象时连后端快照一起删; Retain 则保留

# VolumeSnapshot —— 快照请求
spec:
  volumeSnapshotClassName: snapclass-demo
  source:
    persistentVolumeClaimName: snap-source   # 对当前时刻的 PVC 拍快照

# 还原 PVC —— 新卷从快照诞生
spec:
  resources: { requests: { storage: 1Gi } }  # >= status.restoreSize
  dataSource:
    kind: VolumeSnapshot
    name: snap-demo
    apiGroup: snapshot.storage.k8s.io
```

`dataSource` 另有两种取值：`PersistentVolumeClaim`（直接克隆现有 PVC）、`VolumeSnapshotContent`（预置快照）。还原要求快照 `readyToUse: true`，且新 PVC 的 `storage >= restoreSize`；新 PVC Bound 后 Pod 挂载读到的就是快照时刻的数据。

## Deep Dive

**谁实现了快照接口**：这是最容易被误解的一点——**snapshot-controller 不做快照，它只做转发**。整个链路是：

1. 用户 apply VolumeSnapshot → snapshot-controller（来自 kubernetes-csi/external-snapshotter 项目）监听到
2. controller 找到 VolumeSnapshotClass 里 `driver` 指定的 CSI 驱动，调用它的 **CreateSnapshot gRPC 接口**（CSI 规范里的可选接口）
3. 驱动让存储后端创建快照（增量、秒级），回传 snapshotHandle
4. controller 创建 VolumeSnapshotContent 并绑定，回填 `status.readyToUse=true` 和 `restoreSize`

CRD 和 controller 是通用的（任何集群装一份即可），但**快照能力本身是 CSI 驱动的可选项**——驱动没实现，链路就在第 2 步断掉。

**kind 上为什么走不通（诚实预期）**：kind 默认 StorageClass `standard` 的 provisioner 是 `rancher.io/local-path`。它是一个极简供给器（往节点本地路径写目录），**没有实现 CSI 的 CreateSnapshot 接口**。于是：VolumeSnapshot 对象能创建成功（CRD 层面合法）、`status.readyToUse` **永远不会变成 true**（controller 找不到能处理的驱动）、用它做 dataSource 的还原 PVC 会一直 Pending。这不是故障，是能力边界——`snapshot.sh` 会轮询 30 秒后如实报告，并解释在 EBS/Longhorn/Ceph 上此时会发生什么。想在本地完整跑通，可以在 kind 里装 Longhorn 或用 `cloud-provider` 类方案。

**恢复为什么必须新建 PVC、不能原地灌回**：CSI 的 ProvisionFromSnapshot 语义是"从数据源供给新卷"——挂载中的卷原地覆盖数据一致性无法保证（文件系统/数据库可能持有句柄），而新 PVC 给了原子切换的机会：新 Pod 挂新卷验证无误后再切流。回滚 = 换卷，不是改卷。

## Q&A

**Q1: 快照和备份是一回事吗？**
不是。快照存在存储后端，通常是增量 COW/ROW 实现，创建秒级、空间省，但与源卷同生命周期、同故障域（存储阵列挂了快照也没了）；备份是把数据复制到独立介质，慢且占空间，但能对抗存储级故障。正确姿势是"快照保 RPO + 定期把快照导出到备份存储"。

**Q2: 快照数据到底存在哪？**
不在 etcd（那里只有 VolumeSnapshot/Content 这些元数据对象），不在节点，而在存储后端（EBS 快照、Ceph RBD snapshot、Longhorn 快照链）。`kubectl get volumesnapshot` 看到的只是后端快照的"句柄"。

**Q3: CSI 快照和 Velero 怎么分工？**
CSI 快照只管卷数据、同集群、秒级，不包含 Deployment/Service/ConfigMap 等 K8s 对象；Velero 备份"对象 + 数据"两层，能跨集群恢复、异地容灾，但通常更慢（见 lab 18）。生产常见组合：Velero 拉起对象，卷数据走 CSI 快照或对象存储插件（如 velero-plugin-for-aws 调 S3）。
