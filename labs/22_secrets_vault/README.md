# 22 · Secrets 管理：Vault 动态凭证与 Secrets Store CSI

> 原生 K8s Secret 是 base64 编码的明文：写进 Git 会泄漏，存进 etcd 跟着备份到处跑，且从不轮换（见 lab 05 的"安全真相"）。本实验用 **HashiCorp Vault + Secrets Store CSI Driver** 替换这条路径：应用 Pod 不再持有长期密码，而是在挂载卷的瞬间由 Vault 的数据库动态引擎**现场生成一组临时凭证**（TTL 1h），Pod 销毁即自动吊销。

## What

| 机制 | 角色 |
|------|------|
| SecretProviderClass | 声明式"取数配置"——告诉 CSI 驱动去哪取、取什么 |
| K8s Auth | Pod 用 ServiceAccount token 换短期 Vault token，集群内不存任何 Vault 凭证 |
| 租约（Lease） | 动态凭证的灵魂——TTL 到期作废、Pod 删除即 revoke |
| secretObjects | 可选：把挂载内容投影成普通 K8s Secret，供只认 env/Secret 引用的组件使用 |

一句话心智模型：**凭证从"一次生成、永不轮换的静态资产"变成"按需签发、随 Pod 生灭的临时资产"**——数据库里存在大量短命账号，任何一个泄漏都只在 TTL 窗口内有效。

## Why

静态 Secret 的根本缺陷是"静态"：泄露后的有效窗口是无限的，轮换要人工推动，副本随 etcd 备份、Git 仓库、CI 日志扩散。动态凭证把有效窗口压缩到 TTL（1h），把分发面压缩到"只有用到它的 Pod 挂载时才存在"——泄漏的代价从"灾难"降级为"有限时间窗内的一次性访问"。

## How

```bash
cd labs/22_secrets_vault
./vault_setup.sh install   # 部署 Vault(dev) + PostgreSQL + Secrets Store CSI Driver
./vault_setup.sh config    # 配置数据库动态引擎 + K8s Auth role
./vault_setup.sh deploy    # 部署挂载 CSI 卷的 demo Pod，验证动态凭证注入
./vault_setup.sh clean
```

SecretProviderClass（`manifests/vault_secrets.yaml`）——注意 `database/creds/*` 前缀是**动态引擎**路径，不是 KV 存储路径：

```yaml
spec:
  provider: vault
  parameters:
    roleName: "demo-app"
    objects: |
      - objectName: "username"
        secretPath: "database/creds/demo-app"
```

K8s Auth——把信任范围钉死到具体 SA 和命名空间，防止别的负载冒名：

```bash
vault write auth/kubernetes/role/demo-app \
  bound_service_account_names=demo-app \
  bound_service_account_namespaces=vault-demo policies=demo-app ttl=1h
```

租约配置——每份凭证绑定 TTL/max_ttl：

```bash
vault write database/roles/demo-app default_ttl=1h max_ttl=24h ...
```

secretObjects——同步成普通 K8s Secret 的双通道：

```yaml
secretObjects:
  - secretName: db-creds-synced
    data: [{objectName: username, key: db_user}]
```

## Deep Dive

**动态注入的完整链路（四步）**：Pod 挂载触发 CSI 驱动 → 拿 SA projected token 走 K8s Auth 换取短期 Vault token → 动态引擎让 PostgreSQL 现场 `CREATE ROLE`（演示用 PostgreSQL 部署在 `vault-demo` 命名空间，管理员账号由 `vault_setup.sh config` 步骤写入引擎配置）→ 临时凭证（TTL 1h）写入挂载卷，可选经 secretObjects 投影为普通 Secret。Pod 销毁即自动 revoke。

**动态引擎 vs 静态路径**：`database/creds/*` 每次读取都触发 Vault 现场在数据库里创建新账号；静态路径 `secret/data/*` 只是读预存值（KV 引擎）。前者是本实验的主题——凭证的使用即签发，不用即不存在。

**租约的边界（重要）**：CSI 驱动**不会**替挂载中的动态 Secret 续租——TTL 到期后文件里保持陈旧值，Pod 重建时才重新签发新凭证。长时间运行的 Pod 若依赖"凭证始终新鲜"，需要应用自行重建连接触发重挂载，或接受凭证过期由数据库连接断开暴露问题。

**secretObjects 是投影而非存储源**：挂载文件对多数应用最友好，但有些组件只认 env 或原生 Secret 引用。`secretObjects` 把 CSI 取到的内容同步成普通 K8s Secret——删除后随下次挂载重建，Vault 始终是唯一事实源。

## Q&A

**Q1: 生产环境的 Vault 怎么部署？**
dev 模式仅适合实验：数据在内存、单节点、自动 unseal。生产用 Raft 存储后端（集成存储，免维护单独的存储层）+ auto-unseal（KMS/AWS，避免人工保管 unseal key），并配审计设备（audit device）记录所有读取操作——审计在密钥系统里不是可选项。

**Q2: 同样的机制能管 TLS 证书吗？**
可以。Vault 的 PKI 引擎用同一套租约机制签发短期 TLS 证书，替代手工管理或作为 cert-manager 之外的另一条路——证书"短命化"后，私钥泄漏的窗口同样被压缩到 TTL 级别。

**Q3: 不想装 CSI 驱动有什么替代？**
External Secrets Operator（ESO）：用 controller 定期把 Vault 数据同步为 Secret。取舍是失去"按需挂载 + 租约联动"——ESO 同步的还是静态快照（定期轮询），动态引擎的"随 Pod 生灭"语义不再成立。需要动态凭证选 CSI，只需要"集中管理 + 定期轮换"的静态密钥，ESO 更轻。

**Q4: Vault 全挂了会怎样？**
CSI 默认缓存上次结果，存量 Pod 不受影响；但新 Pod 调度会失败（无法完成挂载），滚动发布也会被卡住。所以"Vault 不可用"要纳入故障演练：评估哪些服务的发布/扩容依赖它，并准备降级路径（如紧急切回静态 Secret 的预案）。
