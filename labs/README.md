# 🧪 labs：Kubernetes 动手实验（工具准备 + 34 实验，kind 本地集群）

> 来源：`docs/kubernetes.md` 清单（34/34）的落地实验，路线从工作负载到平台工程，全部在本机 kind（用 Docker 容器模拟节点的本地 K8s 工具）集群真机跑通。与兄弟系列的关系：labs 是地基——operators 线（Operator 开发）与 mart 线（微服务组装）直接复用这里建立的 k8s-learn 集群与机制。每实验统一结构：六段式教程 README + K8s 清单（多数为 `manifests/`，32 为 base + overlay）+ 一键脚本（apply → observe → clean，支持分步执行）+ `images/` 架构图（00 无图，32–34 仅 SVG），目录形态以各自 README 为准。

进度：**34/34 (100%)**　██████████

## 🚀 快速开始

前置：Docker 已安装；工具未装先跑 [00 工具准备](00_setup_kind/README.md)。以下命令在仓库根执行。

```bash
cd labs/01_setup_env
./setup.sh up            # 建 k8s-learn 集群（1 控制面 + 2 工作节点）+ 验证 + 预载镜像
kubectl get nodes        # 诚实预期：3 个节点 Ready
cd ../03_deploy
./deploy.sh              # 第一个正式实验：依次执行全部步骤（./deploy.sh scale 只执行某一步）
```

诚实预期：首次建集群要拉节点镜像，分钟级等待属正常；每实验做完跑各自的 `./xxx.sh clean`，残留资源会让后面的实验因端口冲突失败。

## 📚 实验总表

| # | 实验 | 一句话产出 |
|:--|:--|:--|
| 00 | [工具准备](00_setup_kind/README.md) | 装好 kind + kubectl 并验证版本，具备跑通全系列的最低环境 |
| 01 | [环境搭建](01_setup_env/README.md) | 一条命令建起 1 控制面 + 2 工作节点的集群并验证，一条命令删干净零残留 |
| 02 | [Pod](02_pod/README.md) | 跑通含 pause / initContainer / sidecar / 探针 4 种示例的演示 |
| 03 | [Deployment](03_deploy/README.md) | 演示自愈、扩缩容、滚动更新与回滚的完整时序 |
| 04 | [Service](04_service/README.md) | 分清四种 Service 类型与三个端口字段，掌握"Service 不通"的第一排查动作 |
| 05 | [ConfigMap/Secret](05_cm_secret/README.md) | 掌握四种注入方式与热更新铁律，看到 Secret 安全性的真实边界 |
| 06 | [Job/CronJob](06_job_cronjob/README.md) | 跑通 completions × parallelism 组合语义与两种失败处理路径 |
| 07 | [DaemonSet](07_daemonset/README.md) | 验证副本数由节点数决定，以及 tolerations / nodeAffinity 两道覆盖开关 |
| 08 | [StatefulSet](08_statefulset/README.md) | 用模拟 MySQL 主从验证稳定域名、独立存储与有序编排 |
| 09 | [HPA](09_hpa/README.md) | 掌握核心公式与指标链路前置条件，亲眼看自动扩缩与慢缩容 |
| 10 | [亲和性](10_affinity/README.md) | 跑通 nodeAffinity / podAffinity / 拓扑打散，看 maxSkew 拒绝调度 |
| 11 | [Ingress](11_ingress/README.md) | 用域名 + 路径 + TLS 终止跑通七层路由 |
| 12 | [NetworkPolicy](12_network_policy/README.md) | 从默认拒绝开始搭白名单隔离并验证连通性 |
| 13 | [Service Mesh](13_service_mesh/README.md) | 注入 Istio sidecar，按流量权重跑通金丝雀发布 |
| 14 | [DNS 服务发现](14_dns_discovery/README.md) | 分清 ClusterIP / Headless / Pod 三种域名，弄懂 ndots:5 |
| 15 | [PV/PVC](15_pv_pvc/README.md) | 掌握绑定三条件与生命周期状态机，追踪删 PVC 后 PV 的去向 |
| 16 | [StorageClass](16_storageclass/README.md) | 一份 StorageClass 让 PVC 动态供给精确大小的 PV，理解延迟绑定 |
| 17 | [CSI 快照](17_csi_snapshot/README.md) | 跑通卷快照，并用 dataSource 从快照还原出新卷 |
| 18 | [Velero 迁移](18_velero_migration/README.md) | 完成有状态应用的备份与跨集群迁移 |
| 19 | [RBAC](19_rbac/README.md) | 用 `can-i` 与 `--as` 验证四件套最小权限组合 |
| 20 | [Pod Security](20_pod_security/README.md) | 看同一个特权 Pod 在三个 namespace 命运迥异的演示 |
| 21 | [镜像安全](21_image_security/README.md) | Trivy 扫描 + Cosign 签名 + Kyverno 准入，拦下带高危漏洞的镜像 |
| 22 | [Vault](22_secrets_vault/README.md) | 应用 Pod 经 CSI Driver 现场取得 Vault 动态短期数据库凭证 |
| 23 | [Prometheus/Grafana](23_prometheus_grafana/README.md) | 部署 kube-prometheus-stack，用 ServiceMonitor / PrometheusRule 声明式监控 |
| 24 | [EFK 日志](24_logging_efk/README.md) | Fluent Bit → Elasticsearch → Kibana，全部 Pod 日志一处可查 |
| 25 | [Jaeger](25_jaeger_tracing/README.md) | 三个微服务（front → order → payment）的调用链在 Jaeger 可见 |
| 26 | [Ephemeral Debug](26_ephemeral_debug/README.md) | 用 kubectl debug 的三种姿势排查进不去 exec 的黑盒 Pod |
| 27 | [Helm](27_helm_chart/README.md) | 从零写 Chart，走完 lint → install → package 全流程 |
| 28 | [ArgoCD](28_gitops_argocd/README.md) | 手改集群被 selfHeal 自动纠偏回 Git 版本 |
| 29 | [CRD Controller](29_crd_controller/README.md) | 自定义 Database CRD + Reconcile 循环的最小 Operator 闭环 |
| 30 | [Karmada](30_multicluster_federation/README.md) | 6 副本按 4:2 权重拆到双集群，并演练失联故障转移 |
| 31 | [Fake GPU Operator](31_fake_gpu_operator/README.md) | 普通节点模拟 nvidia.com/gpu，跑通按卡调度与配额 |
| 32 | [Kustomize](32_kustomize_overlay/README.md) | 一套 base + dev/staging overlay 渲染两个环境，看懂哈希滚动 |
| 33 | [Gateway API](33_gateway_api/README.md) | 用 Envoy Gateway 跑通域名/路径/权重三种 HTTPRoute 路由 |
| 34 | [cert-manager](34_cert_manager/README.md) | 建立两级 CA 信任链，亲眼看证书自动续期 |

