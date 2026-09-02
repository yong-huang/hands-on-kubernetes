# Kubernetes Pod Security 详解：PSS 三等级与 PSA 准入控制

## 1. 引言

默认情况下，容器里的进程一旦配上 `privileged: true`，就等于拿到了节点内核的全部能力：可以挂载宿主磁盘、改内核参数、读写其他容器的内存。哪怕不提权，一个 hostPath 挂到 `/` 的容器也能把整台节点搬走。Pod 安全需要**在创建时刻**就把这些越权行为挡在门外。

Kubernetes 的现代答案是 **PSS + PSA 两层设计**：Pod Security Standards 定义"什么算安全"（三套官方策略），Pod Security Admission 负责"怎么执行"（内置准入控制器，按 namespace 标签决定拒绝/警告/审计）。三道闸：enforce 硬拒绝、warn 软提示、audit 留痕观察。

## 2. 文件结构

```
20_pod_security/
├── README.md               # 本文档
├── pss.sh                  # 演示脚本: deploy / test (测试矩阵) / clean
├── manifests/
│   └── pod_security.yaml   # 3 个不同等级标签的 ns + 4 个测试 Pod (特权/hostPath/合规/root)
└── images/
    ├── psa_matrix.architecture.json  # 图源（Archify Typed JSON IR）
    ├── psa_matrix.html               # 交互版架构图
    └── psa_matrix.svg                # 双主题矢量版（本文档 §6 内嵌）
```

## 3. 核心概念

### PSS 三个等级各限制什么

| 等级 | 定位 | 典型禁/要求项 |
|------|------|--------------|
| **privileged** | 无限制 | 全部放开；仅给 CNI/CSI/监控这类真正需要特权的系统组件 |
| **baseline** | 中等 | 禁特权容器、禁宿主命名空间（hostNetwork/hostPID/hostIPC）、禁 hostPath 与 /proc、/sys 挂载、禁新增 capabilities（如 CAP_SYS_ADMIN） |
| **restricted** | 最严格 | 包含 baseline 全部要求，另加：必须 `runAsNonRoot`、必须 drop ALL capabilities、必须 `seccompProfile: RuntimeDefault`、禁止 `allowPrivilegeEscalation` |

三个等级是**包含关系**：restricted 的要求 ⊇ baseline ⊇ 无。合规于 restricted 的 Pod 在任何等级下都合规。

### PSA 三种模式

同一个等级标签可以配三种模式，作用完全不同：

| 模式 | 违规后果 | 用途 |
|------|---------|------|
| **enforce** | 拒绝创建，API 返回 Forbidden | 硬约束 |
| **audit** | 照常创建，审计日志记一条 `PodSecurityAudit` 事件 | 留痕评估违规面 |
| **warn** | 照常创建，kubectl 打印警告（写入 API 响应的 warnings 字段） | 给调用方提前感知 |

典型灰度路径：先 `warn` 观察影响面 → 再 `audit` 留痕统计 → 最后升级 `enforce` 强制。

### 与旧 PSP 的关系

Pod Security Policy（PSP）是老的方案：一个 Cluster 级 API 对象 + RBAC 控制谁能用哪个策略，配置极其繁琐、默认拒绝容易把集群锁死。PSP 在 **v1.21 弃用、v1.25 移除**，官方替代就是 PSA。区别在于：PSP 是"策略对象 + 授权"，PSA 是"namespace 标签 + 内置准入"，零 API 对象、按 namespace 天然隔离。

### namespace 标签配置

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted         # 模式: 等级
    pod-security.kubernetes.io/enforce-version: v1.36      # 锁定策略版本
```

六种标签的组合：`{enforce,audit,warn}[-version]`。`version` 缺省为 `latest`，生产建议显式固定，避免集群升级后策略悄悄变严。

## 4. YAML 关键字段

```yaml
# namespace 上打标签即完成全部配置 —— 没有任何策略对象
pod-security.kubernetes.io/enforce: restricted

# restricted 合规 Pod 的 securityContext "全家桶"
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

## 5. 合规改造清单

把一个普通业务 Pod 改造成 restricted 合规，需要四件套：

1. `runAsNonRoot: true`（必要时显式 `runAsUser: 1000`）—— root 镜像需要重打或换基础镜像
2. `capabilities.drop: ["ALL"]`—— 确需个别能力（如绑定 80 端口的 `NET_BIND_SERVICE`）再单独 add 回来
3. `allowPrivilegeEscalation: false` —— 同时意味着不能 setuid
4. `seccompProfile.type: RuntimeDefault` —— Pod 级或容器级均可

偷懒办法：`kubectl label --dry-run` 先验证；或直接用社区脚本批量给 Deployment 打补丁。

## 6. 可视化

![PSA 准入矩阵](images/psa_matrix.svg)

本实验的招牌演示画成了命运矩阵：**同一个特权测试 Pod**，提交到三个 PSA 标签不同的命名空间——`enforce=restricted` 直接 403 拒绝、`warn=restricted` 带着警告创建成功、`audit=restricted` 静默创建但审计留痕。右侧是 restricted 合规的 securityContext 四件套：runAsNonRoot、drop ALL、禁提权、seccomp。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/20_pod_security/images/psa_matrix.html)（或本地打开 [`images/psa_matrix.html`](images/psa_matrix.html)）。

## 7. 面试要点

1. **enforce vs audit vs warn**：enforce 违规直接拒绝（Forbidden）；audit 照常创建但在审计日志记录事件；warn 照常创建但通过 API 响应的 warnings 字段提示调用方。三者可同时配置不同等级，例如 enforce=baseline + warn=restricted，先硬挡最危险的、再软提示更高的目标。
2. **baseline 禁了什么**：面向"明显越权"——特权容器、宿主命名空间（hostNetwork/hostPID/hostIPC）、hostPath 及 /proc、/sys 等危险挂载、新增 capabilities、hostPorts。注意 baseline **不管** root 运行、capabilities 保留集和 seccomp，这些是 restricted 的职责。
3. **PSP → PSA 迁移策略**：① 盘点现有 PSP 与实际使用面；② 对每个 namespace 先打 `warn` + `audit` 标签跑一两周，收集违规；③ 修复工作负载（securityContext 全家桶）；④ 逐 namespace 升级 enforce，从低风险业务开始；⑤ 真需要特权的组件集中到专用 privileged namespace。局限：PSA 不支持 PSP 的部分能力（如按 RBAC 授权不同策略、限制只读 root FS），复杂需求需配 Kyverno/OPA。
4. **PSA 与 RBAC / NetworkPolicy 的层次区别**：RBAC 管"谁能对哪些资源做什么操作"（API 访问控制）；NetworkPolicy 管"Pod 能跟谁通信"（网络层）；PSA 管"Pod 本身能有多大的越权配置"（工作负载安全基线）。三者正交，共同构成纵深防御——RBAC 挡住人、PSA 挡住危险 Pod、NetworkPolicy 挡住横向移动。

## 8. 总结

PSS/PSA 的本质是把 Pod 安全从"每家自己写策略"收敛为**官方三等级 + namespace 标签开关**：privileged 放开一切、baseline 挡住越权、restricted 强制最小权限；enforce/audit/warn 三模式提供平滑灰度的执行手段。记住两条主线：等级的包含关系（restricted ⊇ baseline）、模式的软硬之分（拒绝/留痕/提示）。配合 `pss.sh` 里"同一特权 Pod 在三个 namespace 命运迥异"的演示，能直观体会"安全策略跟着 namespace 走"这一设计意图。
