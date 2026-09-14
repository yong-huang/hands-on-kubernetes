# ☸️ Kubernetes 开发运维 31 小项目学习清单 · Todo List

> 通过 31 个小项目（每项目 50-300 行代码/配置）系统掌握 Kubernetes 开发、运维和架构设计
> 预计周期：5-6 周（每天有效学习 3-4 小时）
> 每个项目都配有 🤖 AI 提示词，复制发给 AI 即可获得完整代码

---

## 🤖 AI 辅助提示词速查

| 场景 | 提示词 |
|:---|:---|
| **开始一个新项目** | `我要开始 Kubernetes 项目 [项目名称]，目标是 [项目目标]。请给我一个完整的 YAML 清单文件和必要的脚本，约 [行数] 行，包含清晰的注释和部署说明。只输出代码，不要解释。` |
| **排查 Pod 问题** | `我的 Kubernetes Pod [名称] 状态为 [状态]，describe 输出是：[粘贴输出]。请帮我诊断问题原因并给出修复方案。` |
| **配置优化** | `我的 Kubernetes 配置如下：[粘贴 YAML]。请帮我优化资源配置、健康检查和安全设置。` |
| **编写 Operator** | `我要为 [CRD 名称] 编写一个 Kubernetes Operator，实现 [功能描述]。请给我完整的 Controller 代码和 CRD 定义。` |
| **网络问题排查** | `我的 Kubernetes 集群出现 [网络问题描述]，Service 无法访问 Pod。请帮我诊断并给出解决方案。` |

---

## 📊 总进度

进度：████████████████████ 31/31 (100%)

| 阶段 | 项目数 | 已完成 |
|:---|:---:|:---:|
| 第一阶段：基础入门 | 5 | 5 |
| 第二阶段：工作负载与调度 | 5 | 5 |
| 第三阶段：网络与服务发现 | 4 | 4 |
| 第四阶段：存储与状态管理 | 4 | 4 |
| 第五阶段：安全与配置管理 | 4 | 4 |
| 第六阶段：可观测性与排障 | 4 | 4 |
| 第七阶段：CI/CD 与 GitOps | 4 | 4（另含项目31） |
| **合计** | **31** | **31** |

---

## 🗂️ 第一阶段：基础入门（项目 1-5）

> **目标**：理解 K8s 核心概念，能够部署和管理基本工作负载

---

### [x] 项目 1：本地 Kubernetes 环境搭建

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~20 条命令 |
| **核心知识点** | `kind`/`minikube`/`k3s`、集群初始化、`kubectl` 配置 |
| **验收标准** | `kubectl get nodes` 显示 Ready 状态 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「本地 K8s 环境搭建」，目标是在本地 Mac/Ubuntu 上使用 kind 创建一个 3 节点的 Kubernetes 集群。请给我完整的命令行步骤、kind-config.yaml 配置、验证集群健康的方法。只输出代码和命令。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 2：第一个 Pod 和 Namespace

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行 YAML |
| **核心知识点** | Namespace、Pod 定义、`kubectl run`、`kubectl apply` |
| **验收标准** | 成功创建 Nginx Pod 并能 `kubectl exec` 进入容器 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「第一个 Pod 和 Namespace」，目标是创建独立的 Namespace 并在其中部署 Nginx Pod。请给我完整的 YAML 清单，包含 Namespace 定义、Pod 定义、部署和验证命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 3：Deployment 与滚动更新

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | Deployment、ReplicaSet、滚动更新、回滚 |
| **验收标准** | 更新镜像版本后，无中断切换并支持 `kubectl rollout undo` |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Deployment 与滚动更新」，目标是部署一个带滚动更新策略的 Deployment。请给我完整的 YAML 清单，包含 Deployment 定义（replicas=3）、滚动更新策略（maxSurge/maxUnavailable）、更新和回滚验证命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 4：Service 暴露应用

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML |
| **核心知识点** | ClusterIP、NodePort、LoadBalancer、Service 选择器 |
| **验收标准** | 通过 NodePort 从集群外访问 Nginx |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Service 暴露应用」，目标是创建 3 种类型的 Service 并验证访问。请给我完整的 YAML 清单，包含 ClusterIP、NodePort、LoadBalancer 三种 Service 定义，以及端口转发和访问验证命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 5：应用配置管理（ConfigMap & Secret）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | ConfigMap、Secret、环境变量注入、Volume 挂载 |
| **验收标准** | 应用能从 ConfigMap 读取配置，从 Secret 读取敏感信息 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「应用配置管理」，目标是使用 ConfigMap 和 Secret 管理配置。请给我完整的 YAML 清单，包含 ConfigMap 定义、Secret 定义（Base64 编码）、Pod 通过环境变量和 Volume 挂载两种方式注入配置。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第二阶段：工作负载与调度（项目 6-10）

