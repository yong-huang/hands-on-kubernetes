# CKA 开工包 · 项目 9：应用伸缩与资源限制对调度的影响

> 对应清单：`docs/cka.md` 项目 9 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Scale deployment `web` in namespace `apps` to 5 replicas.
> Then create a pod `heavy` with a CPU request of `4` — it should stay
> Pending. Explain why by inspecting its scheduling events. (Weight: 3%)
>
> 目标用时：8 分钟

## ✅ 考场最优解

```bash
kubectl -n apps scale deploy web --replicas=5
kubectl -n apps rollout status deploy/web --timeout=180s       # 期望 5/5

# heavy Pod（考场节点小，4 CPU 即可复现 Pending）
kubectl run heavy -n apps --image=busybox:1.36 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"containers":[{"name":"heavy","image":"busybox:1.36","command":["sleep","3600"],"resources":{"requests":{"cpu":"4"}}}]}}'
kubectl -n apps describe pod heavy | grep -A2 FailedScheduling  # 事件里找 Insufficient cpu
```

## 🧪 实测记录（2026-10-06）

本机节点可分配 CPU 是 **18 核/节点**（`kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu`），
4 CPU 装得下，所以改用 **64 CPU** 复现同款故障：

```
web   2/5 ... →（片刻后 5/5）          ← scale 立即生效，扩容节奏由 strategy 控制

Warning  FailedScheduling  default-scheduler
0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu.
```

事件三段式拆解：3 个节点各有各的拒绝理由——这跟项目 6 的 taint 事件是同一套读法。

## ⚠️ 五大丢分点

1. **只在 spec 里写 limits 不写 requests**：**调度只看 requests**，limits 影响运行时限额/驱逐；两者都可单写。
2. **不会反查容量**：`kubectl describe node <n>` 的 `Allocated resources` 段 + `-o jsonpath='{.status.allocatable.cpu}'` 是判断「为什么装不下」的标准动作。
3. **Pending 归因单一化**：Pending ≠ 一定缺资源，事件里可能是 taint/亲和/PVC，**必须引用事件原文**作答。
4. **scale 与 rollout 混淆**：`scale` 只改 `spec.replicas`；是否平滑新增由 strategy 决定——两者命令与字段名都不同。
5. **清理 Pod 的坑（实测踩到）**：删 Pending/强删 Pod 用 `kubectl delete pod heavy --force --grace-period=0`，**别再叠加 `--now`**（两者互斥报错）；且清理命令别加 `2>/dev/null`——报错被吞、资源残留，排查半小时起步。

## 🧹 重练

```bash
kubectl -n apps delete pod heavy --force --grace-period=0
kubectl -n apps delete deploy web --now
```
