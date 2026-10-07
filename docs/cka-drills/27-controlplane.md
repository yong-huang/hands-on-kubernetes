# CKA 开工包 · 项目 27：控制面组件故障定位与恢复

> 对应清单：`docs/cka.md` 项目 27 ｜ 环境：kind 集群 `k8s-learn`（控制面组件均为静态 pod）｜ 实测日期：2026-10-07
> 先闭卷自做，再对照。**scheduler 与 controller-manager 都做了完整注入/恢复实测。**

## 📝 题面（考场原题风格）

> `Task:` In the cluster, newly created pods remain Pending forever. Identify
> which control-plane component is broken and restore it without restarting
> the whole cluster. (Weight: 8%)
>
> 目标用时：10 分钟

## ✅ 实测一：kube-scheduler 摘除 → 永远 Pending → 恢复

```bash
# 注入（kind：控制面组件是节点容器内的静态 pod，manifests 目录即开关）
docker exec k8s-learn-control-plane mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/
# 现象（实测 2026-10-07）：
kubectl -n kube-system get pods | grep scheduler        # 0 个（mirror pod 消失）
kubectl get pod sched-test -o wide                       # Pending，NODE=<none>
kubectl get pod sched-test -o jsonpath='{.status.conditions[*].type}'   # 无 PodScheduled
kubectl describe pod sched-test | grep "Successfully assigned"          # 无此事件
# 恢复
docker exec k8s-learn-control-plane mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
# 实测：25s 内 scheduler 回来，卡住的 pod 立即落位（sched-test → worker2）✅
```

## ✅ 实测二（方法论级陷阱）：controller-manager 摘除——status 冻结

注入方式同上（摘 `kube-controller-manager.yaml`），删一个 deployment 的 pod 后：

```
实际 pod 数：2 → 1（没人重建 ✅）
kubectl get deploy cm-demo  → READY 2/2   ← 假象！
kubectl get rs    cm-demo   → 2/2/2      ← 假象！
```

**controller 挂掉后所有 status 字段停止更新，`get deploy/rs` 显示的是冻结的旧状态**，
看起来完全健康。唯一可信的是 `kubectl get pods -l app=xxx` 数实际对象。
（前两轮实测就是被这个假象骗到以为实验失败。）

## 🧠 现象对照表（考场诊断卡）

| 组件挂掉 | 实测现象 |
|:---|:---|
| kube-scheduler | 新 Pod Pending、NODE `<none>`、无 PodScheduled condition、无调度事件 |
| kube-controller-manager | 副本数不收敛（**status 冻结是假象，数 pod 才作数**）、Node 生命周期/端点同步等控制循环全停 |
| etcd | apiserver 读写失败（ls/get 超时报错），一切操作瘫痪 |
| kube-apiserver | kubectl 全部失联（TLS/connection refused），静态 pod/节点上容器仍在跑 |

## ⚠️ 五大丢分点

1. **诊断入口**：先 `kubectl -n kube-system get pods` 看哪个控制面静态 pod 消失/异常——一步锁定，比翻日志快。
2. **status 冻结陷阱（本题实测最大收获）**：别信 `get deploy` 的 READY，数 pod。
3. **恢复手段**：静态 pod 环境下把 manifest 放回 `/etc/kubernetes/manifests/` 即秒级自愈；考场恢复 = 修 manifest 文件或 `mv` 回来，**不是重启集群**。
4. **kube-apiserver 挂时别慌**：kubectl 失联但节点上容器还活着，恢复 apiserver 一切照旧——这与 scheduler/cm 挂的区分度题眼。
5. **窗口纪律**：注入期间系统其他控制循环也在停转（节点 lease、端点同步），做实验窗口要短、恢复要快——考试不存在这个环节，但本机练要养成习惯。

## 🧹 重练

```bash
docker exec k8s-learn-control-plane ls /etc/kubernetes/manifests/   # 确认四个 manifest 齐
```