## 🧭 学习路线

主线按序号走，三篇进阶实验在对应位置插读：

1. **基础（01–09）**：环境 → 工作负载 → 网络 → 配置 → 弹性，理解"声明式 API + 控制循环"这条主线
2. **调度与网络（10–12）**：调度约束、七层路由、网络隔离 → 插读 **33·Gateway API**（Ingress 的官方继任者，趁 Ingress 记忆新鲜对照着读）
3. **服务治理（13–14）**：服务网格、DNS 内幕
4. **存储（15–18）**：从静态 PV 到动态供给、快照、备份迁移
5. **安全（19–20）**：RBAC、Pod 准入 → 插读 **34·cert-manager**（给 11 的 TLS 字段补上自动签发与续期）
6. **镜像与密钥（21–22）**：镜像供应链、Vault 动态凭证
7. **可观测性（23–26）**：监控、日志、追踪、排障
8. **平台工程（27，插读 32·Kustomize，再 28–31）**：Helm → Kustomize（Helm 的另一半，ArgoCD 常见前置）→ GitOps、CRD 扩展、多集群、Operator

> 编号是实验的身份证（= 创建顺序），不是阅读顺序——按本路线读，三篇进阶实验会出现在它们最有参照价值的位置。

## 🖼️ 架构图

多数实验 `images/` 内有可交互 HTML 与双主题 SVG（00 无图，32–34 仅有 SVG；全系列共 44 张图）。

本地用浏览器打开 `images/*.html`（32–34 直接打开 `.svg`），或看 GitHub Pages 在线版：<https://yong-huang.github.io/hands-on-kubernetes/>。

## ⚠️ 预期失败诚实标注

- 跳过 01 直接做后续实验：没有 k8s-learn 集群，所有脚本第一步就失败。
- 实验做完不 clean：残留资源占用端口与内存，后面的实验可能因端口冲突失败。
- 国内网络不预载镜像：13 / 21 / 28 等实验节点拉镜像超时，用 `scripts/load_images.sh` 预载。

## 🔧 环境要求

- 基线：Docker；kind ≥ 0.20、kubectl ≥ 1.28（labs/00 一键安装，节点镜像不锁版本）。
- 按实验额外：istioctl（13）、velero CLI（18）、trivy / cosign（21）、helm（27）、karmadactl（30）。
- 集群级清理：`./setup.sh down`（01）或 `kind delete cluster --name k8s-learn`，删掉重建零残留。
