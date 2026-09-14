# GitOps 与 ArgoCD 详解：声明式、版本化与自动纠偏

## 1. 引言

传统部署方式（CI 里跑 `kubectl apply`）有三个隐患：CI 系统持有集群凭据（凭据一旦泄露，整个集群门户大开）、集群实际状态无人对账（有人手改了副本数，没人知道）、回滚靠重新跑流水线（慢且不可靠）。

GitOps 把"部署"变成一个纯声明式的收敛问题：**Git 仓库里的 YAML 就是期望状态，集群里的实际状态由集群内的控制器持续向它收敛**。三个关键词：

- **声明式（Declarative）**：描述"要什么"而不是"做什么"，任何状态都可以从 YAML 完整重建
- **版本化（Versioned）**：每次变更都是一次 commit，`git log` 即审计记录，`git revert` 即回滚
- **自动纠偏（Auto-remediating）**：有人手改集群？控制器发现漂移（drift）后自动改回 Git 版本

ArgoCD 就是这样一个运行在集群内的控制器，也是 CNCF 毕业项目。

## 2. 文件结构

```
28_gitops_argocd/
├── README.md                # 本文档
├── argocd.sh                # 演示脚本: install | app | status | sync | clean | all
├── manifests/
│   ├── app-of-apps.yaml     # Application CRD 示例: guestbook 应用 + app-of-apps 根应用(注释)
│   ├── argocd-install.yaml  # ArgoCD 官方安装清单(已 vendor 进仓库, 约 24500 行, 离线可用)
└── images/
    ├── gitops_loop.architecture.json  # 图源（Typed JSON IR）
    ├── gitops_loop.html               # 交互版架构图
    └── gitops_loop.svg                # 双主题矢量版（本文档 §6 内嵌）
```

安装清单 `manifests/argocd-install.yaml`（约 24500 行）已直接 vendor 进仓库，安装优先使用本地文件，无需联网。

## 3. 核心概念

### Application CRD：一个 CRD 说清"Git 里什么 = 集群里什么"

ArgoCD 只加了一个核心 CRD：`Application`。它把三件事绑在一起：从**哪个仓库的哪个路径**读期望状态、同步到**哪个集群的哪个命名空间**、用**什么策略**同步。ArgoCD 控制循环每隔约 3 分钟（可配置）对比 Git 与集群实时状态，不一致就按策略行动。

### sync 策略：automated / prune / selfHeal

| 选项 | 不开会怎样 | 开了的效果 |
|------|-----------|-----------|
| `automated` | Git 变更只显示 OutOfSync，需手动点 Sync | 检测到差异自动 apply |
| `prune` | Git 里删掉的资源在集群里残留 | Git 删 = 集群删，不留孤儿资源 |
| `selfHeal` | 有人 `kubectl scale` 手改集群，漂移永久存在 | 自动把手改改回 Git 版本 |

`selfHeal` 是"自动纠偏"的落地：它保证 Git 是唯一可信源。若确有需要手改的场景（如 HPA 调副本数），用 `ignoreDifferences` 告诉 ArgoCD 忽略指定字段的差异，而不是关闭 selfHeal。

### app-of-apps：用 Git 管理应用清单本身

把"集群里该有哪些应用"也声明成 Git：一个**根 Application** 只监视一个装满子 Application YAML 的目录。往目录里 commit 一个新 YAML = 集群里多一个应用；删掉文件（配合 prune）= 应用被移除。于是**新增一个应用的动作就是一次 git commit**，整个平台可以从一个根应用自举（bootstrap）出来。

### Pull 模型 vs Push 模型

- **Push（传统 CI/CD）**：CI 在集群外，构建完拿着 kubeconfig 主动推。凭据散落在 CI 系统，CI 与部署耦合，漂移无人检测
- **Pull（GitOps）**：Agent（ArgoCD）跑在集群内，自己拉 Git、自己对比、自己 apply。集群凭据不出集群；CI 只负责构建镜像和改 YAML，部署完全解耦

## 4. YAML 关键字段

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

易踩的坑：

