# CKA 开工包 · 项目 8：Deployment 滚动更新与回滚

> 对应清单：`docs/cka.md` 项目 8 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。本题实测踩到一个「静默失败」大坑，见下。

## 📝 题面（考场原题风格）

> `Task:` Update deployment `api` in namespace `apps` to image `nginx:1.27`
> with `maxSurge=1, maxUnavailable=0`. Wait for the rollout to finish.
> Then roll back to the previous revision. (Weight: 4%)
>
> 目标用时：8 分钟

## ⚠️ 实测头号踩坑：容器名 ≠ Deployment 名（升级静默失败）

`kubectl create deployment api --image=nginx:1.25` 创建的**容器名是 `nginx`**（跟镜像名走）。
于是 `kubectl set image deploy/api api=nginx:1.27` 报错：

```
error: unable to find container named "api"
```

若没注意，之后 `rollout undo` 会提示 `skipped rollback (current template already matches revision 1)`
——因为升级根本没发生，revision 1 就是当前版本。**修正：用通配符最稳**：

```bash
kubectl set image deploy/api '*=nginx:1.27'
```

## ✅ 考场最优解（实测全流程）

```bash
kubectl create deployment api -n apps --image=nginx:1.25 --replicas=3
kubectl -n apps rollout status deploy/api --timeout=180s
# 策略（改的是 spec.strategy，不触发新 revision）
kubectl -n apps patch deploy api --type=strategic \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
# 升级（--record 已废弃，用 change-cause 注解留痕）
kubectl -n apps annotate deploy api kubernetes.io/change-cause="upgrade to 1.27" --overwrite
kubectl -n apps set image deploy/api '*=nginx:1.27'
kubectl -n apps rollout status deploy/api --timeout=300s
# 回滚
kubectl -n apps rollout history deploy/api
kubectl -n apps rollout undo deploy/api --to-revision=1
kubectl -n apps rollout status deploy/api --timeout=300s
kubectl -n apps get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}'   # → nginx:1.25
```

实测结果：升级后镜像 `nginx:1.27`，`undo --to-revision=1` 后回到 `nginx:1.25` ✅

## ⚠️ 丢分点清单

1. **容器名想当然**：先 `kubectl get deploy api -o jsonpath='{.spec.template.spec.containers[0].name}'` 确认，或直接 `*=` 通配。
2. **maxSurge=1/maxUnavailable=0 语义**：先扩 1 再缩，全程可用副本不降——题面这么写就要 patch 这么改，漏了 strategy 直接丢分。
3. **`--record` 已废弃**：考场写 change-cause 注解（`kubernetes.io/change-cause`），`rollout history` 才有人话。
4. **不确认升级已发生就 undo**：`rollout status` 是「等它完成」也是「验证它发生了」的判据。
5. **没有 --timeout 的 rollout status 会无限等**：镜像 tag 写错（如 `nginx:1.x` 不存在）时 Pod 卡 ImagePull，考场时间就这么烧掉的。

## 🧹 重练

```bash
kubectl -n apps delete deploy api --now
```