> **目标**：掌握各种工作负载类型和高级调度策略

---

### [x] 项目 6：Job 与 CronJob

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML |
| **核心知识点** | Job、CronJob、并行执行、失败重试策略 |
| **验收标准** | 定时执行数据库备份 Job |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Job 与 CronJob」，目标是实现定时数据库备份任务。请给我完整的 YAML 清单，包含 Job 定义（一次性任务）和 CronJob 定义（每小时执行），包含重试策略和并行度设置。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 7：DaemonSet 与节点守护

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML |
| **核心知识点** | DaemonSet、节点选择器、日志收集/监控 Agent |
| **验收标准** | 在每个节点上运行日志采集器 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「DaemonSet 与节点守护」，目标是部署一个节点级的日志采集 Agent（如 Fluentd）。请给我完整的 YAML 清单，包含 DaemonSet 定义、节点选择器、容忍度设置，验证每个节点都有一个 Pod 运行。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 8：StatefulSet 与稳定的存储

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行 YAML |
| **核心知识点** | StatefulSet、PV/PVC、有序部署/删除、稳定网络标识 |
| **验收标准** | 部署 3 个 MySQL 主从副本，每个绑定独立存储 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「StatefulSet 与稳定的存储」，目标是部署一个有状态应用（如 MySQL）。请给我完整的 YAML 清单，包含 StatefulSet 定义、Headless Service、PV/PVC 模板，验证 Pod 有稳定的网络标识和独立的存储。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 9：HPA 自动水平伸缩

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | Metrics Server、HPA、CPU/Memory 阈值、自定义指标 |
| **验收标准** | 应用负载增加时自动扩容 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「HPA 自动水平伸缩」，目标是部署一个支持自动伸缩的应用。请给我完整的 YAML 清单，包含 Deployment、HPA 定义（CPU 阈值 50%）、安装 Metrics Server 的命令，以及压测验证自动扩容的步骤。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 10：亲和性与反亲和性调度

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | nodeSelector、nodeAffinity、podAffinity、podAntiAffinity、拓扑分布约束 |
| **验收标准** | 确保多副本 Pod 分布在不同节点上 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「亲和性与反亲和性调度」，目标是实现高可用 Pod 分布。请给我完整的 YAML 清单，包含 PodAntiAffinity 配置（同一 Deployment 的副本不部署在同一节点）、topologySpreadConstraints 配置，验证 Pod 跨节点分布。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第三阶段：网络与服务发现（项目 11-14）

> **目标**：理解 K8s 网络模型、Service、Ingress 和服务网格

---