- Application 资源**必须创建在 argocd 命名空间**，否则控制器不认
- `targetRevision: HEAD` 永远追新，生产建议固定 tag/commit 以便审查
- 删除 Application 时其 finalizer 会**连带删除它创建的所有资源**——想保留资源先去掉 finalizer

## 5. 国内网络注意事项

- **quay.io 镜像**：ArgoCD 组件镜像（argocd-server / repo-server / applicationset-controller / dex）托管在 quay.io，节点直接拉常 TLS 超时。预载方法（同系列 `./load_images.sh` 思路）：
  ```bash
  docker pull docker.m.daocloud.io/quay.io/argoproj/argocd:v2.13.3
  docker tag  docker.m.daocloud.io/quay.io/argoproj/argocd:v2.13.3 \
             quay.io/argoproj/argocd:v2.13.3
  for n in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
    docker save quay.io/argoproj/argocd:v2.13.3 \
      | docker exec --privileged -i "${n}" ctr --namespace=k8s.io images import -
  done
  ```
  版本号先 `grep quay.io argocd-install.yaml` 确认；redis 组件走 `docker.m.daocloud.io/library/redis`
- **github 下载清单**：`raw.githubusercontent.com` 直连不稳定，建议在能访问的机器下载后保存为本目录 `argocd-install.yaml`，脚本会优先使用本地文件
- **示例仓库克隆**：ArgoCD 的 repo-server 也需要访问 github.com 拉 argocd-example-apps，若超时可换 gitee 镜像仓库或自建私有仓库

## 6. 可视化

![GitOps 闭环](images/gitops_loop.svg)

闭环一条线：开发者 `git push`（声明式变更）→ Git 仓库保存**期望状态** → ArgoCD（集群内）pull 期望状态、与**实际状态** diff → `sync` 收敛（prune / selfHeal）。红色警告线是反面剧情：有人 `kubectl scale` 手改集群 = 漂移，selfHeal 会把它改回 Git 版本——Git 因此成为唯一可信源。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/28_gitops_argocd/images/gitops_loop.html)（或本地打开 [`images/gitops_loop.html`](images/gitops_loop.html)）。

## 7. 深入要点

1. **GitOps vs 传统 CI/CD**：Pull 模型，Agent 在集群内自己拉取期望状态并收敛，集群凭据不出集群；CI 只管构建镜像与提交 YAML，部署与构建解耦。安全边界从"信任 CI"变成"信任 Git + 审计链"。
2. **selfHeal 的作用**：检测并纠正集群侧漂移（有人 `kubectl edit/scale` 手改），保证 Git 是唯一可信源；配合 `prune` 让"删除"也是声明式的。需要合法手改时用 `ignoreDifferences` 精确豁免字段。
3. **密钥管理**：Git 仓库不能存明文 Secret。常用方案：**Sealed Secrets**（集群外加密、只有集群内私钥能解）、 SOPS + age/KMS、或 External Secrets Operator（从 Vault/云 KMS 拉取），ArgoCD 只同步加密后的安全内容。
4. **回滚怎么做**：`git revert` 一次 commit，ArgoCD 自动把集群收敛回旧版本——回滚、审计、变更评审全部复用 Git 工作流，这是 GitOps 最大的运营红利。
5. **ArgoCD vs Flux**：都是 CNCF 毕业的 GitOps 引擎。ArgoCD 自带 Web UI、多集群管理与应用健康视图，重交互体验；Flux 更轻量、纯控制器组合、与 Kustomize/Helm 深度集成，重自动化流水线。功能上已互相靠拢，选型看团队习惯。

## 8. 总结

GitOps = 声明式期望状态（Git）+ 集群内控制器（ArgoCD）+ 持续对账收敛（automated/prune/selfHeal）。记住一条主线：**集群的实际状态永远向 Git 的期望状态收敛**，app-of-apps、ignoreDifferences、git revert 回滚都围绕它展开。配合 `argocd.sh` 的 install → app → status → sync 演示，注意 quay.io 镜像预载与 github 清单缓存，就能在 kind 集群上完整跑通第一个 GitOps 应用。
