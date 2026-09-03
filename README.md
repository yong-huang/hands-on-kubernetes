# hands-on-kubernetes

Kubernetes 动手学习系列：通过 **31 个可真实跑通的小项目**，从环境搭建一路学到多集群与 Operator 开发。每个实验都自带原理讲解（README）、K8s 清单（manifests/）、一键演示脚本（xxx.sh）和架构图（images/）。

> 🖼️ **交互式架构图**：每个实验（00 除外）都配有由 [Archify](https://github.com/tt-a1i/archify) 生成、通过 showcase 级校验的架构图，共 38 张三件套：图源 JSON（Typed JSON IR）+ 可交互 HTML（缩放 / 节点聚焦 / 连线追踪 / 深浅主题）+ 双主题矢量 SVG（README 内嵌）。开启 GitHub Pages 后可[在线查看](https://yong-huang.github.io/hands-on-kubernetes/)；克隆到本地后用浏览器打开对应实验的 `images/*.html` 也可以。

## 环境要求

- Docker（kind 以容器模拟节点；未装 kind/kubectl 先跑 [labs/00_setup_kind](labs/00_setup_kind/README.md)）
- kind ≥ 0.20、kubectl ≥ 1.28（节点镜像不锁定版本，使用 kind 默认）
- 部分实验额外需要：helm（27）、istioctl（13）、velero CLI（18）、trivy/cosign（21）、karmadactl（30）等，见各实验 README

**海外网络**：实验镜像均可从 docker.io 直接拉取，无需预载，可跳过 `load_images.sh`。国内网络建议先配置镜像加速；批量预载镜像到 kind 节点用公共脚本：

```bash
scripts/load_images.sh [image1 image2 ...]   # 无参数时加载默认列表
```

## 目录结构

```
hands-on-kubernetes/
├── README.md             # 本文档：系列总目录
├── LICENSE               # MIT
├── PROJECT_TEMPLATE.md   # 复刻模版：把本系列泛化到其它领域（含 AI 提示词）
├── scripts/
│   └── load_images.sh    # 公共脚本：拉取镜像并导入所有 kind 节点（集群名 k8s-learn）
└── labs/
    └── NN_xxx/           # 每个实验统一结构：
        ├── README.md     #   教程文档（原理 + 实操步骤，内嵌双主题矢量架构图）
        ├── xxx.sh        #   主演示脚本：本实验的学习重点（./xxx.sh [step]）
        ├── manifests/    #   K8s YAML 清单
        └── images/       #   架构图三件套（Archify 生成）：
            ├── xxx.architecture.json  #   图源（Typed JSON IR）
            ├── xxx.html               #   交互版（浏览器打开，可缩放/聚焦/追踪）
            └── xxx.svg                #   双主题矢量版（README 内嵌）
```

## 实验列表

| # | 实验 | 主题 |
|---|------|------|
| 00 | [工具准备](labs/00_setup_kind/README.md) | 安装 kind + kubectl |
| 01 | [环境搭建](labs/01_setup_env/README.md) | kind 本地集群：拓扑、CNI、验证 |
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
| 13 | [Service Mesh](labs/13_service_mesh/README.md) | Istio sidecar 与金丝雀发布 |
| 14 | [DNS 服务发现](labs/14_dns_discovery/README.md) | ClusterIP、Headless 与 Pod 级域名 |
| 15 | [PV/PVC](labs/15_pv_pvc/README.md) | 静态供给、绑定机制与回收策略 |
| 16 | [StorageClass](labs/16_storageclass/README.md) | 动态供给、延迟绑定与 CSI |
| 17 | [CSI 快照](labs/17_csi_snapshot/README.md) | VolumeSnapshot、dataSource 还原 |
| 18 | [Velero 迁移](labs/18_velero_migration/README.md) | 有状态应用备份与跨集群迁移 |
| 19 | [RBAC](labs/19_rbac/README.md) | 角色、绑定与最小权限原则 |
| 20 | [Pod Security](labs/20_pod_security/README.md) | PSS 三等级与 PSA 准入控制 |
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

## 建议学习路线

1. **基础（01–09）**：环境 → 工作负载 → 网络 → 配置 → 弹性，理解"声明式 API + 控制循环"这条主线
2. **调度与网络进阶（10–14）**：调度约束、七层路由、网络隔离、服务网格、DNS 内幕
3. **存储（15–18）**：从静态 PV 到动态供给、快照、备份迁移
4. **安全（19–22）**：RBAC、Pod 准入、镜像供应链、密钥管理
5. **可观测性（23–26）**：监控、日志、追踪、排障
6. **平台工程（27–31）**：Helm、GitOps、CRD 扩展、多集群、Operator

## 如何跑一个实验

```bash
cd labs/03_deploy
./deploy.sh          # 依次执行全部步骤
./deploy.sh scale    # 只执行某一步（步骤列表见脚本头部注释）
```

所有实验都在 kind 集群（`k8s-learn`）上验证过；涉及外网镜像的实验，README 中均标注了用 `scripts/load_images.sh` 预载的方法。

## License

[MIT](LICENSE) — 实验代码与文档可自由使用、修改和分发。