### [x] 项目 11：Ingress 与域名路由

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | Ingress Controller（nginx-ingress）、域名路由、TLS 证书 |
| **验收标准** | 通过域名访问后端服务 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Ingress 与域名路由」，目标是配置域名访问服务。请给我完整的 YAML 清单，包含 Ingress 资源定义（域名路由）、安装 nginx-ingress-controller 的命令、以及测试访问的 curl 命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 12：NetworkPolicy 网络策略

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | NetworkPolicy、Ingress/Egress 规则、命名空间隔离 |
| **验收标准** | 只允许前端访问后端，禁止其他 Pod 访问 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「NetworkPolicy 网络策略」，目标是实现微服务间的网络隔离。请给我完整的 YAML 清单，包含 NetworkPolicy 定义（只允许带有 app=frontend 标签的 Pod 访问 app=backend 的 Pod），验证网络策略生效的命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 13：Service Mesh 入门（Istio）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~80 行 YAML |
| **核心知识点** | Istio 安装、VirtualService、DestinationRule、Sidecar 注入、灰度发布 |
| **验收标准** | 配置流量镜像/灰度路由（v1 90%，v2 10%）|

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Service Mesh 入门」，目标是使用 Istio 实现灰度发布。请给我完整的 YAML 清单，包含 Istio 安装命令、VirtualService 定义（v1 权重 90%，v2 权重 10%）、DestinationRule 定义，验证流量分配。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 14：自定义 DNS 与服务发现

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行 YAML |
| **核心知识点** | CoreDNS 配置、服务域名、Headless Service |
| **验收标准** | 通过 DNS 名称 `my-svc.namespace.svc.cluster.local` 访问服务 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「自定义 DNS 与服务发现」，目标是理解 K8s DNS 解析机制。请给我完整的 YAML 清单，包含 Headless Service 定义，演示通过 Pod DNS 名称（如 pod-0.headless-svc.namespace.svc.cluster.local）访问特定 Pod。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第四阶段：存储与状态管理（项目 15-18）

> **目标**：掌握 PV/PVC、StorageClass、CSI 存储机制

---

### [x] 项目 15：PV/PVC 静态存储

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | PersistentVolume、PersistentVolumeClaim、静态绑定、回收策略 |
| **验收标准** | Pod 成功挂载 PV 并写入数据 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「PV/PVC 静态存储」，目标是创建静态 PV 并通过 PVC 挂载。请给我完整的 YAML 清单，包含 PV 定义（hostPath）、PVC 定义、Pod 挂载 PVC，验证 Pod 写入的文件持久保存。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 16：StorageClass 动态存储

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML |
| **核心知识点** | StorageClass、CSI 驱动、动态 PVC 创建、默认 StorageClass |
| **验收标准** | PVC 自动触发存储卷创建（AWS EBS/GCE PD） |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「StorageClass 动态存储」，目标是配置动态存储供给。请给我完整的 YAML 清单，包含 StorageClass 定义、PVC 声明（storageClassName 指定）、以及云平台 CSI 驱动安装命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 17：CSI 快照与备份

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | VolumeSnapshot、VolumeSnapshotClass、数据恢复 |
| **验收标准** | 创建 PVC 快照并从中恢复数据 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「CSI 快照与备份」，目标是实现存储卷快照和恢复。请给我完整的 YAML 清单，包含 VolumeSnapshotClass 定义、VolumeSnapshot 定义、从快照恢复为新 PVC 的流程。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 18：有状态应用迁移与数据迁移

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~80 行 YAML |
| **核心知识点** | Velero、数据迁移、跨集群恢复 |
| **验收标准** | 使用 Velero 备份/恢复 StatefulSet 数据 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「有状态应用迁移」，目标是使用 Velero 备份和迁移 StatefulSet。请给我完整的命令行步骤和 YAML 清单，包含 Velero 安装、备份创建、跨集群恢复的完整流程。只输出代码和命令。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第五阶段：安全与配置管理（项目 19-22）

> **目标**：掌握 RBAC、Pod 安全、镜像安全和配置最佳实践

---

### [x] 项目 19：RBAC 权限控制

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行 YAML |
| **核心知识点** | ServiceAccount、Role/ClusterRole、RoleBinding/ClusterRoleBinding |
| **验收标准** | 给开发人员只读权限 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「RBAC 权限控制」，目标是给不同角色分配最小权限。请给我完整的 YAML 清单，包含 ServiceAccount 定义、Role（只读 Pod/Service）、RoleBinding 绑定，验证 ServiceAccount 只能执行 get/list 操作。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 20：Pod Security Standards

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | Pod Security Standards（Privileged/Baseline/Restricted）、PSA 配置 |
| **验收标准** | 不符合安全标准的 Pod 被拒绝创建 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Pod Security Standards」，目标是配置 Pod 安全准入策略。请给我完整的 YAML 清单，包含 Namespace 标签配置（pod-security.kubernetes.io/enforce=restricted）、尝试创建特权 Pod 被拒绝的验证命令。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 21：镜像安全与漏洞扫描

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML |
| **核心知识点** | 镜像签名（Cosign）、漏洞扫描（Trivy）、镜像准入策略 |
| **验收标准** | 含有高危漏洞的镜像无法部署 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「镜像安全与漏洞扫描」，目标是配置镜像安全准入。请给我完整的 YAML 清单，包含安装 Trivy Operator 的命令、漏洞报告 CRD、配置准入策略阻止高危镜像部署。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 22：Secrets 管理（Vault 集成）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~80 行 YAML |
| **核心知识点** | HashiCorp Vault、Secrets CSI Driver、动态凭证注入 |
| **验收标准** | Pod 从 Vault 动态获取数据库凭证 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Secrets 管理」，目标是使用 Vault 管理应用密钥。请给我完整的 YAML 清单，包含 Vault 安装配置、Secrets CSI Driver 部署、Pod 通过 CSI 挂载 Vault 动态凭证。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

