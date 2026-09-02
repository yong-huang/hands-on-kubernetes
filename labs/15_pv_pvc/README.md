# Kubernetes PV/PVC 详解：静态供给、绑定机制与回收策略

## 1. 引言

容器里的文件系统是易失的：Pod 一删，写在容器可写层里的数据就没了；哪怕只是 Pod 被调度到另一个节点，本地路径也对不上。朴素的办法是把数据直接塞进 hostPath，但这样 Pod 和节点路径强耦合，计算和存储没有分离。

Kubernetes 的解法是 **PV/PVC 两层抽象**：管理员用 PersistentVolume 声明"集群里有哪些存储"（供给侧），用户用 PersistentVolumeClaim 声明"我需要什么样的存储"（需求侧），控制器负责把二者**绑定**。Pod 只引用 PVC，完全不知道底层是 hostPath、local 盘还是云盘——计算与存储就此解耦。

## 2. 文件结构

```
15_pv_pvc/
├── README.md            # 本文档
├── pv.sh                # 全流程演示脚本: deploy/verify/reclaim/clean
├── manifests/
│   └── pv_pvc.yaml      # PV(hostPath) + PVC + 挂载 Pod + 带节点亲和性的第二个 PV
└── images/
    ├── pvc_binding.architecture.json  # 图源（Archify Typed JSON IR）
    ├── pvc_binding.html               # 交互版架构图
    └── pvc_binding.svg                # 双主题矢量版（本文档 §可视化 内嵌）
```

## 3. 核心概念

### PV 与 PVC 的关系

```
Pod（使用者）──引用──> PVC（申请单, namespace 级）──绑定──> PV（存储资源, 集群级）──> 实际存储(hostPath/local/云盘)
```

- **PV 是集群级资源**（不属于任何 namespace），生命周期独立于 Pod：Pod 删了 PV 还在，数据还在
- **PVC 是 namespace 级资源**，Pod 只能引用同 namespace 的 PVC
- 绑定由控制器完成：满足条件时 PV 从 `Available` 变为 `Bound`，并在 `spec.claimRef` 记下 PVC 的身份（一对一，独占）
- 绑定是**即时消费**而非"预约"：即使后来出现更合适的 PV，已绑定的也不会迁移

### accessModes 三种模式

| 模式 | 缩写 | 含义 | 典型后端 |
|------|------|------|----------|
| ReadWriteOnce | RWO | 同一时刻只允许**一个节点**挂载读写 | 块存储（云盘、local 盘） |
| ReadOnlyMany | ROX | 多节点同时只读 | 多副本读同一份数据 |
| ReadWriteMany | RWX | 多节点同时读写 | NFS、CephFS、EFS 等共享文件系统 |

注意 RWO 限制的是**节点**不是 Pod：同节点上的多个 Pod 可以共享一个 RWO 卷。accessModes 是 PV 的能力集，PVC 请求的是需求，绑定时要求 **PV 的模式 ⊇ PVC 的模式**。

### 回收策略对比

PVC 被删除后，PV 何去何由 `persistentVolumeReclaimPolicy` 决定：

| 策略 | 删 PVC 后 PV 的状态 | 数据 | 说明 |
|------|---------------------|------|------|
| Retain | `Released`（≠ Available） | 保留 | 最安全；需管理员手动删 PV、清数据后才能重新供给 |
| Delete | 连同 PV 一起删除 | 删除 | 动态供给的默认值，依赖 CSI 插件执行真实删除 |
| Recycle | （已废弃） | 清空后回 Available | 旧版本会 `rm -rf /*`，已被动态供给取代 |

**Released 与 Available 的区别**是本项目的演示重点：Retain 下 PV 保留着旧 claimRef，不会再被新 PVC 绑走——这是防止数据被误接管的保护。

### 静态供给 vs 动态供给

