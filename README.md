# hands-on-kubernetes

> Kubernetes 动手学习系列：31 个实验与 10 个微服务项目已全部在本地 kind 集群验证过，10 个 Operator 项目完成并验证 7 个（进行中）。读完这个仓库的任意一篇，你都能照着脚本跑通并理解背后的机制。

## Background

学 Kubernetes 的常见起点是读文档或看视频：概念都"懂了"，上手创建一个 Pod（Kubernetes 最小部署单位：一个或一组同机共生、统一调度的容器）还是要现查命令。

另一条极端是直接读生产系统：权限受限、不敢实验、坏了影响别人。两条路之间缺一环——**可以随便搞坏、搞坏秒重建、每一步都有验收的本地实验环境**。

本仓库补的就是这一环：全部实验跑在 kind（Docker 容器模拟节点）搭建的本地集群上，每个实验自带一键脚本（apply → observe → clean）和验收步骤。三条学习线由此展开：labs 打基础，operators 练开发，microservices 学组装。

## What

hands-on-kubernetes 是一个动手学习系列仓库，包含三条学习线：

| 线 | 目录 | 内容 | 状态 |
|---|---|---|---|
| 实验线 | `labs/` | 31 个实验（00 是工具准备）：工作负载、网络、存储、安全、可观测、平台工程 | ✅ 全部完成 |
| Operator 线 | `operators/` | 10 个 kubebuilder 项目：资源编排到 AI 工作负载 | 🚧 7/10 |
| 微服务线 | `mart/` | mini-mart 迷你电商：10 个项目共同生长的系统 | ✅ 10/10 |

一句话心智模型：**labs 是"学会零件"，operators 是"学会造工具"，microservices 是"学会组装机器"**。

但和三本独立教材不同的是，三条线共享同一个集群和一套脚本约定，operator 与微服务实验会直接引用 labs 里建立的机制（如 labs/31 的 fake GPU 设备插件、labs/02 的探针健康检查）。

每个实验的统一结构：教程 README、K8s 清单（manifests/）、一键演示脚本（xxx.sh，支持分步执行）、架构图（images/，可交互 HTML + 双主题 SVG，共 41 张；README 均为纯文字，不内嵌图）。