## 🗂️ 第六阶段：可观测性与排障（项目 23-26）

> **目标**：构建日志、监控、追踪体系，掌握高级排障技巧

---

### [x] 项目 23：Prometheus + Grafana 监控

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~80 行 YAML |
| **核心知识点** | Prometheus Operator、ServiceMonitor、Grafana Dashboard |
| **验收标准** | 集群和应用指标可视化展示 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Prometheus + Grafana 监控」，目标是部署完整的监控栈。请给我完整的 YAML 清单，包含 Prometheus Operator 安装、ServiceMonitor 定义（监控 Nginx 应用）、Grafana 部署和预置 Dashboard。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 24：日志收集（EFK/ELK Stack）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~70 行 YAML |
| **核心知识点** | Fluentd/Filebeat、Elasticsearch、Kibana 日志聚合 |
| **验收标准** | 所有 Pod 日志集中检索 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「日志收集」，目标是使用 EFK Stack 集中采集日志。请给我完整的 YAML 清单，包含 Fluentd DaemonSet 配置（采集所有 Pod 日志）、Elasticsearch 部署、Kibana 部署和日志查询示例。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 25：分布式追踪（Jaeger）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行 YAML |
| **核心知识点** | Jaeger Operator、分布式追踪、Trace 查看 |
| **验收标准** | 微服务调用链可在 Jaeger UI 查看 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「分布式追踪」，目标是部署 Jaeger 并采集追踪数据。请给我完整的 YAML 清单，包含 Jaeger Operator 安装、Jaeger 实例部署、应用注入 Tracing 配置（如 Istio + Jaeger）。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 26：高级排障（Ephemeral Container 调试）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行命令 |
| **核心知识点** | Ephemeral Container、`kubectl debug`、容器网络调试 |
| **验收标准** | 使用临时容器调试问题 Pod |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「高级排障」，目标是掌握使用 Ephemeral Container 调试 Pod。请给我完整的命令清单，包含 kubectl debug 创建调试容器、安装网络工具、排查网络/文件问题的完整流程。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

## 🗂️ 第七阶段：CI/CD 与 GitOps（项目 27-30）

> **目标**：掌握 GitOps、Helm、ArgoCD 等现代化交付方式

---

### [x] 项目 27：Helm Chart 开发

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~100 行 YAML |
| **核心知识点** | Helm 模板、values.yaml、依赖管理、Chart 打包 |
| **验收标准** | 用 1 个 Helm Chart 部署完整的微服务应用 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Helm Chart 开发」，目标是创建一个完整的 Helm Chart 部署应用。请给我完整的 Chart 结构、templates 目录下的核心模板文件（Deployment、Service、ConfigMap、Ingress）、values.yaml 示例和安装命令。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 28：GitOps（ArgoCD）持续交付

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | ArgoCD、Application CRD、Sync 策略、自动部署 |
| **验收标准** | Git 仓库变更自动同步到集群 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「GitOps 持续交付」，目标是使用 ArgoCD 实现 GitOps 自动化部署。请给我完整的 YAML 清单，包含 ArgoCD 安装命令、Application 定义（Git 仓库路径、目标集群）、自动同步策略配置。只输出代码。`

**完成日期**：________
**踩坑记录**：________

---

### [x] 项目 29：自定义资源（CRD）与 Controller

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~200 行（Go/Python）|
| **核心知识点** | CRD 定义、自定义 Controller、控制循环、Operator Pattern |
| **验收标准** | 自定义 `Database` 资源，Controller 自动创建 StatefulSet |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「自定义资源与 Controller」，目标是创建 Database CRD 并编写 Controller。请给我完整的 CRD YAML 定义（Database 资源）、Controller 代码（Go 或 Python，使用 client-go/kubernetes-client）、以及部署运行步骤。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 30：多集群联邦管理

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~80 行 YAML |
| **核心知识点** | KubeFed 或 Karmada、多集群联邦、跨集群资源编排 |
| **验收标准** | 一个 Deployment 自动部署到多个集群 |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「多集群联邦管理」，目标是使用 Karmada 实现跨集群部署。请给我完整的 YAML 清单，包含 Karmada 安装、集群注册、联邦 Deployment 定义（propagationPolicy），验证应用部署到多个成员集群。只输出代码。`

