# CKA 开工包 · 项目 6：节点维护——cordon、drain 与 taint

> 对应清单：`docs/cka.md` 项目 6 ｜ 环境：kind 集群 `k8s-learn`（3 节点，v1.36.1）｜ 实测日期：2026-10-06
> 本机已完整实测 drain→taint→uncordon 全流程（原以为必须 killercoda，实测 kind 3 节点即可）。先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Prepare node `worker1` for maintenance: drain it ignoring DaemonSet-managed pods,
> then add label `disk=ssd` and taint `maintenance=true:NoSchedule`.
> After maintenance, uncordon the node. (Weight: 4%)
>
> 目标用时：8 分钟

## ✅ 考场最优解

```bash
kubectl drain k8s-learn-worker2 --ignore-daemonsets --delete-emptydir-data
kubectl label node k8s-learn-worker2 disk=ssd
kubectl taint node k8s-learn-worker2 maintenance=true:NoSchedule
# （做题目要求的验证）
kubectl uncordon k8s-learn-worker2
```

## 🧪 实测记录（2026-10-06）

**drain 效果**：9 个业务 Pod 全部驱逐重建到其他节点，节点进入 `Ready,SchedulingDisabled`，残留仅 DaemonSet：

```
evicting pod default/nginx-85b9b8c477-7b6wc ...（共 9 个）
k8s-learn-worker2   Ready,SchedulingDisabled   <none>   22d   v1.36.1
# worker2 上剩余：kube-system/kindnet、kube-system/kube-proxy（均为 DaemonSet）
```

**taint 反例**（nodeSelector 钉到该节点、无容忍）→ Pending，一条事件把 3 个节点各拒一次的原因全说清：

```
FailedScheduling: 0/3 nodes are available:
  1 node(s) didn't match Pod's node affinity/selector,   ← worker（没标签）
  1 node(s) had untolerated taint(s),                    ← worker2（maintenance taint）
  1 node(s) were unschedulable                           ← 控制面（cordon/自身 taint）
```

**⚠️ 考场经典陷阱（实测踩到）**：带容忍的 Pod 在 uncordon 前依然 Pending——**toleration 只豁免 taint，不豁免 cordon**（cordon 是另一层 `spec.unschedulable` 开关）。uncordon 后立即 `Running` 落到 worker2。

**清理**（恢复集群供后续项目使用）：

```bash
kubectl delete pod taint-test no-toleration with-toleration --now
kubectl label node k8s-learn-worker2 disk-
kubectl taint node k8s-learn-worker2 maintenance=true:NoSchedule-
```

## ⚠️ 五大丢分点

1. **忘 `--ignore-daemonsets`**：drain 会因 DaemonSet-owned Pod 卡死并报 `cannot delete Pods managed by DaemonSet`，考试时间白烧。
2. **裸 Pod 没加 `--force`**：无控制器的 Pod 默认拒驱。考场先 `kubectl get pods -A -o wide` 看目标节点有没有裸 Pod，题面说 ignore DaemonSet 之外还提 bare pods 就加 `--force`。
3. **effect 选错**：`NoExecute` 会立刻赶走节点上已运行的 Pod（等于二次 drain）；维护场景题目写的是 `NoSchedule` 就照抄，别自作主张。
4. **cordon/taint 混为一谈**：两者都是「不让调度」，但 toleration 只对 taint 生效。若验收 Pod 一直 Pending，先查节点是否还 `SchedulingDisabled`。
5. **做完不恢复**：题目要求 uncordon 就必须 uncordon，评分表按最终状态打分；本机练习同理，taint/label 用 `kubectl taint node <n> key-` 和 `kubectl label node <n> key-` 减号回收。

## 🧹 重练

```bash
# 直接重跑上面「考场最优解」+ 正反验证两个 Pod；最后按清理段恢复原状
```
