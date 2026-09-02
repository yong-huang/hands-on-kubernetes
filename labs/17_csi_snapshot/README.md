# Kubernetes CSI 快照与还原：VolumeSnapshot、dataSource 与 kind 上的诚实预期

## 1. 引言

有了 PV/PVC 和动态供给，数据的"存放"问题解决了，但"出事怎么办"没有：误执行 `DELETE FROM`、发布引入数据损坏、想给生产库克隆一份测试环境——这些场景的共同需求是**把某一时刻的卷状态保存下来，需要时再变回一个可用的卷**。这就是 CSI Snapshot 的使命：备份、回滚、克隆，三个场景一套机制。

快照的特殊之处在于它**发生在存储后端**而不是 Pod 里：增量、秒级、不占用 Pod 的计算资源。要理解它，关键是搞清楚"谁实现了什么"——这正好也是 kind 集群上最容易踩的认知坑。

## 2. 文件结构

```
17_csi_snapshot/
├── README.md               # 本文档
├── snapshot.sh             # 分步演示: crd | deploy | snapshot | restore | verify | clean
├── manifests/
│   └── csi_snapshot.yaml   # PVC+Pod / VolumeSnapshotClass / VolumeSnapshot / 还原 PVC
└── images/
    ├── snapshot_chain.architecture.json  # 图源（Archify Typed JSON IR）
    ├── snapshot_chain.html               # 交互版架构图
    └── snapshot_chain.svg                # 双主题矢量版（本文档 §6 内嵌）
```

## 3. 核心概念

### 三层 CRD 体系

CSI 快照完全照搬了 PV/PVC 的"用户侧/集群侧 + Class"双层设计：

```
VolumeSnapshot (namespaced) ←绑定→ VolumeSnapshotContent (集群级)
        ↑ 引用 Class                          ↑ 引用
VolumeSnapshotClass (driver + 参数)    CSI driver → 存储后端快照
```

- **VolumeSnapshot**：用户的快照请求，`spec.source.persistentVolumeClaimName` 指向要拍快照的 PVC
- **VolumeSnapshotContent**：集群级对象，对应存储后端里真实存在的那份快照（类比 PV）
- **VolumeSnapshotClass**：快照的"配方"（类比 StorageClass），`driver` 字段指定用哪个 CSI 驱动、`deletionPolicy` 决定删对象时是否连带删后端快照（Delete/Retain，语义同 reclaimPolicy）

### 谁实现了快照接口

这是最容易被误解的一点：**snapshot-controller 不做快照，它只做转发**。整个链路是：

1. 用户 apply VolumeSnapshot → snapshot-controller（来自 kubernetes-csi/external-snapshotter 项目）监听到
2. controller 找到 VolumeSnapshotClass 里 `driver` 指定的 CSI 驱动，调用它的 **CreateSnapshot gRPC 接口**（CSI 规范里的可选接口）
3. 驱动让存储后端创建快照（增量、秒级），回传 snapshotHandle
4. controller 创建 VolumeSnapshotContent 并绑定，回填 `status.readyToUse=true` 和 `restoreSize`

CRD 和 controller 是通用的（任何集群装一份即可），但**快照能力本身是 CSI 驱动的可选项**——驱动没实现，链路就在第 2 步断掉。

### kind 上为什么走不通（诚实预期）

kind 默认 StorageClass `standard` 的 provisioner 是 `rancher.io/local-path`。它是一个极简供给器（往节点本地路径写目录），**没有实现 CSI 的 CreateSnapshot 接口**。于是：

- VolumeSnapshot 对象能创建成功（CRD 层面合法）
- `status.readyToUse` **永远不会变成 true**（controller 找不到能处理的驱动）
- 用它做 dataSource 的还原 PVC 会一直 Pending

这不是故障，是能力边界。manifest 按 `tier` 标签分层（`tier=app` / `tier=snapshot` / `tier=restore`，同 lab 12 的套路），脚本各步骤用 `kubectl apply -l tier=...` 分批生效：`deploy` 只装源数据，`snapshot` 只装快照对象，`restore` 才 apply 还原 PVC（并在 kind 上如实展示它一直 Pending）。`snapshot.sh snapshot` 会轮询 30 秒后如实报告，并解释在 EBS/Longhorn/Ceph 上此时会发生什么；想在本地完整跑通，可以在 kind 里装 Longhorn 或用 `cloud-provider` 类方案。

