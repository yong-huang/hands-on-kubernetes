# 20 · Pod Security：PSS 三等级与 PSA 准入控制

> 默认情况下，容器里的进程一旦配上 `privileged: true`，就等于拿到了节点内核的全部能力：可以挂载宿主磁盘、改内核参数、读写其他容器的内存。哪怕不提权，一个 hostPath 挂到 `/` 的容器也能把整台节点搬走。Pod 安全需要**在创建时刻**就把这些越权行为挡在门外。

## What

Kubernetes 的现代答案是 **PSS + PSA 两层设计**：Pod Security Standards（PSS）定义"什么算安全"——三套官方策略；Pod Security Admission（PSA）负责"怎么执行"——内置准入控制器，按 namespace 标签决定拒绝/警告/审计。一句话心智模型：**安全策略跟着 namespace 走，namespace 上打标签就是全部配置**。

三个等级（**包含关系**：restricted 的要求 ⊇ baseline ⊇ 无，合规于 restricted 的 Pod 在任何等级下都合规）：

| 等级 | 定位 | 典型禁/要求项 |
|------|------|--------------|
| **privileged** | 无限制 | 全部放开；仅给 CNI/CSI/监控这类真正需要特权的系统组件 |
| **baseline** | 中等 | 禁特权容器、禁宿主命名空间（hostNetwork/hostPID/hostIPC）、禁 hostPath 与 /proc、/sys 挂载、禁新增 capabilities（如 CAP_SYS_ADMIN） |
| **restricted** | 最严格 | 包含 baseline 全部要求，另加：必须 `runAsNonRoot`、必须 drop ALL capabilities、必须 `seccompProfile: RuntimeDefault`、禁止 `allowPrivilegeEscalation` |

同一个等级标签可配三种模式（六种标签的组合：`{enforce,audit,warn}[-version]`）：

| 模式 | 违规后果 | 用途 |
|------|---------|------|
| **enforce** | 拒绝创建，API 返回 Forbidden | 硬约束 |
| **audit** | 照常创建，审计日志记一条 `PodSecurityAudit` 事件 | 留痕评估违规面 |
| **warn** | 照常创建，kubectl 打印警告（写入 API 响应的 warnings 字段） | 给调用方提前感知 |

## Why

Pod 安全必须"创建时拦截"而不是"运行后补救"：特权容器一旦起来，节点的内核边界就破了，事后驱逐只是止损。而旧方案 Pod Security Policy（PSP）是集群级策略对象 + RBAC 授权，配置极其繁琐、默认拒绝容易把整个集群锁死——PSP 在 **v1.21 弃用、v1.25 移除**，官方替代就是 PSA：零 API 对象、按 namespace 天然隔离、warn/audit 提供平滑灰度路径。

## How

```bash
cd labs/20_pod_security
./pss.sh deploy   # 3 个不同等级标签的 ns + 4 个测试 Pod（特权/hostPath/合规/root）
./pss.sh test     # 测试矩阵：同一特权 Pod 在三个 namespace 的不同命运
./pss.sh clean
```

namespace 标签配置（没有任何策略对象）：

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted         # 模式: 等级
    pod-security.kubernetes.io/enforce-version: v1.36      # 锁定策略版本
```

`version` 缺省为 `latest`，生产建议显式固定，避免集群升级后策略悄悄变严。

restricted 合规 Pod 的 securityContext "全家桶"（`manifests/pod_security.yaml`）：

```yaml
spec:
  securityContext:
    runAsNonRoot: true              # Pod 级: 禁止 uid=0
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault          # 限制系统调用集
  containers:
    - securityContext:
        allowPrivilegeEscalation: false   # 禁 sudo/suid 提权
        capabilities:
          drop: ["ALL"]             # 丢掉全部 Linux capabilities
        seccompProfile:
          type: RuntimeDefault
```

把普通业务 Pod 改造成 restricted 合规的四件套：① `runAsNonRoot: true`（必要时显式 `runAsUser: 1000`，root 镜像需要重打或换基础镜像）；② `capabilities.drop: ["ALL"]`——确需个别能力（如绑定 80 端口的 `NET_BIND_SERVICE`）再单独 add 回来；③ `allowPrivilegeEscalation: false`——同时意味着不能 setuid；④ `seccompProfile.type: RuntimeDefault`——Pod 级或容器级均可。偷懒办法：`kubectl label --dry-run` 先验证，或用社区脚本批量给 Deployment 打补丁。

## Deep Dive

**三模式的软硬组合**：enforce 违规直接拒绝（Forbidden）；audit 照常创建但在审计日志记录事件；warn 照常创建但通过 API 响应的 warnings 字段提示调用方。三者可同时配置不同等级，例如 enforce=baseline + warn=restricted——先硬挡最危险的、再软提示更高的目标。

**baseline 的边界**：面向"明显越权"——特权容器、宿主命名空间（hostNetwork/hostPID/hostIPC）、hostPath 及 /proc、/sys 等危险挂载、新增 capabilities、hostPorts。注意 baseline **不管** root 运行、capabilities 保留集和 seccomp，这些是 restricted 的职责。

**招牌演示**：**同一个特权测试 Pod**，提交到三个 PSA 标签不同的命名空间——`enforce=restricted` 直接 403 拒绝、`warn=restricted` 带着警告创建成功、`audit=restricted` 静默创建但审计留痕。同一份 YAML，命运完全由目标 namespace 的标签决定。

**PSP → PSA 迁移的可行路径**：① 盘点现有 PSP 与实际使用面；② 对每个 namespace 先打 `warn` + `audit` 标签跑一两周，收集违规；③ 修复工作负载（securityContext 全家桶）；④ 逐 namespace 升级 enforce，从低风险业务开始；⑤ 真需要特权的组件集中到专用 privileged namespace。局限：PSA 不支持 PSP 的部分能力（如按 RBAC 授权不同策略、限制只读 root FS），复杂需求需配 Kyverno/OPA。

## Q&A

**Q1: PSA、RBAC、NetworkPolicy 三者的分工？**
三者正交，共同构成纵深防御：RBAC 管"谁能对哪些资源做什么操作"（API 访问控制，挡住人，见 lab 19）；PSA 管"Pod 本身能有多大的越权配置"（工作负载安全基线，挡住危险 Pod）；NetworkPolicy 管"Pod 能跟谁通信"（网络层，挡住横向移动，见 lab 12）。任何一层都不是银弹——RBAC 挡不住容器逃逸，PSA 挡不住两个合法 Pod 之间的攻击。

**Q2: 集群里所有业务 namespace 都该直接上 enforce=restricted 吗？**
不该一刀切。restricted 要求 securityContext 四件套齐全，存量业务多半不合规，直接 enforce 会把发布全部拦死。按灰度路径走：先全量打 `warn=restricted` 让调用方在 kubectl 输出里看到差距，再对低风险 namespace 升 enforce；平台型基础设施（CNI/CSI/监控 Agent）集中到 privileged namespace，并严格控制谁能往里部署。
