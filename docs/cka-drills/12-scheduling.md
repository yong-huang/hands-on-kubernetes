# CKA 开工包 · 项目 12：定向调度——nodeName、taint/toleration 与 affinity

> 对应清单：`docs/cka.md` 项目 12 ｜ 环境：kind 集群 `k8s-learn`（3 节点）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。本题实测撞上 YAML 1.1 「Norway 问题」，见丢分点 2。

## 📝 题面（考场原题风格）

> `Task:` Schedule a pod `fixed` onto node `worker2` directly via `nodeName`.
> Create another pod `flexible` that lands on any node labeled `disk=ssd`,
> preferring `zone=east`. Give `worker2` taint `special=true:NoSchedule`
> and ensure only `fixed` can tolerate it. (Weight: 5%)
>
> 目标用时：12 分钟

## ✅ 考场最优解（实测全过）

```bash
kubectl label node k8s-learn-worker2 disk=ssd zone=east
kubectl taint node k8s-learn-worker2 special=true:NoSchedule

# fixed：nodeName 绕过调度器直派（仍然要写 toleration 才能落在 taint 节点上？
# 否！nodeName 直派不走调度器，taint 不拦它；但考场稳妥起见两者都写）
# flexible：required 硬性 disk=ssd + preferred 软性 zone=east + toleration
# no-tol：只有 nodeSelector、没有容忍 → 负例
```

核心 YAML（flexible）：

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - {key: disk, operator: In, values: [ssd]}
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions: [{key: zone, operator: In, values: [east]}]
  tolerations:
  - {key: special, operator: Equal, value: "true", effect: NoSchedule}
```

## 🧪 实测结果（2026-10-06）

```
fixed      Running   k8s-learn-worker2   ← nodeName 直派成功
flexible   Running   k8s-learn-worker2   ← required+preferred 命中
no-tol     Pending   <none>              ← 被拒
# 拒绝事件：1 node(s) didn't match Pod's node affinity/selector,
#           2 node(s) had untolerated taint(s)
```

注意事件语义：no-tol 事件里 **2 个节点都报 untolerated taint**——因为控制面节点本就有 `node-role.kubernetes.io/control-plane:NoSchedule`，没有容忍的业务 Pod 在任何 CKA 集群里都天生进不了控制面。

## ⚠️ 五大丢分点

1. **operator 忘写 Exists 场景**：taint `special=true` 用 Equal 必须带 `value: "true"`；若题目 taint 无值或用 Exists，toleration 不能带 value。
2. **YAML 1.1 Norway 问题（实测踩到）**：单字母 `name: n` 被 YAML 1.1 解析成布尔 `false`（n/N/no/y/yes/on/off 同理），apiserver 报 `cannot unmarshal bool into ... field Container.name of type string`。给容器名加引号或用正常名字。
3. **nodeName 与 affinity 的本质差异**：nodeName 绕过调度器（不校验资源/taint/亲和）；affinity 走调度器全量过滤。概念题高频。
4. **preferred 结构记不住**：`preferredDuringSchedulingIgnoredDuringExecution` 是 **weight + preference** 对象数组，weight 1-100；required 才是 nodeSelectorTerms。
5. **affinity 的 IgnoredDuringExecution 语义**：节点标签后来变了，已调度 Pod 不迁移——「Ignored」指运行期，概念题常考。

## 🧹 重练

```bash
kubectl -n apps delete pod fixed flexible no-tol --now
kubectl label node k8s-learn-worker2 disk- zone-
kubectl taint node k8s-learn-worker2 special=true:NoSchedule-
```
