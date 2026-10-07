# CKA 开工包 · 项目 21：PVC 排障与卷快照恢复

> 对应清单：`docs/cka.md` 项目 21 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。**快照段本机离线不可行**（见末尾），排障段完整实测。

## 📝 题面（考场原题风格）

> `Task:` PVC `data-claim` in namespace `apps` is stuck Pending — diagnose and
> fix it so it binds. Then take a snapshot `data-snap` of the bound PVC and
> restore it into a new PVC `data-restored`; verify the restored volume
> contains the original data. (Weight: 5%)
>
> 目标用时：12 分钟

## ✅ 排障段：两级 Pending，两种修法（实测全过）

```bash
# 注入故障：SC 名拼错
kubectl -n apps patch ... # 创建 PVC 时 storageClassName: faast

# 第一级诊断：STORAGECLASS 列显示一个"不存在"的名字
kubectl -n apps get pvc data-claim    # Pending  faast
kubectl -n apps get sc | grep faast   # 无输出 → 根因

# 修复尝试①：patch —— 直接被 apiserver 拒（⚠️ 头号考点）
kubectl -n apps patch pvc data-claim -p '{"spec":{"storageClassName":"standard"}}'
# Error: spec is immutable after creation except resources.requests ...
# 正确修法②：删了重建（未绑定过的 PVC 无数据风险）
kubectl -n apps delete pvc data-claim --now
# 重建（storageClassName: standard）→ 仍 Pending？
```

**第二级 Pending**：修复 SC 后 PVC 依然 Pending 不是没修好——kind 的 standard SC 是
`WaitForFirstConsumer`，**创建消费它的 Pod 后才 Bound**：

```bash
kubectl -n apps run data-user --image=busybox:1.36 --command -- sleep 3600 \
  --overrides='...volumes: [{name: d, persistentVolumeClaim: {claimName: data-claim}}]'
kubectl -n apps get pvc data-claim   # Bound pvc-4acd5ac8… ✅
```

## ⚠️ 五大丢分点

1. **PVC spec 基本不可变（实测撞墙）**：`storageClassName`、`accessModes` 建后即锁，patch 直接 Forbidden；只有 `resources.requests` 可扩。修配置型 PVC 故障 = 删了重建。
2. **WaitForFirstConsumer 的 Pending 是正常态**：先看 SC 的 `VOLUMEBINDINGMODE` 列再下结论；"没有消费者"和"没有 provisioner"是两种 Pending。
3. **诊断顺序**：`get pvc`（看 SC 列）→ `get sc`（名字对不对）→ `describe pvc`（事件；注意 local-path 场景事件可能为空，别等事件）→ `get pods`（有没有消费者）。
4. **SC 不存在时事件静默**：没有 provisioner 认领的 PVC 不一定报事件，列名比对比等事件快。
5. **RWO 消费者约束**：同一 PVC 的消费者 Pod 先起会卡在 PVC 未 Bound（跨 SC 模式），先修 PVC 再起消费 Pod 是稳态顺序。

## ❌ 快照段：本机离线不可行（环境实测）

- VolumeSnapshot CRD 与 snapshot-controller 的官方清单托管在 GitHub（直连被墙，labs/17 本地缓存仅 113 行 demo、无 CRD/控制器）。
- kind 自带 local-path provisioner **不支持 CSI 快照**，即使装了 controller 也没有可用的 snapshot 后端。
- **fallback**：① killercoda 的 CSI/snapshot 场景（联网环境，考点覆盖）；② 考前在 kubernetes.io 文档通读 VolumeSnapshot 三对象（VolumeSnapshotClass/VolumeSnapshot/dataSource 恢复模板）；③ 本清单项目 21 验收标准中快照部分按"理解字段+能背模板"完成，实操留待 killercoda。

## 🧹 重练

```bash
kubectl -n apps delete pod/data-user pvc/data-claim --now
# 重做：故意把 SC 写成不存在的名字 → 走完两级排障
```
