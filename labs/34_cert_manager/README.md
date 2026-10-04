# 34 · cert-manager：证书自动化签发与续期

> lab 11 的 Ingress 要 TLS、lab 13 的 mesh 要 mTLS 证书、几乎每个生产服务都要证书——手工签发（openssl + kubectl create secret）的流程谁也坚持不了三个月。cert-manager 把证书变成声明式资源：声明"我要 a.example.com 的证书"，签发、落盘、到续期全部自动。读完本篇，你将建立两级 CA 信任链并亲眼看到证书被"原地换新"。

## Background

证书管理的传统流程是：openssl 生成 CSR（Certificate Signing Request，写明域名等申请信息、交给 CA 签字的文件）、找 CA（Certificate Authority，证书颁发机构）签名（或买商业证书）。

接着 kubectl create secret tls 落盘，到期前人工记得换——每一环都靠日历提醒，忘了就是生产故障页。

更麻烦的是"每个 Ingress 都要证书"这种规模化管理：几十个域名，几十份私钥散落在 Secret 里，没有统一的签发记录与续期策略。

cert-manager 把证书纳入 K8s 声明式体系：`Certificate` 资源声明"要什么证书"，Issuer 声明"由谁签"，签发、写 Secret、临近到期自动续期全部由控制器完成——证书从运维流程变成一种 K8s 对象。

## What

cert-manager 的核心是"两级签发"模型：

| 资源 | 角色 |
|------|------|
| ClusterIssuer / Issuer | 签发者：self-signed（自签名，用自己的私钥给自己签）、CA、ACME（Let's Encrypt）等类型 |
| Certificate | 用户的证书申请：域名、有效期、续期窗口、落到哪个 Secret |
| Secret（产物） | 自动写入的 `tls.crt` / `tls.key`，lab 11 Ingress 引用的就是它 |

一句话心智模型：**Certificate 是证书的"rental 合同"，cert-manager 是自动续租的管家**——但和租房不同，续期时给你的是一张全新的证书而不是旧证书延期：NotBefore 会刷新，Secret 原地换新。

本实验建立两级信任链：`self-signed ClusterIssuer` 签出**根 CA**（`isCA: true` 的 Certificate），根 CA 再喂给 **CA ClusterIssuer**——所有业务证书由这把 CA 签发，客户端只要信任根 CA 即可。

## When to Use

典型场景：内部服务的 HTTPS 证书统一签发（CA Issuer + 客户端信任根 CA）；对接 Let's Encrypt 给公网域名自动续期（ACME HTTP-01/DNS-01）；给 mesh / webhook / 数据库 TLS 提供证书源。

何时不用：公网证书已有云厂商托管（ALB 终止 TLS 等）；只需要一个测试用的自签证书（openssl 两条命令更快，不值得装一套控制器）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 手工 openssl + Secret | 一次性的、续期靠人 | 临时调试 |
| cert-manager（本实验） | 声明式、自动续期、多 Issuer 类型 | K8s 集群证书管理的事实标准 |
| 云厂商证书服务 | 托管免运维 | 云 LB 终止 TLS 的场景 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。cert-manager 清单从 GitHub 下载（镜像在 quay.io，国内集群可直接拉取，见 labs/01 的镜像源说明）。

```bash
cd labs/34_cert_manager
./cert.sh install   # 安装 cert-manager (controller/webhook/cainjector)
./cert.sh deploy    # self-signed -> CA 两级签发, 签出 a.example.com 证书
./cert.sh verify    # openssl 验证签发链/域名/有效期
./cert.sh rotate    # 改域名触发自动重签
./cert.sh clean
```

`verify` 步骤的真实输出（节选）：

```
issuer=CN=demo-root-ca
subject=O=hands-on-kubernetes, CN=a.example.com
notBefore=Oct  2 03:04:20 2026 GMT
notAfter=Dec 31 03:04:20 2026 GMT
--- DNS 名称 ---
X509v3 Subject Alternative Name:
    DNS:a.example.com
```

`rotate` 步骤的真实输出（节选）：

```
certificate.cert-manager.io/a-example-com patched
X509v3 Subject Alternative Name:
    DNS:a.example.com, DNS:b.example.com
```

诚实预期：`install` 后三个组件（controller/webhook/cainjector）要全部 Ready 才能签发；Certificate 从创建到 READY 约 5-10 秒（自签链最快，ACME 要过公网验证会慢得多）。

## How It Works

**两级信任链的建立**：第一步用 self-signed ClusterIssuer 给一张 `isCA: true` 的 Certificate 签出根 CA（落在 Secret `demo-root-ca`）。

第二步创建 `spec.ca.secretName: demo-root-ca` 的 CA ClusterIssuer——它读这把私钥给所有业务证书签名。

你在 `verify` 步骤看到的 `issuer=CN=demo-root-ca`，就是这条链在起作用：业务证书由我们的 CA 签发，把根 CA 分发给客户端后整条信任链闭环。

**签发是控制循环**：Certificate 对象创建后，cert-manager 对比"期望的证书"与 Secret 里的现状——不存在、快到期或配置变化，就向 Issuer 请求新证书。

新证书写回 Secret 并更新 Certificate 的 READY 条件。你在 `deploy` 输出看到的 `condition met`，就是这个循环的收敛信号。

**续期窗口 `renewBefore`**：本实验 `duration: 2160h`（90 天）+ `renewBefore: 1440h`（到期前 60 天开始续）——cert-manager 在窗口内自动重签，Secret 原地换新、引用它的 Pod 无需重启。

`rotate` 步骤的域名变化立即触发重签，SAN（Subject Alternative Name，即 verify 输出里的 X509v3 Subject Alternative Name 字段）多出 `b.example.com`。

对照 lab 05"Secret 不自动轮换"的静态局限——这正是"证书的动态语义"与"配置的静态语义"的分野。

## Pitfalls & Q&A

踩坑清单：

- Issuer 是命名空间级、ClusterIssuer 是集群级——业务证书跨命名空间引用签发者时必须用 ClusterIssuer。
- `isCA: true` 忘了加：根 CA 签不出下一级，CA Issuer 直接报错。
- 证书 READY=False 先看 `kubectl describe certificate` 的 Events，多数是 Issuer 名字/类型写错或 ACME 验证未过。

**Q1: 和 lab 11 的 tls.secretName 什么关系？**
lab 11 的 Ingress 里 `tls.secretName` 引用的 Secret，传统流程要手工 `kubectl create secret tls` 准备。

本实验证明这个 Secret 可以由 Certificate 自动生成并持续续期。

两者对接后，"Ingress + Certificate"就是生产 HTTPS 的完整声明。

**Q2: 内部服务的客户端怎么信任这套 CA？**
把根 CA 的 `tls.crt`（demo-root-ca Secret 里）分发给客户端：进程内加信任库，或作为 ConfigMap 挂进 Pod 的 CA 目录。

服务间 mTLS 场景同理——这也是 lab 22 Vault PKI 引擎的同款思路，区别是签发引擎不同。

**Q3: 公网域名怎么自动续期？**
换 ACME 类型的 ClusterIssuer（Let's Encrypt）：HTTP-01 验证需要公网可达的路由（cert-manager 自动建临时 Ingress）。

DNS-01 验证则靠 DNS 提供商的 API 凭据（支持泛域名）。kind 本地练不了 ACME 的验证环节，但 Issuer/Certificate 的声明方式与本实验完全一致。
