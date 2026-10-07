# CKA 开工包 · 项目 4：RBAC 最小权限配置

> 对应清单：`docs/cka.md` 项目 4 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1，3 节点）｜ 实测日期：2026-10-06
> 本题解已在本机实测跑通，验收矩阵 6/6 通过。**先自己闭卷做一遍，再回来对照**——这是真题训练场，不是教程。

## 📝 题面（考场原题风格）

> `Task:` Create a new ServiceAccount named `cicd` in namespace `build`.
> Grant this ServiceAccount permission to create and patch Deployments in namespace `build` only.
> Verify the permission using `kubectl auth can-i`. (Weight: 4%)
>
> 目标用时：8 分钟 ｜ 建议先 `kubectl config use-context kind-k8s-learn`

## ✅ 考场最优解（imperative，约 40 秒打完）

```bash
kubectl create namespace build
kubectl create serviceaccount cicd -n build
kubectl create role deploy-manager -n build \
  --verb=create,patch --resource=deployments
kubectl create rolebinding cicd-deploy-manager -n build \
  --role=deploy-manager --serviceaccount=build:cicd
```

自验（判分人看得见的动作，务必做）：

```bash
kubectl auth can-i create deployments --as=system:serviceaccount:build:cicd -n build    # 期望 yes
kubectl auth can-i create deployments --as=system:serviceaccount:build:cicd -n default  # 期望 no
```

## 🧾 YAML 备查版（等价于上面 4 条命令的产物）

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deploy-manager
  namespace: build
rules:
- apiGroups: ["apps"]          # deployments 属于 apps 组，手写 YAML 最常见翻车点
  resources: ["deployments"]
  verbs: ["create", "patch"]   # 只给题目要的动词，多给=违反最小权限=丢分
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cicd-deploy-manager
  namespace: build
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deploy-manager
subjects:
- kind: ServiceAccount
  name: cicd
  namespace: build
```

## 🧪 验收矩阵（本机实测输出 2026-10-06）

```
[1] 本空间 create deployments (期望 yes):  yes
[2] 本空间 patch deployments  (期望 yes):  yes
[3] 本空间 list deployments   (期望 no):   no
[4] 本空间 delete deployments (期望 no):   no
[5] 跨空间 create deployments (期望 no):   no
[6] 本空间 create pods        (期望 no):   no
```

清单验收标准（[1]=yes 且 [5]=no）达成 ✅

## ⚠️ 五大丢分点

1. **apiGroup 写错**：手写 YAML 把 deployments 的 apiGroup 写成 `extensions`（老版本）或留空。`kubectl create role` 自动补 `apps`，考场优先 imperative。
2. **动词画蛇添足**：题目只要 `create,patch`，顺手加了 `list/get/delete` —— 违反「only」语义，判分脚本会检查 verbs 集合。
3. **Role 误用 ClusterRole**：题面说 `in namespace build only`，用 ClusterRole+ClusterRoleBinding 直接超范围，全题 0 分。
4. **忘了自验**：`kubectl auth can-i` 题面明确要求 Verify，不做这一步等于主动丢过程分。
5. **ServiceAccount 名字空间写错**：RoleBinding 的 subject 要写 `build:cicd` 或带 `namespace: build`，漏了会绑定到 default 的同名 SA。

## 🧹 复盘/重练

```bash
kubectl delete ns build          # 清场，重练一遍
# 重练目标：不看本文档，8 分钟内闭卷完成 + 自验通过
```
