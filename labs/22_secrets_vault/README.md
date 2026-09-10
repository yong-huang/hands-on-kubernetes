# Secrets 管理（Vault 集成）

## 1. 文件结构

```
22_secrets_vault/
├── README.md               # 本文档
├── vault_setup.sh          # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── vault_secrets.yaml  # 演示用的 K8s 清单
└── images/
    ├── vault_dynamic.architecture.json  # 图源（Typed JSON IR）
    ├── vault_dynamic.html               # 交互版架构图
    └── vault_dynamic.svg                # 双主题矢量版（本文档 §5 内嵌）
```

## 2. 项目概述

原生 K8s Secret 是 base64 编码的明文：写进 Git 会泄漏，存进 etcd 跟着备份到处跑，且从不轮换。本项目（`vault_secrets.yaml` + `vault_setup.sh`）用 **HashiCorp Vault + Secrets Store CSI Driver** 替换这条路径：应用 Pod 不再持有长期密码，而是在挂载卷的瞬间由 Vault 的数据库动态引擎**现场生成一组临时凭证**（TTL 1h），Pod 销毁即自动吊销——目标是让"Pod 从 Vault 动态获取数据库凭证"成为默认姿势。

---

## 3. 核心机制解析

### 1. SecretProviderClass：声明式的取数配置

```yaml
spec:
  provider: vault
  parameters:
    roleName: "demo-app"
    objects: |
      - objectName: "username"
        secretPath: "database/creds/demo-app"
```

它不是 Secret 本身，而是告诉 CSI 驱动"去哪取、取什么"。注意 `database/creds/*` 前缀——这不是 KV 存储路径，而是**动态引擎**：每次读取都会触发 Vault 现场在 PostgreSQL 里 `CREATE ROLE` 一个新账号（演示用 PostgreSQL 部署在 `vault-demo` 命名空间，管理员账号由 `vault_setup.sh config` 步骤写入引擎配置）。静态路径 `secret/data/*` 则只是读预存值。

### 2. K8s Auth：Pod 身份换 Vault Token

```bash
vault write auth/kubernetes/role/demo-app \
  bound_service_account_names=demo-app \
  bound_service_account_namespaces=vault-demo policies=demo-app ttl=1h
```

CSI 驱动拿 Pod 的 ServiceAccount projected token 去 Vault 换取短期 Vault token——集群内不需要存任何 Vault 凭证。`bound_service_account_*` 把信任范围钉死到具体 SA 和命名空间，防止别的负载冒名。

### 3. 租约（Lease）：动态凭证的灵魂

```bash
vault write database/roles/demo-app default_ttl=1h max_ttl=24h ...
```

每份凭证绑定租约：超过 TTL/max_ttl 即作废、Pod 删除时 CSI 驱动主动 revoke。注意 CSI 驱动**不会**替挂载中的动态 Secret 续租——TTL 到期后文件里保持陈旧值，Pod 重建时才重新签发新凭证。效果是数据库里存在大量短命账号，任何一个泄漏都只在 TTL 窗口内有效。这与静态 Secret"一次生成、永不轮换"形成本质区别。

### 4. secretObjects 双通道

```yaml
secretObjects:
  - secretName: db-creds-synced
    data: [{objectName: username, key: db_user}]
```

挂载文件对多数应用最友好，但有些组件只认 env 或原生 Secret 引用。`secretObjects` 把 CSI 取到的内容同步成普通 K8s Secret——注意它是**投影**而非存储源，删除后随下次挂载重建。

---

## 4. 可视化

![Vault 动态凭证](images/vault_dynamic.svg)

图中主链是动态注入四步：Pod 挂载触发 CSI 驱动 → 拿 SA projected token 走 K8s Auth 换取短期 Vault token → 动态引擎让 PostgreSQL 现场 `CREATE ROLE` → 临时凭证（TTL 1h）写入挂载卷，可选经 secretObjects 投影为普通 Secret。Pod 销毁即自动 revoke——任何泄漏只在 TTL 窗口内有效。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/22_secrets_vault/images/vault_dynamic.html)（或本地打开 [`images/vault_dynamic.html`](images/vault_dynamic.html)）。

---

## 5. 工程延伸

- **HA 部署**: dev 模式仅适合实验；生产用 Raft 存储后端 + auto-unseal（KMS/AWS），并配审计设备
- **PKI 引擎**: 同样机制可签发短期 TLS 证书，替代手工 cert-manager 之外的另一条路
- **External Secrets Operator**: 若不想装 CSI 驱动，ESO 用 controller 定期把 Vault 数据同步为 Secret——取舍是失去"按需挂载 + 租约联动"
- **应急演练**: 把"Vault 全挂"纳入故障演练——CSI 默认缓存上次结果，但新 Pod 调度会失败，需评估依赖面
