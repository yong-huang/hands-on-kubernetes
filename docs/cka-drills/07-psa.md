# CKA 开工包 · 项目 7：Pod Security Admission 命名空间加固

> 对应清单：`docs/cka.md` 项目 7 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Enforce the Pod Security Standard `baseline` on namespace `apps`
> (enforce mode, warn and audit also enabled). Verify that a pod with
> `privileged: true` is rejected. (Weight: 3%)
>
> 目标用时：6 分钟

## ✅ 考场最优解

```bash
kubectl label ns apps \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline
# 验证：特权 Pod 被拒
kubectl run pri -n apps --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"pri","image":"busybox:1.36","securityContext":{"privileged":true}}]}}'
# 普通 Pod 正常创建 → 加固生效且不影响业务
kubectl run normal -n apps --image=busybox:1.36 --restart=Never --command -- sleep 3600
```

## 🧪 实测记录（2026-10-06）

特权 Pod 被 apiserver 原文拒绝（考场看到这句就是满分证据）：

```
Error from server (Forbidden): pods "privileged-pod" is forbidden:
violates PodSecurity "baseline:latest": privileged
(container "p" must not set securityContext.privileged=true)
```

**三模式语义实测**（把 warn 提到 restricted 后创建普通 Pod）：

```
Warning: would violate PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false ... unrestricted capabilities ...
  runAsNonRoot != true ... seccompProfile ...
pod/warn-demo created          ← 只警告，不拦截
```

即：**enforce=拒绝、warn=照建但 stderr 报警、audit=只进审计日志**。restricted 标准对普通镜像必出 4 条违规警告，考场上看到 Warning 不代表失败，看 Pod 是否创建成功。

## ⚠️ 五大丢分点

1. **PSA 配置位置错**：只能配在 **namespace label**（`pod-security.kubernetes.io/*`），不是 RBAC 也不是 NetworkPolicy；三个键名拼错一个都不生效。
2. **三模式职责混**：题目说 warn/audit also enabled，漏打标签直接丢一半分。
3. **标准级别梯度不清**：privileged（不限制）⊂ baseline（禁特权/宿主命名空间等）⊂ restricted（还要求 runAsNonRoot、drop ALL 等）。
4. **验证姿势错**：证明「被拒」要贴出 Forbidden 原文；证明「不影响业务」要建一个合规 Pod 成功。
5. **清理不彻底**：练习后用 `kubectl label ns apps pod-security.kubernetes.io/enforce- ...`（key 减号）摘除，否则后续在该命名空间部署受限镜像会莫名被拒。

## 🧹 重练

```bash
kubectl delete pod -n apps --all --now
kubectl label ns apps pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/audit- pod-security.kubernetes.io/warn-
```