- **静态供给（本项目）**：管理员手动创建 PV（hostPath/local），PVC 靠 capacity/accessModes/storageClassName 匹配。`storageClassName: manual` 只是一个匹配标记，背后没有任何控制器
- **动态供给（生产默认）**：只定义 StorageClass（指定 CSI driver 与参数），PVC 创建后控制器按需自动创建 PV 并绑定；PVC 删除时按 reclaimPolicy 自动回收。PVC 里留空 `storageClassName` 即使用默认 StorageClass

## 4. YAML 关键字段

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

几个易踩的坑：

- PVC 请求量大于所有可用 PV 的 capacity 时会一直 `Pending`（没有 StorageClass 时不会自动扩出 PV）
- `local` 类型 PV 必须配 `nodeAffinity`（K8s 强制），否则连创建都不过；hostPath PV 不强制，但若数据只存在于部分节点，仍应配 `nodeAffinity` 引导 Pod 调度到有数据的节点，避免挂载失败
- PV 的 capacity 只是声明值，hostPath 并不会真的限额——配额由底层存储实现（如云盘、LVM）

## 5. 可视化

![PV/PVC 绑定](images/pvc_binding.svg)

静态绑定链路：Pod 用 `claimName` 引用 PVC → PV 控制器按**三条件**（capacity ≥、accessModes ⊇、storageClassName =）匹配 → 绑定为一对一独占（写 claimRef）→ PV 挂到实际存储（本例 hostPath）。Pod 全程不感知底层是 hostPath、local 盘还是云盘。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/15_pv_pvc/images/pvc_binding.html)（或本地打开 [`images/pvc_binding.html`](images/pvc_binding.html)）。

## 6. 面试要点

1. **PVC 和 PV 的绑定条件有哪些**：① PV capacity ≥ PVC 请求量；② PV 的 accessModes 包含 PVC 请求的模式；③ storageClassName 一致（PVC 留空则用默认 SC，走动态供给）；此外 PVC 还可用 label selector 和 `volumeName` 进一步约束挑选范围。绑定一对一独占，记录在 PV 的 claimRef 里。
2. **Retain vs Delete 的语义**：Retain——删 PVC 后 PV 进入 Released，数据和 claimRef 保留，需管理员手动删 PV 并清数据才能复用，最安全；Delete——PV 连同底层存储一起删（动态供给默认），依赖 CSI 插件。Released 不是 Available，不会再被自动绑走。
3. **PVC 比 PV 小怎么绑**：绑定要求是 capacity ≥ request，所以 500Mi 的 PVC 可以绑到 1Gi 的 PV 上，但整块 PV 被独占，剩余容量浪费（且不给退款）；多个小 PVC 会各自绑不同 PV。生产上用动态供给按需创建精确大小的 PV 来避免浪费。
4. **PV 的节点亲和性是干什么的**：hostPath/local 类存储只存在于特定节点，PV 的 `nodeAffinity` 把"数据在哪"这个拓扑约束交给调度器：调度器把 PV 的 nodeAffinity 与 Pod 的资源请求合并过滤节点，保证 Pod 落在能挂到这块存储的节点上。没有它，Pod 可能调度到无数据的节点导致挂载失败。
5. **StatefulSet 的 volumeClaimTemplates 和直接写 PVC 有什么区别**：直接 PVC 是 Pod 模板里引用同一个 PVC（Deployment 常用，所有副本共享、无身份）；volumeClaimTemplates 为**每个副本自动生成独立的 PVC**（`data-web-0`、`data-web-1`...），副本重建后仍绑定回自己原来的 PVC，从而获得"稳定存储身份"——这正是有状态应用的核心需求。缩容时 PVC 保留（扩容回来数据还在），需手动删除。

## 7. 总结

PV/PVC 的本质是把存储拆成"供给"与"需求"两个角色，用绑定机制把二者对接，让 Pod 彻底与底层存储解耦。记住三条主线：绑定三条件（capacity/accessModes/storageClass）、生命周期状态机（Available → Bound → Released 及 Retain/Delete 两条出路）、静态 vs 动态供给（manual 标记 vs StorageClass+CSI）。配合 `pv.sh` 里"删 Pod 数据还在、删 PVC 变 Released"的演示，能直观感受到"数据属于 PV 而不属于 Pod"这一设计意图。
