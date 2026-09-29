# 19 · RBAC：角色、绑定与最小权限原则

> 一个集群里不止管理员在调 API：CI 流水线要部署应用、监控组件要读 Pod 状态、Pod 内的应用要 watch ConfigMap。**谁**能对**哪些资源**做**什么操作**——这个问题由 RBAC（基于角色的访问控制）回答。没有被显式授权的操作，默认全部拒绝（default-deny）。读完本篇，你将掌握四件套的组合矩阵，并学会用 `can-i` 与 `--as` 像裁判一样验证权限。

## Background

早期集群的访问控制是"一把钥匙"：所有人共用管理员 kubeconfig。CI 泄露一次凭据，整个集群门户大开；想知道"谁能删生产 Pod"，答案无从查起。给每个人单开权限又会爆炸——权限和身份绑死，换岗、交接、审计都无从下手。

RBAC 的解法是把"身份"和"权限"解耦：权限定义在 Role（角色）里，通过 Binding（绑定）挂到 Subject（主体）上。角色可以复用，身份可以累积多个绑定的权限，"谁有什么权"变成一张可查询的表。它的默认姿态是白名单：没有被显式授权的操作，一律拒绝。

## What

RBAC 把"身份"和"权限"解耦：权限定义在 Role 里，通过 Binding 绑到 Subject 上。一个 Role 可以被多个身份复用，一个身份也可以累积多个 Binding 的权限。四件套按作用域组合：

| 对象 | 级别 | 作用 |
|------|------|------|
| Role | namespace | 权限规则集合，只在所在 ns 生效 |
| ClusterRole | 集群 | 集群级资源（Node/PV/ns）的规则；或"可跨 ns 复用的规则模板" |
| RoleBinding | namespace | 把 Role/ClusterRole 绑到 Subject，生效于本 ns |
| ClusterRoleBinding | 集群 | 把 ClusterRole 绑到 Subject，**所有 ns 生效** |

一句话心智模型：**Binding 决定"权限生效在哪"，Role 决定"权限是什么"**——可以把 Role 想象成岗位职责说明书；但和岗位职责不同的是，一个人可以同时挂多份说明书（多个 Binding 取并集），且说明书只能加不能减（没有黑名单）。

关键组合是 **RoleBinding + ClusterRole**：规则定义一次（如内置的 `view`），在每个 ns 里用 ns 级 Binding 引用——规则复用但权限不出 ns，这是最推荐的姿势。

## When to Use

典型场景：给 CI 流水线一个只能部署指定 namespace 的 ServiceAccount（K8s 里给进程用的身份账号，How It Works 详述）；给监控组件只读权限（内置 `view` 角色）；给团队开"开发 ns 内自由、生产 ns 只读"的分级权限。

何时不用：单管理员本地集群（RBAC 的价值在多主体）；需要按请求内容动态鉴权（如"只能改自己创建的对象"——那是准入控制或外部策略引擎的领域）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 共享管理员 kubeconfig | 无边界 | 不要用 |
| RBAC | 白名单 + 并集 + 默认拒绝 | K8s API 访问控制（标准） |
| OPA/Kyverno 准入策略 | 管资源内容合规 | 与 RBAC 互补（lab 21） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/19_rbac
./rbac.sh deploy   # 两个 SA/Role/RoleBinding 身份组合 + demo Deployment
./rbac.sh verify   # can-i yes/no 矩阵：who 能对 what 做什么
./rbac.sh deny     # --as 模拟：看真实的 Forbidden 报错
./rbac.sh clean
```

关键字段（`manifests/rbac.yaml`）：

```yaml
# Role: 一组规则
rules:
  - apiGroups: [""]               # "" = 核心 API 组 (pods/services/configmaps)
    resources: ["pods", "pods/log"]  # 子资源必须显式列出
    verbs: ["get", "list", "watch"]  # 只读三件套

# RoleBinding: subjects + roleRef
subjects:
  - kind: ServiceAccount
    name: dev-viewer
    namespace: rbac-demo           # SA 是 ns 级资源，namespace 必须写对
roleRef:                           # 创建后不可修改（immutable），换角色只能删了重建
  apiGroup: rbac.authorization.k8s.io
  kind: Role                       # 也可以写 ClusterRole（ns 级生效）
  name: pod-reader