GitHub Pages 开启后可[在线查看架构图](https://yong-huang.github.io/hands-on-kubernetes/)，本地用浏览器打开 `images/*.html` 也可以。

## When to Use

典型场景：零基础想系统上手 K8s（按 labs 顺序做）；会 K8s 想学 Operator 开发（operators 01 起步，Go/kubebuilder）；想看微服务模式在真实系统里的组装（mart 按序生长）。

何时不用：找生产级最佳实践或运维手册（这是学习仓库，简化了真实环境的复杂度）；需要托管方案的教程（全仓库面向本机 kind；唯一例外是 mart 项目 9 的 CI 默认用 GitHub Actions 免费额度，附离线 fallback）。

同类资源对比：

| 资源 | 差异 | 什么时候选它 |
|---|---|---|
| 官方文档 / kubernetes.io tutorials | 权威但偏参考手册 | 查语法与 API |
| 本仓库 | 每实验可跑、可验收、中文 | 系统性动手入门 |
| 生产运维手册（Google SRE 等） | 面向真实系统 | 已有基础后的进阶 |

## Quick Start

前置条件：Docker 已安装（kind 以容器模拟节点）；国内网络建议先配镜像加速。

```bash
cd labs/00_setup_kind
./setup_kind.sh          # 安装 kind + kubectl（未装过才需要）

cd ../01_setup_env
./setup.sh up            # 建学习集群 k8s-learn（1 控制面 + 2 工作节点）
kubectl get nodes        # 诚实预期：3 个节点 Ready

cd ../03_deploy
./deploy.sh              # 第一个正式实验：依次执行全部步骤
./deploy.sh scale        # 或只执行某一步（步骤列表见脚本头部注释）
```

版本要求：kind ≥ 0.20、kubectl ≥ 1.28（节点镜像不锁定版本）。部分实验额外需要 helm（27）、istioctl（13）、velero CLI（18）、trivy/cosign（21）、karmadactl（30），见各实验 README。

海外网络下实验镜像均可直接拉取；国内网络批量预载镜像到 kind 节点用公共脚本：

```bash
scripts/load_images.sh [image1 image2 ...]   # 无参数时加载默认列表
```

## How It Works

**labs 实验列表**（建议按序学习，路线设计见下）：

| # | 实验 | 主题 |
|---|------|------|
| 00 | [工具准备](labs/00_setup_kind/README.md) | 安装 kind + kubectl |
| 01 | [环境搭建](labs/01_setup_env/README.md) | kind 本地集群：拓扑、CNI（容器网络接口插件，负责给 Pod 分配集群内 IP 并打通连通性）、验证 |
| 02 | [Pod](labs/02_pod/README.md) | 最小调度单元、生命周期、探针 |
| 03 | [Deployment](labs/03_deploy/README.md) | 自愈、扩缩容、滚动更新与回滚 |
| 04 | [Service](labs/04_service/README.md) | 服务发现与负载均衡 |
| 05 | [ConfigMap/Secret](labs/05_cm_secret/README.md) | 配置与代码分离 |
| 06 | [Job/CronJob](labs/06_job_cronjob/README.md) | 一次性任务与定时任务 |
| 07 | [DaemonSet](labs/07_daemonset/README.md) | 每节点一个 Pod 的守护进程 |
| 08 | [StatefulSet](labs/08_statefulset/README.md) | 稳定标识、独立存储、有序编排 |
| 09 | [HPA](labs/09_hpa/README.md) | 自动扩缩容原理与实战 |
| 10 | [亲和性](labs/10_affinity/README.md) | nodeAffinity/podAffinity/拓扑打散 |
| 11 | [Ingress](labs/11_ingress/README.md) | 七层域名与路径路由 |
| 12 | [NetworkPolicy](labs/12_network_policy/README.md) | 默认拒绝与白名单隔离 |
| 13 | [Service Mesh](labs/13_service_mesh/README.md) | Istio sidecar（注入到业务 Pod 旁的代理容器）与金丝雀发布（新版本先放小比例流量验证） |
| 14 | [DNS 服务发现](labs/14_dns_discovery/README.md) | ClusterIP、Headless 与 Pod 级域名 |
| 15 | [PV/PVC](labs/15_pv_pvc/README.md) | 静态供给、绑定机制与回收策略 |
| 16 | [StorageClass](labs/16_storageclass/README.md) | 动态供给、延迟绑定与 CSI（容器存储接口） |
| 17 | [CSI 快照](labs/17_csi_snapshot/README.md) | VolumeSnapshot、dataSource 还原 |
| 18 | [Velero 迁移](labs/18_velero_migration/README.md) | 有状态应用备份与跨集群迁移 |
| 19 | [RBAC](labs/19_rbac/README.md) | 角色、绑定与最小权限原则 |
| 20 | [Pod Security](labs/20_pod_security/README.md) | Pod 安全标准（PSS）三等级与 PSA 准入控制（namespace 级安全配置强制） |
| 21 | [镜像安全](labs/21_image_security/README.md) | Trivy 扫描、Cosign 签名、Kyverno 准入 |
| 22 | [Vault](labs/22_secrets_vault/README.md) | Secret 管理与 Vault 集成 |
| 23 | [Prometheus/Grafana](labs/23_prometheus_grafana/README.md) | 监控体系 |
| 24 | [EFK 日志](labs/24_logging_efk/README.md) | 日志收集 Stack |
| 25 | [Jaeger](labs/25_jaeger_tracing/README.md) | 分布式追踪 |
| 26 | [Ephemeral Debug](labs/26_ephemeral_debug/README.md) | 临时调试容器排障 |
| 27 | [Helm](labs/27_helm_chart/README.md) | Chart 开发全流程：lint→install→package |
| 28 | [ArgoCD](labs/28_gitops_argocd/README.md) | GitOps 声明式持续交付 |
| 29 | [CRD Controller](labs/29_crd_controller/README.md) | 自定义资源与调谐循环 |
| 30 | [Karmada](labs/30_multicluster_federation/README.md) | 多集群联邦管理 |
| 31 | [Fake GPU Operator](labs/31_fake_gpu_operator/README.md) | GPU Operator 与 AI Ops 体验 |

**建议学习路线**（labs 内部的六段坡道）：

1. **基础（01–09）**：环境 → 工作负载 → 网络 → 配置 → 弹性，理解"声明式 API + 控制循环"这条主线
2. **调度与网络进阶（10–14）**：调度约束、七层路由、网络隔离、服务网格、DNS 内幕
3. **存储（15–18）**：从静态 PV 到动态供给、快照、备份迁移
4. **安全（19–22）**：RBAC、Pod 准入、镜像供应链、密钥管理
5. **可观测性（23–26）**：监控、日志、追踪、排障
6. **平台工程（27–31）**：Helm、GitOps、CRD 扩展、多集群、Operator

**三条学习线的清单文档**（含逐项验收标准、AI 开始提示词、踩坑记录），落地代码分别在 `labs/`、`operators/`、`mart/`：

| 清单 | 内容 | 状态 |
|:--|:--|:--|
| [kubernetes.md](docs/kubernetes.md) | 31 个实验的总清单（与 labs/ 一一对应） | ✅ 31/31 |
| [kubernetes_operator.md](docs/kubernetes_operator.md) | 10 个 Operator 开发项目（kubebuilder） | 🚧 7/10（项目 5 代码完成待修，7、10 未勾选） |
| [microservices.md](docs/microservices.md) | mini-mart 微服务开发（Go/Python 双栈） | ✅ 10/10 |
| [TESTING.md](docs/TESTING.md) | 全仓测试报告与回归指南 | ✅ |

## Pitfalls & Q&A

踩坑清单：

- 跳过 labs/01 直接做后续实验：没有 k8s-learn 集群，所有脚本第一步就失败。
- 每个实验做完不 clean：残留资源占用端口与内存，后面的实验可能因端口冲突失败。
- 国内网络不预载镜像：特定实验（13/21/28 等）节点拉镜像超时，README 内均有预载指引。

**Q1: 从哪个实验开始？**
零基础按 00 → 01 → 02 顺序；已会基础概念的可从任意感兴趣的开始——每个实验 README 自包含，前提依赖（如集群、镜像预载）都在各自 Quick Start 标注。operators 线需要 Go 基础，mart 线需要 Go + Python 双语言。

**Q2: 实验做完集群怎么处理？**
单实验资源用各自的 `xxx.sh clean` 清理；整个集群用 `./setup.sh down`（labs/01）或 `kind delete cluster --name k8s-learn` 删掉重建，零残留——实验之间互不污染靠的就是"随手删、随手建"。

**Q3: 内容可以转载或用于培训吗？**
可以。[MIT](LICENSE) 许可——实验代码与文档可自由使用、修改和分发，保留版权声明即可。
