# CKA 开工包 · 项目 14：Endpoints 排查与 selector 修复

> 对应清单：`docs/cka.md` 项目 14 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Deployment `api` is running 3 ready pods, but Service `api` has no
> endpoints and is unreachable. Find the root cause and fix it.
> Do not modify the deployment. (Weight: 4%)
>
> 目标用时：6 分钟

## ✅ 考场最优解（实测可复现）

```bash
# 注入故障：人为把 svc 的 selector 改成与 pod label 不匹配
kubectl -n apps patch svc api -p '{"spec":{"selector":{"app":"api-broken"}}}'

# 排障四连
kubectl -n apps get ep api                 # ENDPOINTS = <none> ← 头号信号
kubectl -n apps describe svc api | grep -A1 Selector   # app=api-broken
kubectl -n apps get pods --show-labels     # pod 实际是 app=api
# 修复（题目禁改 deployment → 改 svc）
kubectl -n apps patch svc api -p '{"spec":{"selector":{"app":"api"}}}'
kubectl -n apps get ep api                 # 立即出现 3 个 podIP:port
```

## 🧪 实测证据（2026-10-06）

```
修复前:  api    ENDPOINTS <none>      Selector: app=api-broken   pods: app=api
修复后:  api    ENDPOINTS 10.244.1.29:80,10.244.2.20:80,10.244.2.21:80
wget http://api → nginx 欢迎页 ✅
```

**📋 考情更新（v1.33+）**：kubectl 已提示 `v1 Endpoints is deprecated in v1.33+`。
新姿势：`kubectl get endpointslice -n apps`——考场两种都要会读，EndpointSlice 按
`kubernetes.io/service-name` label 关联 Service。

## ⚠️ 五大丢分点

1. **只查 svc 不查 ep**：Pod 全 Ready 但服务不通，第一反应该看 `get ep`——为空=selector 失配（本题）、有值=端口/策略问题（项目 24）。
2. **`pod-template-hash` 干扰**：`--show-labels` 输出里 hash 标签别抄进 selector，只匹配业务标签。
3. **忽略题目约束**：`Do not modify the deployment` 意味着改 Service 一侧；擅自给 pod 打标签虽也能通，但违反题意判 0。
4. **patch selector 的覆盖语义**：`spec.selector` 是 map 整体替换，patch 时写全所有要保留的键。
5. **修完不验证**：`get ep` 出现 IP + 一次 `exec wget` 双证据，才叫修完。

## 🧹 重练

```bash
kubectl -n apps patch svc api -p '{"spec":{"selector":{"app":"api-broken"}}}'   # 再坏一次
```