```

常见漏配：`deployments` 在 `apps` 组而不是核心组；`resourceNames` 字段可以把 get 限定到具体对象名；ClusterRole 里可以写 `aggregationRule` 从其他 ClusterRole 聚合规则。

验证工具三件套：

| 工具 | 用途 |
|------|------|
| `kubectl auth can-i <verb> <resource> -n <ns> --as=<user>` | 预演授权判定，返回 yes/no，无副作用，CI 里断言权限的利器；SA 的完整用户名是 `system:serviceaccount:<ns>:<sa>` |
| `--as` 模拟 | 给任何 kubectl 命令加上身份伪装（前提是你有 impersonate 权限），直接跑真实操作看结果——deny 步骤用它展示真实的 Forbidden 报错 |
| `kubectl describe rolebinding <name>` | 查看绑定链两端——subjects 是谁、roleRef 指向哪个 Role |

## How It Works

**认证 vs 授权**：每次 API 请求都要过两道关——**认证（authn）回答"你是谁"**，通过客户端证书、Token、ServiceAccount Token 等确定身份；

**授权（authz）回答"你可以吗"**，RBAC 是其中最常用的模式（还有 Node/ABAC/Webhook 等）。认证在前授权在后，先有身份才谈得上权限。

**身份的两种来源**：**ServiceAccount 是进程身份**，集群内的对象（有 Token），给 CI、控制器、Pod 内应用用；

**User/Group 是人的身份**，由外部认证体系（OIDC、证书 CN 等）提供，K8s 里没有 User 对象，`kubectl create user` 不存在。

Binding 的 `subjects.kind` 三选一：`ServiceAccount`（要带 namespace）/ `User` / `Group`。

**判断流程**：apiserver 收到请求后先认证出用户（含组、SA 信息），再遍历所有匹配该用户的 Binding（RoleBinding + ClusterRoleBinding）并累加其引用 Role 的规则。

任一规则的 apiGroups/resources/verbs（及 resourceNames）匹配请求即放行。

全部不匹配时返回 403 Forbidden——你在 `deny` 步骤看到的 Forbidden 报错，就是"所有规则都不匹配"的终点。

**verbs 与子资源**：verbs 是动作——`get/list/watch/create/update/patch/delete/deletecollection`，还有 `*` 通配与 `impersonate`（允许模拟他人，高危）。

**子资源要单独授权**：`kubectl logs` 实际请求的是 `GET /api/v1/namespaces/{ns}/pods/{name}/log`，对应 resource 是 `pods/log` 而不是 `pods`。

只授了 pods 的 get 是拉不了日志的（`exec` 同理需要 `pods/exec`），本实验专门演示了这一点。

**default-deny 语义**：RBAC 只有白名单没有黑名单，多个 Binding 的权限**取并集**，无法用一条规则"减掉"权限。没匹配到任何规则就是 Forbidden。所以授权粒度宁细勿粗——给了 `*` 就收不回来了。

## Pitfalls & Q&A

踩坑清单：

- 写了 Role 忘了 Binding（最常见）：角色定义不会自动生效。
- Role 和 Binding/请求的 namespace 不匹配：权限没落在请求发生的 ns。
- 只授 `pods` 漏了 `pods/log` 等子资源，`kubectl logs/exec` 报 Forbidden。
- `deployments` 在 apps 组，写成核心组匹配不上。
- 集群级资源（PV/Node）用 Role 授权永远不生效。
- roleRef 不可变，改绑定要删重建。

**Q1: RBAC 和 Pod Security、NetworkPolicy 是什么关系？**

三层互补的安全面：RBAC 管"谁能调 K8s API"（控制面，挡住人）；Pod Security Admission 管容器本身的权限（数据面，挡住危险 Pod，见 lab 20）；

NetworkPolicy 管 Pod 间网络可达性（网络面，挡住横向移动，见 lab 12）。任何一层都不是银弹——RBAC 挡不住容器逃逸，NetworkPolicy 挡不住越权的 kubectl。

**Q2: 为什么 roleRef 设计成不可变？**

Binding 是"身份 → 权限"的唯一指针，如果 roleRef 可以就地改，一次误操作就能把只读身份静默升级成集群管理员，且审计日志里看不出权限变化。删了重建虽然繁琐，但每次权限变更都是显式事件，留下了审计痕迹——这是"不便换来的安全"，和 default-deny 是同一个设计取向。
