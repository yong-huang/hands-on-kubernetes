# CKA 开工包 · 项目 19：静态 PV/PVC 绑定与 Pod 挂载

> 对应清单：`docs/cka.md` 项目 19 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Create a PV `app-data` (1Gi, hostPath `/mnt/data`, ReadWriteOnce,
> reclaimPolicy Retain) and a PVC `app-claim` (500Mi) that binds to it. Mount
> the claim at `/usr/share/nginx/html` in a new nginx pod. Verify data
> survives pod deletion. (Weight: 5%)
>
> 目标用时：10 分钟

## ✅ 考场最优解（实测全过）

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: {name: app-data}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""            # 静态绑定的关键：空字符串
  hostPath: {path: /mnt/data}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: app-claim, namespace: apps}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 500Mi}}
  storageClassName: ""            # 与 PV 一致的空串才不会被动态供给截胡
  volumeName: app-data            # 静态指定，绑定零悬念
```

验证持久性（写 → 删 Pod → 重建 → 读回）：

```bash
kubectl exec nginx-pv -- sh -c "echo persisted-v1 > /usr/share/nginx/html/test.txt"
kubectl delete pod nginx-pv --now   # 重建同名/新 Pod 挂同一 PVC
kubectl exec <新pod> -- cat /usr/share/nginx/html/test.txt   # → persisted-v1 ✅
```

## 🧪 实测记录（2026-10-06）

- 绑定：PVC `Bound` → `app-data 1Gi RWO`（PVC 只要 500Mi，显示的是 PV 容量 1Gi——容量是"至少"语义）。
- 持久性：删 Pod 重建后 `persisted-v1` 读回 ✅。
- **Retain 语义实测**：删 PVC 后 PV 变 `Released`（保留数据、等待管理员介入），不会自动变 Available。

## ⚠️ 五大丢分点

1. **hostPath 的节点陷阱（本机实测设计）**：hostPath PV 不约束节点，Pod 换节点数据就"丢"。持久性验证时把新旧 Pod 钉同一节点（nodeSelector），或给 PV 加 nodeAffinity——考场多为单节点场景，但要知道原理。
2. **storageClassName 双侧都要空串**：只 PV 写 `""`、PVC 不写，PVC 会被默认 SC 动态供给抢走，永远不绑你的静态 PV。
3. **accessModes 语义**：RWO=单节点挂载（不是单 Pod！同节点多 Pod 可共用）；ROX/RWX 按节点数理解。
4. **reclaimPolicy 三态**：Retain（Released 等人管）/ Delete（PV 随 PVC 消失）/ 回收状态链 Available→Bound→Released→（Retain 手动删后）Failed。
5. **PVC 容量显示**：`kubectl get pvc` 的 CAPACITY 显示 PV 容量而非请求量；判分看 STATUS=Bound + 正确挂载，别被列值迷惑。

## 🧹 重练

```bash
kubectl -n apps delete pod/nginx-pv pvc/app-claim --now; kubectl delete pv app-data --now
```
