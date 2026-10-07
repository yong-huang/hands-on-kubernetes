# CKA 开工包 · 项目 22：Pod 四大故障状态速修

> 对应清单：`docs/cka.md` 项目 22 ｜ 环境：kind 集群 `k8s-learn` ｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。**注入 YAML 与判分脚本已沉淀**，可随时重练。

## 📝 题面（考场原题风格）

> `Task:` Fix all broken pods in namespace `broken`. Each pod fails for a
> different reason: wrong image, invalid command, unschedulable constraint,
> and a too-low memory limit. Leave the workloads otherwise unchanged.
> (Weight: 8%)
>
> 目标用时：15 分钟

## 🧰 可复用工具（本目录 scripts/）

```bash
# 恢复故障现场
kubectl delete ns broken; kubectl create ns broken
kubectl apply -f docs/cka-drills/scripts/chaos-22.yaml
# 判分（修复后跑）
bash docs/cka-drills/scripts/verify-22.sh    # → 得分: 4/4
```

## ✅ 四态诊断速查表（实测取证原文）

| 状态 | 一眼定位命令 | 证据原文（实测） | 修法 |
|:---|:---|:---|:---|
| ImagePullBackOff | `describe pod` | `Failed to pull image "busybox:9.9.9-nonexist" ... 403/404` | patch image（**image 是 Pod 唯一可热改字段**） |
| CrashLoopBackOff | `logs pod` | `exec: /nonexistent-bin: no such file or directory` | 删了重建改 command |
| Pending | `describe pod` | `0/3 nodes: 1 untolerated taint(s), 2 didn't match node affinity/selector` | 删了重建去掉 nodeSelector |
| OOMKilled | `describe pod` + `get pod -o jsonpath` | Last State `Reason: OOMKilled` `Exit Code: 137`，restartCount 上涨 | 删了重建调大 memory limit |

**2026-10-06 实测轨迹**：注入后 25s 四态齐现（bad-cmd 先显 `RunContainerError`，重试 3 次转 CrashLoopBackOff）；oom-loop 重启计数 3；修复后 `verify-22.sh` 输出 **4/4**。

## ⚠️ 五大丢分点

1. **可变与不可变字段（本题最深的坑）**：Pod 创建后只有 `spec.containers[].image` 等极少数字段可 patch；command / nodeSelector / resources **全部 immutable**，改=删了重建。实测：patch nodeSelector/resources 直接被拒。
2. **exit code 137 = OOM**（128+9 SIGKILL）；`logs --previous` 能看到被杀前的输出——OOM 必答证据链。
3. **CrashLoopBackOff 与 Init:CrashLoopBackOff 区分**：Init 容器失败看 `logs <pod> -c <init-container>`。
4. **"leave otherwise unchanged" 约束**：只修故障字段，别顺手优化——判分 diff 其他字段算错。
5. **状态出现的时序**：镜像拉取失败先显 `ErrImagePull`、重试后转 `ImagePullBackOff`；启动命令错先显 `RunContainerError` 再转 `CrashLoopBackOff`——考场看到的中间态别慌。

## 🧹 重练

```bash
# 见顶部"可复用工具"：恢复故障 → 闭卷修 → verify-22.sh 判 4/4
kubectl delete ns broken --now
```