**完成日期**：2026-08-23
**踩坑记录**：________

---

### [x] 项目 31：Fake GPU Operator 与 AI Ops 体验

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~100 行 YAML |
| **核心知识点** | GPU Operator 架构、Device Plugin、模拟 GPU 资源、AI 工作负载调度 |
| **验收标准** | 安装 fake GPU operator，节点出现模拟 GPU 资源，AI 任务按 GPU 资源调度 |
| **前置知识** | 项目 7 (DaemonSet)、项目 10 (亲和性调度) |

**🤖 开始提示词**：
> `我要开始 Kubernetes 项目「Fake GPU Operator 与 AI Ops」，目标是在无真实 GPU 的集群上模拟 GPU 资源并体验 AI Ops 流程。请给我完整的 YAML 清单，包含：模拟 GPU Device Plugin (DaemonSet 上报 nvidia.com/gpu 资源)、AI 训练任务 (Job 申请 GPU 资源)、GPU 资源配额 (ResourceQuota)、监控查询命令。只输出代码。`

**体验流程**：
1. 部署 fake GPU device plugin → 节点 Status.Capabilities 出现 `nvidia.com/gpu: N`
2. 提交申请 GPU 的训练 Job → 观察按 GPU 资源调度
3. 配置 ResourceQuota 限制团队 GPU 配额 → 观察超配额任务 Pending
4. `kubectl describe nodes` 查看 GPU 分配情况，体验 GPU Ops 的日常巡检

**完成日期**：2026-08-23
**踩坑记录**：________

---

## 📅 周计划

| 周次 | 内容 | 项目数 |
|:---|:---|:---:|
| **第 1 周** | 项目 1-5（基础入门） | 5 |
| **第 2 周** | 项目 6-10（工作负载与调度） | 5 |
| **第 3 周** | 项目 11-14（网络与服务发现） | 4 |
| **第 4 周** | 项目 15-18（存储与状态管理） | 4 |
| **第 5 周** | 项目 19-22（安全与配置管理） | 4 |
| **第 6 周** | 项目 23-26（可观测性与排障） | 4 |
| **第 7 周** | 项目 27-30（CI/CD 与 GitOps） | 4 |

---

## 🏆 里程碑

- [x] **完成项目 1-5** → K8s 基础操作能力
- [x] **完成项目 6-10** → 工作负载编排能力
- [x] **完成项目 11-14** → 网络与服务治理能力
- [x] **完成项目 15-18** → 存储与状态管理能力
- [x] **完成项目 19-22** → 安全与配置管理能力
- [x] **完成项目 23-26** → 可观测性与排障能力
- [x] **完成项目 27-30** → 自动化交付与 GitOps 能力

---

## 📝 每日日志

| 日期 | 项目 | 耗时 | 收获 | 踩坑 |
|:---|:---|:---:|:---|:---|
| | | | | |
| | | | | |
| | | | | |

---

## 🔧 环境配置

```bash
# 安装 kind
brew install kind
# 或下载二进制
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/

# 安装 kubectl
brew install kubectl
# 验证
kubectl version --client

# 安装 Helm
brew install helm

# 安装 Istio（项目 13）
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=demo -y

# 安装 Prometheus Operator（项目 23）
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/blob/main/bundle.yaml

# 安装 ArgoCD（项目 28）
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml