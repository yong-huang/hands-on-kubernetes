# CKA 开工包 · 项目 20：StorageClass 动态供给

> 对应清单：`docs/cka.md` 项目 20 ｜ 环境：kind 集群 `k8s-learn`（自带 local-path provisioner ✅）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Create a new StorageClass `fast` using the same provisioner as the
> existing default class, and make it the cluster default. Then create PVC
> `fast-claim` (1Gi) without specifying a storageClassName and confirm it
> binds dynamically. (Weight: 4%)
>
> 目标用时：8 分钟

## ✅ 考场最优解（实测全过）

```bash
# 1. 看现有默认 SC 的 provisioner（kind 自带 rancher.io/local-path）
kubectl get sc
# 2. 新建 fast 并设默认（换默认=一摘一戴两个 annotation）
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations: {storageclass.kubernetes.io/is-default-class: "true"}
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":null}}}'
# 3. 免 SC 名的 PVC → 动态供给
kubectl -n apps create deployment demo --image=busybox:1.36 -- sh -c "sleep 3600"  # 消费者
kubectl -n apps set volume deploy/demo --add --claim-name=fast-claim --mount-path=/data ...
# 或手写 PVC（不写 storageClassName）
```

## 🧪 实测记录（2026-10-06）

```
fast (default)   rancher.io/local-path   Delete   WaitForFirstConsumer   ← 新默认生效
PVC fast-claim（无 storageClassName）→ Bound pvc-589e1cdf…（fast）✅
Pod 写 /data/hello.txt 读回 dynamic-ok ✅
清场：删 PVC → 动态 PV 自动回收（Delete 策略，与 Retain 对照）
```

**volumeBindingMode 两种模式的实测差异**：
- `Immediate`：PVC 一创建立刻 Bound（PV 先行分配）。
- `WaitForFirstConsumer`（kind 默认）：PVC 创建后**一直 Pending**，直到消费它的 Pod 被调度才绑定——这样 PV 能跟着 Pod 落到同一拓扑域。**别把这种 Pending 误诊为故障**（项目 21 实测踩过）。

## ⚠️ 五大丢分点

1. **换默认是"一摘一戴"**：先把旧默认的 annotation patch 成 null，再给新 SC 戴上——集群里同时有两个默认 SC 时行为未定义，评分可能按错误算。
2. **annotation 键名**：`storageclass.kubernetes.io/is-default-class`（不是 `volume.beta.kubernetes.io/...` 老键）。
3. **provisioner 照抄现有**：题目说 "same provisioner as the existing default class"，先 `kubectl get sc` 再抄，别凭记忆写 `kubernetes.io/aws-ebs` 之类。
4. **PVC 不写 storageClassName ≠ 写空串**：不写=用默认 SC（动态）；写 `""`=只要静态 PV（项目 19）。一字之差两条题目路径，混淆必错。
5. **reclaimPolicy 是 SC 的属性**：动态供给的 PV 继承 SC 的 reclaimPolicy（Delete 默认）；想 Retain 得在 SC 里声明。

## 🧹 重练

```bash
kubectl -n apps delete pod/sc-user pvc/fast-claim --now
kubectl patch sc fast -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":null}}}'
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl delete sc fast --now
```
