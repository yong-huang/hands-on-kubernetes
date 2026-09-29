# 28 · GitOps 与 ArgoCD：声明式、版本化与自动纠偏

> GitOps 把"部署"变成一个纯声明式的收敛问题：**Git 仓库里的 YAML 就是期望状态，集群里的实际状态由集群内的控制器持续向它收敛**。ArgoCD 就是这样一个运行在集群内的控制器（CNCF 毕业项目）。读完本篇，你将理解 Pull 模型为什么更安全，并理解手改集群如何被 selfHeal 自动纠偏回 Git 版本。

## Background

传统部署是 CI 推动的：流水线构建完镜像，拿着 kubeconfig 对集群执行 `kubectl apply`。这套 Push 模型有三个反复被验证的隐患：CI 系统持有集群凭据，凭据一旦泄露整个集群门户大开；集群实际状态无人对账，有人手改了副本数没人知道；回滚靠重新跑流水线，慢且依赖 CI 系统可用。

GitOps 把方向反过来：集群内的 Agent 自己去拉 Git、自己对比、自己收敛。凭据不出集群，Git 成为唯一可信源，回滚变成一次 `git revert`。ArgoCD 和 Flux 是这条路线的两个 CNCF 毕业实现。

## What

GitOps 的三个关键词：

- **声明式（Declarative）**：描述"要什么"而不是"做什么"，任何状态都可以从 YAML 完整重建
- **版本化（Versioned）**：每次变更都是一次 commit，`git log` 即审计记录，`git revert` 即回滚
- **自动纠偏（Auto-remediating）**：有人手改集群？控制器发现漂移（drift，集群实际状态与 Git 期望状态的偏差）后自动改回 Git 版本

ArgoCD 只加了一个核心 CRD（自定义资源定义：向 API Server 注册的新资源类型）：`Application`——它把三件事绑在一起：从**哪个仓库的哪个路径**读期望状态、同步到**哪个集群的哪个命名空间**、用**什么策略**同步。

控制循环每隔约 3 分钟（可配置）对比 Git 与集群实时状态，不一致就按策略行动。

一句话心智模型：**集群的实际状态永远向 Git 的期望状态收敛**——可以把 ArgoCD 想象成"集群的自动对时器"；但和对时器不同的是，它修正的不是时间而是任意 K8s 对象，且"正确时间"由 Git 仓库定义。

## When to Use

典型场景：部署权限收敛（开发团队只提交 PR，不拿集群凭据）；环境漂移治理（手改的副本数被自动拉回）；多环境发布审计（`git log` 就是发布历史）。

何时不用：高频变色的临时调试环境（同步循环会跟手工调试打架，调试时暂停 sync）；非声明式的发布流程（依赖脚本逐步执行的业务逻辑不适合 GitOps）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| CI + kubectl apply（Push） | CI 持凭据、无对账 | 小团队起步期 |
| ArgoCD | UI 与多集群视图强 | 平台化、多团队视图需求 |
| Flux | 轻量、纯控制器 | CI 式纯自动化流水线 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；国内网络需预载 quay.io 镜像（见本节末尾）。

```bash
cd labs/28_gitops_argocd
./argocd.sh install   # 安装 ArgoCD（本地 vendor 清单，约 24500 行，离线可用）
./argocd.sh app       # 创建 guestbook Application
./argocd.sh status    # 观察 OutOfSync / Synced / Healthy 状态
./argocd.sh sync      # 手动/自动同步演示
./argocd.sh clean
```

Application 关键字段（`manifests/app-of-apps.yaml`）：

```yaml
spec:
  source:                        # 期望状态在哪
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD         # 跟踪分支/标签；固定 tag 则锁定版本
    path: guestbook              # 只监视仓库子目录
  destination:
    server: https://kubernetes.default.svc   # in-cluster 访问 API Server
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true                # Git 删 = 集群删
      selfHeal: true             # 手改会被改回 Git 版本
    syncOptions:
      - CreateNamespace=true     # namespace 不存在自动建
```

