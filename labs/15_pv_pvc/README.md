# 15 · PV/PVC：静态供给、绑定机制与回收策略

> 容器里的文件系统是易失的：Pod 一删，写在容器可写层里的数据就没了；哪怕只是 Pod 被调度到另一个节点，本地路径也对不上。Kubernetes 用 **PV/PVC 两层抽象**把"供给存储"和"申请存储"拆开，Pod 只认 PVC，完全不知道底层是 hostPath、local 盘还是云盘——计算与存储就此解耦。

## What

存储的消费链是一条引用链：

```
Pod（使用者）──引用──> PVC（申请单, namespace 级）──绑定──> PV（存储资源, 集群级）──> 实际存储(hostPath/local/云盘)
```

- **PV 是集群级资源**（不属于任何 namespace），生命周期独立于 Pod：Pod 删了 PV 还在，数据还在
- **PVC 是 namespace 级资源**，Pod 只能引用同 namespace 的 PVC
- 绑定由控制器完成：满足条件时 PV 从 `Available` 变为 `Bound`，并在 `spec.claimRef` 记下 PVC 的身份（一对一，独占）

PVC 的核心需求字段是 accessModes，三种模式：

| 模式 | 缩写 | 含义 | 典型后端 |
|------|------|------|----------|
| ReadWriteOnce | RWO | 同一时刻只允许**一个节点**挂载读写 | 块存储（云盘、local 盘） |
| ReadOnlyMany | ROX | 多节点同时只读 | 多副本读同一份数据 |
| ReadWriteMany | RWX | 多节点同时读写 | NFS、CephFS、EFS 等共享文件系统 |

注意 RWO 限制的是**节点**不是 Pod：同节点上的多个 Pod 可以共享一个 RWO 卷。accessModes 是 PV 的能力集，PVC 请求的是需求，绑定时要求 **PV 的模式 ⊇ PVC 的模式**。

## Why

朴素的办法是把数据直接塞进 hostPath，但这样 Pod 和节点路径强耦合，计算和存储没有分离：数据跟着节点走，节点坏了数据陪葬，扩缩容、迁移都束手束脚。PV/PVC 把存储拆成"供给"与"需求"两个角色，用绑定机制对接—— Pod 彻底与底层存储解耦，换存储后端只需换 PV 的来源，消费方一字不改。

## How

```bash
cd labs/15_pv_pvc
./pv.sh deploy    # 部署 PV(hostPath) + PVC + 挂载 Pod，观察 Available -> Bound
./pv.sh verify    # 删 Pod 重建：数据还在；写数据验证持久化
./pv.sh reclaim   # 删 PVC：PV 变 Released（Retain 策略），不会再被绑走
./pv.sh clean
```

关键字段（`manifests/pv_pvc.yaml`）：

```yaml
# PV（供给侧）
spec:
  capacity:
    storage: 1Gi                    # 容量：PVC 请求量必须 <= 它
  accessModes: [ReadWriteOnce]      # 能力集：必须包含 PVC 请求的模式
  persistentVolumeReclaimPolicy: Retain   # 删 PVC 后数据保留，手动清理
  storageClassName: manual          # 必须与 PVC 的一致才能静态绑定
  hostPath:
    path: /data/pv-demo             # kind 里位于节点容器内部，演示够用
  nodeAffinity:                     # local/hostPath 类 PV 的拓扑约束
    required:
      nodeSelectorTerms: [...]      # 限制使用该 PV 的 Pod 只能调度到数据所在节点

# PVC（需求侧）
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
  storageClassName: manual          # 留空 = 走默认 StorageClass（动态供给）

# Pod（使用侧）
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-demo           # 只引用 PVC，不感知 PV
```

## Deep Dive

**绑定三条件**：PV 控制器按 ① PV capacity ≥ PVC 请求量；② PV 的 accessModes 包含 PVC 请求的模式；③ storageClassName 一致（PVC 留空则用默认 SC，走动态供给）——匹配，此外 PVC 还可用 label selector 和 `volumeName` 进一步约束挑选范围。绑定是**即时消费**而非"预约"：即使后来出现更合适的 PV，已绑定的也不会迁移。

**生命周期状态机**：`Available → Bound → Released`，PVC 被删除后 PV 何去何从由 `persistentVolumeReclaimPolicy` 决定：

| 策略 | 删 PVC 后 PV 的状态 | 数据 | 说明 |
|------|---------------------|------|------|
| Retain | `Released`（≠ Available） | 保留 | 最安全；需管理员手动删 PV、清数据后才能重新供给 |
| Delete | 连同 PV 一起删除 | 删除 | 动态供给的默认值，依赖 CSI 插件执行真实删除 |
| Recycle | （已废弃） | 清空后回 Available | 旧版本会 `rm -rf /*`，已被动态供给取代 |

**Released 与 Available 的区别**是本实验的演示重点：Retain 下 PV 保留着旧 claimRef，不会再被新 PVC 绑走——这是防止数据被误接管的保护。

**静态供给 vs 动态供给**：静态（本实验）——管理员手动创建 PV（hostPath/local），PVC 靠 capacity/accessModes/storageClassName 匹配，`storageClassName: manual` 只是一个匹配标记，背后没有任何控制器；动态（生产默认）——只定义 StorageClass（指定 CSI driver 与参数），PVC 创建后控制器按需自动创建 PV 并绑定，PVC 删除时按 reclaimPolicy 自动回收（见 lab 16）。

**PV 的节点亲和性**：hostPath/local 类存储只存在于特定节点，PV 的 `nodeAffinity` 把"数据在哪"这个拓扑约束交给调度器：调度器把 PV 的 nodeAffinity 与 Pod 的资源请求合并过滤节点，保证 Pod 落在能挂到这块存储的节点上。没有它，Pod 可能调度到无数据的节点导致挂载失败。

踩坑清单：

- PVC 请求量大于所有可用 PV 的 capacity 时会一直 `Pending`（没有 StorageClass 时不会自动扩出 PV）
- `local` 类型 PV 必须配 `nodeAffinity`（K8s 强制），否则连创建都不过；hostPath PV 不强制，但若数据只存在于部分节点，仍应配 `nodeAffinity` 引导 Pod 调度到有数据的节点
- PV 的 capacity 只是声明值，hostPath 并不会真的限额——配额由底层存储实现（如云盘、LVM）

## Q&A

**Q1: PVC 比 PV 小，怎么绑？**
绑定要求是 capacity ≥ request，所以 500Mi 的 PVC 可以绑到 1Gi 的 PV 上，但整块 PV 被独占，剩余容量浪费（且不给退款）；多个小 PVC 会各自绑不同 PV。生产上用动态供给按需创建精确大小的 PV 来避免浪费。

**Q2: StatefulSet 的 volumeClaimTemplates 和直接写 PVC 有什么区别？**
直接 PVC 是 Pod 模板里引用同一个 PVC（Deployment 常用，所有副本共享、无身份）；volumeClaimTemplates 为**每个副本自动生成独立的 PVC**（`data-web-0`、`data-web-1`...），副本重建后仍绑定回自己原来的 PVC，从而获得"稳定存储身份"——这正是有状态应用的核心需求（见 lab 08）。缩容时 PVC 保留（扩容回来数据还在），需手动删除。
