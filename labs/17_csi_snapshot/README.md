# 17 · CSI 快照与还原：VolumeSnapshot、dataSource 与诚实预期

> 有了 PV/PVC 和动态供给，数据的"存放"问题解决了，但"出事怎么办"没有：误执行 `DELETE FROM`、发布引入数据损坏、想给生产库克隆一份测试环境——这些场景的共同需求是**把某一时刻的卷状态保存下来，需要时再变回一个可用的卷**。这就是 CSI Snapshot 的使命：备份、回滚、克隆，三个场景一套机制。读完本篇，你将分清"CRD 控制面"与"驱动实现"的能力分层，并理解为什么 kind 上快照永远不 ready。

## Background

数据出事后的传统补救是把备份拷回来：从备份机拖全量数据、停服、覆盖、重启——RTO（恢复耗时）以小时计。而块存储系统其实早就内置了更快的机制：快照（snapshot）在存储后端用写时复制（COW/ROW）实现，增量、秒级、不占用计算资源。

问题在于各家存储的快照接口互不相同。CSI Snapshot 把它标准化成 K8s API：VolumeSnapshot 是声明式请求，快照的创建与还原都走统一的 CRD（自定义资源）流程——应用不需要知道后端是 EBS、Ceph 还是 Longhorn。

理解它的关键是搞清"谁实现了什么"，这也是 kind 集群上最容易踩的认知坑。

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

## When to Use

典型场景：发布前的数据保险（拍快照，出问题秒回）；给测试环境克隆一份生产数据（dataSource 克隆）；定期快照 + 导出到备份存储的混合策略。

何时不用：对抗存储级故障（快照与源卷同故障域，阵列挂了快照也没了——那要备份，见 lab 18）；跨集群迁移（快照留在原存储系统，目标集群读不到）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 快照 | 秒级、增量、同故障域 | 误操作回滚、克隆环境 |
| 备份（Velero 等） | 独立介质、慢、跨集群 | 容灾、长期保留 |
| 数据库自带备份（pg_dump） | 应用层一致性最好 | 数据库优先用应用层工具 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/17_csi_snapshot
./snapshot.sh crd        # 安装 snapshot CRD + snapshot-controller（快照控制面）
./snapshot.sh deploy     # 源 PVC + 写入数据（tier=app）
./snapshot.sh snapshot   # 创建 VolumeSnapshot，轮询 readyToUse（kind 上会如实报告"永不 ready"）
./snapshot.sh restore    # 创建 dataSource 还原 PVC（kind 上如实展示一直 Pending）
./snapshot.sh verify     # 还原后的数据校验（云上/Longhorn 环境可完整跑通）
./snapshot.sh clean
```

诚实预期：kind 默认的 local-path 供给器不支持快照，`snapshot` 步骤会轮询 30 秒后如实报告 `readyToUse` 永远不变 true——这是能力边界演示，不是脚本故障；想在本地完整跑通可在 kind 里装 Longhorn。

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

`dataSource` 另有两种取值：`PersistentVolumeClaim`（直接克隆现有 PVC）、`VolumeSnapshotContent`（预置快照）。

还原要求快照 `readyToUse: true`，且新 PVC 的 `storage >= restoreSize`；新 PVC Bound 后 Pod 挂载读到的就是快照时刻的数据。

## How It Works

**谁实现了快照接口**：这是最容易被误解的一点——**snapshot-controller 不做快照，它只做转发**。整个链路是：

1. 用户 apply VolumeSnapshot → snapshot-controller（来自 kubernetes-csi/external-snapshotter 项目）监听到
2. controller 找到 VolumeSnapshotClass 里 `driver` 指定的 CSI 驱动，调用它的 **CreateSnapshot gRPC 接口**（CSI 规范里的可选接口）
3. 驱动让存储后端创建快照（增量、秒级），回传 snapshotHandle
4. controller 创建 VolumeSnapshotContent 并绑定，回填 `status.readyToUse=true` 和 `restoreSize`

CRD 和 controller 是通用的（任何集群装一份即可），但**快照能力本身是 CSI 驱动的可选项**——驱动没实现，链路就在第 2 步断掉。你在 `snapshot` 步骤看到的"永远不 ready"，断点就在这里：kind 的 local-path 驱动没有 CreateSnapshot 实现。

**恢复为什么必须新建 PVC、不能原地灌回**：CSI 的 ProvisionFromSnapshot 语义是"从数据源供给新卷"——挂载中的卷原地覆盖数据一致性无法保证（文件系统/数据库可能持有句柄），而新 PVC 给了原子切换的机会：新 Pod 挂新卷验证无误后再切流。回滚 = 换卷，不是改卷。

## Pitfalls & Q&A

踩坑清单：

- "对象创建成功"不等于"快照真的存在"——判断标准只有 `status.readyToUse: true`。
- VolumeSnapshotClass 的 `driver` 必须与源 PVC 的供给驱动一致，否则链路找不到能处理的驱动。
- `deletionPolicy: Delete` 下删 VolumeSnapshot 会连带删后端快照：namespace 整体销毁但数据要留档的场景用 `Retain`（controller 只删 K8s 对象，后端快照需手动清理，语义与 PV 的 Retain 一致）。

**Q1: 快照和备份是一回事吗？**
不是。快照存在存储后端，通常是增量 COW/ROW 实现，创建秒级、空间省，但与源卷同生命周期、同故障域（存储阵列挂了快照也没了）；备份是把数据复制到独立介质，慢且占空间，但能对抗存储级故障。正确姿势是"快照保 RPO（可容忍的数据丢失窗口）+ 定期把快照导出到备份存储"。

**Q2: 快照数据到底存在哪？**
不在 etcd（那里只有 VolumeSnapshot/Content 这些元数据对象），不在节点，而在存储后端（EBS 快照、Ceph RBD snapshot、Longhorn 快照链）。`kubectl get volumesnapshot` 看到的只是后端快照的"句柄"。

**Q3: CSI 快照和 Velero 怎么分工？**

CSI 快照只管卷数据、同集群、秒级，不包含 Deployment/Service/ConfigMap 等 K8s 对象；Velero 备份"对象 + 数据"两层，能跨集群恢复、异地容灾，但通常更慢（见 lab 18）。

生产常见组合：Velero 拉起对象，卷数据走 CSI 快照或对象存储插件（如 velero-plugin-for-aws 调 S3）。