**国内网络注意**：ArgoCD 组件镜像托管在 quay.io，节点直接拉常 TLS 超时，需预载（同系列 `./load_images.sh` 思路）：

```bash
docker pull docker.m.daocloud.io/quay.io/argoproj/argocd:v2.13.3
docker tag  docker.m.daocloud.io/quay.io/argoproj/argocd:v2.13.3 \
           quay.io/argoproj/argocd:v2.13.3
for n in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
  docker save quay.io/argoproj/argocd:v2.13.3 \
    | docker exec --privileged -i "${n}" ctr --namespace=k8s.io images import -
done
```

版本号先 `grep quay.io argocd-install.yaml` 确认；redis 组件走 `docker.m.daocloud.io/library/redis`。

安装清单 `raw.githubusercontent.com` 直连不稳定，建议在能访问的机器下载后保存为本目录 `argocd-install.yaml`（脚本优先使用本地文件）。

ArgoCD 的 repo-server 也需要访问 github.com 拉示例仓库，若超时可换 gitee 镜像仓库或自建私有仓库。

## How It Works

**sync 策略：automated / prune / selfHeal**：

| 选项 | 不开会怎样 | 开了的效果 |
|------|-----------|-----------|
| `automated` | Git 变更只显示 OutOfSync，需手动点 Sync | 检测到差异自动 apply |
| `prune` | Git 里删掉的资源在集群里残留 | Git 删 = 集群删，不留孤儿资源 |
| `selfHeal` | 有人 `kubectl scale` 手改集群，漂移永久存在 | 自动把手改改回 Git 版本 |

`selfHeal` 是"自动纠偏"的落地：它保证 Git 是唯一可信源。若确有需要手改的场景（如 HPA——按负载自动调副本数的组件，见 lab 09），用 `ignoreDifferences` 告诉 ArgoCD 忽略指定字段的差异，而不是关闭 selfHeal。

**app-of-apps：用 Git 管理应用清单本身**：把"集群里该有哪些应用"也声明成 Git——一个**根 Application** 只监视一个装满子 Application YAML 的目录。往目录里 commit 一个新 YAML = 集群里多一个应用；

删掉文件（配合 prune）= 应用被移除。**新增一个应用的动作就是一次 git commit**，整个平台可以从一个根应用自举（bootstrap）出来。

**回滚怎么做**：`git revert` 一次 commit，ArgoCD 自动把集群收敛回旧版本——回滚、审计、变更评审全部复用 Git 工作流，这是 GitOps 最大的运营红利。

## Pitfalls & Q&A

踩坑清单：

- Application 资源**必须创建在 argocd 命名空间**，否则控制器不认。
- `targetRevision: HEAD` 永远追新，生产建议固定 tag/commit 以便审查。
- 删除 Application 时其 finalizer 会**连带删除它创建的所有资源**——想保留资源先去掉 finalizer。

**Q1: Git 里不能存明文 Secret，密钥怎么管？**

常用方案三选一：**Sealed Secrets**（集群外加密、只有集群内私钥能解）、SOPS + age/KMS（文件级加密，Git 里存密文）、External Secrets Operator（从 Vault/云 KMS 拉取，见 lab 22）。原则是 Git 只进加密后的内容，明文密钥永远不落仓库。

**Q2: ArgoCD 和 Flux 怎么选？**

都是 CNCF 毕业的 GitOps 引擎。ArgoCD 自带 Web UI、多集群管理与应用健康视图，重交互体验；Flux 更轻量、纯控制器组合、与 Kustomize/Helm 深度集成，重自动化流水线。

功能上已互相靠拢，选型看团队习惯：需要平台化 UI 和多团队视图选 ArgoCD，追求轻量和 CI 式纯自动化选 Flux。