### dataSource 还原

还原就是创建一个新 PVC，`spec.dataSource` 指明数据来源：

```yaml
dataSource:
  kind: VolumeSnapshot              # 另两种: PersistentVolumeClaim(克隆), VolumeSnapshotContent
  name: snap-demo
  apiGroup: snapshot.storage.k8s.io # kind 为 VolumeSnapshot 时必须写
```

控制器从快照 clone 出一个新卷，新 PVC Bound 后 Pod 挂载读到的就是快照时刻的数据。要求快照 `readyToUse: true`，且新 PVC 的 `storage >= restoreSize`。

## 4. YAML 关键字段

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

## 5. 可视化

![CSI 快照链路](images/snapshot_chain.svg)

图中①-⑦是完整链路：apply VolumeSnapshot → snapshot-controller 转发 → CSI 驱动执行 CreateSnapshot → 存储后端生成快照并回填 handle → VolumeSnapshotContent 绑定；还原走 ⑤-⑦：新 PVC 以 dataSource 引用快照 → clone 出新卷 → 新 Pod 挂新卷。CSI 驱动节点上标出了 **kind local-path 的能力断点**——没有 CreateSnapshot 实现，链路在②断掉，readyToUse 永远不会变 true。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/17_csi_snapshot/images/snapshot_chain.html)（或本地打开 [`images/snapshot_chain.html`](images/snapshot_chain.html)）。

## 6. 面试要点

1. **快照 vs 备份**：快照存在存储后端，通常是增量 COW/ROW 实现，创建秒级、空间省，但与源卷同生命周期、同故障域（存储阵列挂了快照也没了）；备份是把数据复制到独立介质，慢且占空间，但能对抗存储级故障。正确姿势是"快照保 RPO + 定期把快照导出到备份存储"。
2. **快照存在哪**：不在 etcd（那里只有 VolumeSnapshot/Content 这些元数据对象），不在节点，而在存储后端（EBS 快照、Ceph RBD snapshot、Longhorn 快照链）。`kubectl get volumesnapshot` 看到的只是后端快照的"句柄"。
3. **恢复为什么必须新建 PVC、不能原地灌回**：CSI 的 ProvisionFromSnapshot 语义是"从数据源供给新卷"——挂载中的卷原地覆盖数据一致性无法保证（文件系统/数据库可能持有句柄），而新 PVC 给了原子切换的机会：新 Pod 挂新卷验证无误后再切流。回滚 = 换卷，不是改卷。
4. **与 Velero 的分工**：CSI 快照只管卷数据、同集群、秒级，不包含 Deployment/Service/ConfigMap 等 K8s 对象；Velero 备份"对象 + 数据"两层，能跨集群恢复、异地容灾，但通常更慢。生产常见组合：Velero 拉起对象，卷数据走 CSI 快照或对象存储插件（如 velero-plugin-for-aws 调 S3）。
5. **VolumeSnapshotContent 和 deletionPolicy=Retain 的场景**：删除 namespaced 的 VolumeSnapshot 时想保留后端快照（比如 namespace 整体销毁但数据要留档），用 Retain——controller 只删 K8s 对象，后端快照及 Content 需手动清理，语义与 PV 的 Retain 一致。

## 7. 总结

CSI 快照体系 = PV/PVC 设计模式在"时间维度"上的复刻：VolumeSnapshotClass/VolumeSnapshot/VolumeSnapshotContent 三层对应 StorageClass/PVC/PV，dataSource 对应"从模板供给新卷"。核心认知是**能力分层**：CRD + snapshot-controller 是通用控制面（人人可装），CreateSnapshot 是驱动的可选实现（EBS/Longhorn/Ceph 有，kind local-path 没有）——所以"对象创建成功"绝不等于"快照真的存在"，判断标准只有一个：`status.readyToUse: true`。配合 `snapshot.sh` 在 kind 上亲眼看到"永远不 ready"的诚实演示，比在云上一次跑通记得更牢。
