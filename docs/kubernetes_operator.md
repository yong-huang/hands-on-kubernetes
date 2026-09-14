# ☸️ Kubernetes Operator 10 项目实战清单

> 由 30 项目学习清单压缩而来：砍掉同质与重叠项目，保留 10 个**实用、有教学梯度、
> 有实战价值**的 Operator（每个仍是完整可运行的 kubebuilder 项目，300~600 行）。
> 预计周期：3~4 周（每天有效学习 2~3 小时）。
>
> 前置建议：先做本仓库 `labs/29_crd_controller`——用 Python 手写 Reconcile 循环
> 理解"水平触发 + 幂等"的原理，再用 kubebuilder 走工业化路线。

## ✂️ 压缩说明（30 → 10 砍了什么）

| 原项目 | 处置 | 理由 |
|:---|:---|:---|
| 1~6（Hello/ConfigMap/Deployment/Service/Finalizer/Status） | **合并 → 项目 1** | 同一个 Operator 的渐进版，核心模式一次学全 |
| 7+9（MySQL/PG 备份） | **合并 → 项目 2** | StatefulSet 供给 + 定时备份是一个产品的两步 |
| 10/11（Etcd/ZK 集群） | 砍 | 集群 membership 管理复杂度高，教学点与 Redis 主从重复 |
| 12+13（Cron 扩缩容/滚动重启） | **合并 → 项目 4** | 同属"运维自动化"且都基于 patch 触发 |
| 15/16（配额调整/健康巡检） | 砍 | 与 HPA、liveness 探针原生能力重叠 |
| 18/19/20（Kafka/ES/RabbitMQ） | **保留 18 → 项目 7** | 同为"外部系统 API 管理"模式，做一个即可举一反三 |
| 21（ServiceMonitor 生成） | 砍 | watch-and-derive 模式与毕业项目重复 |
| 23（PyTorch 分布式训练） | **保留 → 项目 9（新增名额）** | 与 GPU 单卡训练形成"单卡 → 分布式"进阶 |
| 24/25（模型服务/数据缓存） | 砍（作项目 9 延伸） | 依赖重（KFServing/Fluid 生态），核心编排已在 23 |
| 26+27（Webhook/高级特性） | **合并 → 项目 10** | 生产化必需，随毕业项目一起做 |
| 29（GitOps Application） | 砍 | `labs/28` ArgoCD 已完整覆盖 GitOps |
| 30（端到端微服务） | **保留 → 项目 10 载体** | 毕业综合 |

## 🤖 AI 辅助提示词速查

| 场景 | 提示词 |
|:---|:---|
| **开始一个新项目** | `我要开始 Kubernetes Operator 项目「[名称]」，目标是 [目标]。使用 kubebuilder 框架，包含 CRD 定义、Controller 逻辑、RBAC 和部署文件，macOS 可编译运行。只输出代码。` |
| **调试 Operator** | `我的 Operator [名称] 出现 [问题]。关键代码：[粘贴]。请诊断并修复。` |
| **理解某个模式** | `请解释 Operator 开发中的 [Reconcile 幂等/Finalizer/OwnerReference/Leader Election]，并给出代码示例。` |

## 📊 总进度

进度：█████░░░░░ 5/10 (50%)

| 阶段 | 项目 | 已完成 |
|:---|:---|:---:|
| 第一阶段：核心模式 | 1 | 1 |
| 第二阶段：有状态应用 | 2-3 | 2 |
| 第三阶段：运维自动化 | 4-5 | 1 |
| 第四阶段：外部系统与 AI | 6-9 | 2 |
| 第五阶段：毕业综合 | 10 | 0 |

---

## 🗂️ 第一阶段：核心模式（项目 1）

### [x] 项目 1：App 资源管家 ✅ 2026-09-04/05（原 30 清单的 1~6 全量合并）

| 项目信息 | 详情 |
|:---|:---|
| **代码目录** | `operators/01_app_operator`（核心模式一次学全：资源编排 + 状态上报 + Finalizer） |
| **行数** | ~600 行 |
| **核心学习点** | kubebuilder 骨架 · Reconcile 幂等 · OwnerReference 级联 · spec/status 分权 · Finalizer 两阶段删除 · Owns 漂移自愈 |
| **功能** | `App` CR（image/replicas/env/configData）自动编排 ConfigMap + Deployment + Service；status 上报 Available；CR 删除时先清理模拟的外部资源（Finalizer 两阶段） |
| **验收标准** | ① 创建 CR 后三件套自动出现且带 OwnerReference；② 改 replicas 自动伸缩、手改子资源自动拉回；③ 删 CR 时 Terminating 停留（外部清理）后消失 |

**✅ 实测记录**：
- 2026-09-04：三条验收通过；踩坑——kubebuilder 目录带数字前缀时默认项目名不合法（init 加 `--project-name`）；新版 CreateOrPatch 返回 (op, err)；nginx:alpine 未预载 ErrImagePull（load_images.sh 自愈）。
- 2026-09-05：Finalizer 增量——status.externalID + 两阶段删除；给外部清理加 5s 模拟延迟，Terminating 停留肉眼可见。

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「App 资源管家」，声明式管理一组应用资源。kubebuilder 完整项目：App CRD（image、replicas、env、configData），Reconcile 编排 ConfigMap+Deployment+Service（OwnerReference + CreateOrPatch），status 上报 Available Conditions，Finalizer 两阶段删除（模拟清理外部资源）。只输出代码。`

---

## 🗂️ 第二阶段：有状态应用（项目 2-3）

### [x] 项目 2：MySQL Operator + 定时备份（原 7+9）✅ 2026-09-05

| 项目信息 | 详情 |
|:---|:---|
| **代码目录** | `operators/02_mysql_operator` |
| **行数** | ~500 行 |
| **核心学习点** | StatefulSet + volumeClaimTemplates · Headless Service · CronJob 生命周期 · Finalizer 清理 PVC · 密码引用 Secret 不进 CR |
| **功能** | `MySQL` CR（storageSize/rootPasswordSecret/backupSchedule）一键部署单实例（PVC 持久化），可选按 Cron 定时 mysqldump 到备份 PVC |
| **验收标准** | ① CR 创建后 MySQL 可写、Pod 重建数据不丢；② 备份 CronJob 按计划产出 dump；③ 删 CR 连同 PVC 一起清理（复用 Finalizer） |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「MySQL Operator」，目标是部署 MySQL 单实例并支持定时备份。请用 kubebuilder 给我完整项目：MySQL CRD（storageSize、rootPasswordSecret 引用 Secret、backupSchedule 字段），Reconcile 创建 Headless Service + Service + StatefulSet（volumeClaimTemplates 持久化，root 密码从 Secret 注入）与备份 CronJob（mysqldump 到独立 PVC），Finalizer 清理 PVC。只输出代码。`

**✅ 实测记录（2026-09-05，kind v1.36）**：四条验收全过——
① CR 创建后 STS/双 Service/数据 PVC(3Gi Bound)/备份 CronJob 全自动出现，
写库→删 Pod 重建→数据还在；② 备份 CronJob 手动触发的 Job 成功，日志
backup-ok，dump 落在独立备份 PVC；③ 删 CR 后 Finalizer 清理全部 PVC，
集群零残留。**踩坑（最有价值的一条）**：CronJob 引用的备份 PVC 忘了由
controller 创建——CronJob 的卷引用不会触发动态供给，Pod 永远
Pending（FailedScheduling: pvc not found）。静态检查查不出这种"少建一个
资源"的 bug，只有真机跑到才知道。另：load_images.sh 只识别到一个节点的
Hostname 地址，镜像要手动补进其余节点（或修脚本的 jsonpath）。

### [x] 项目 3：Redis 主从 Operator（原 8）✅ 2026-09-05

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~400 行 |
| **核心学习点** | 主从复制配置 · 按序扩缩容 · 读写分离 |
| **功能** | `RedisCluster` CR 部署 1 主 N 从，从库自动 replicaof 主库，支持扩容从库数量 |
| **验收标准** | ① 主写从读数据同步；② replicas 2→3 自动加入新从库；③ Pod DNS 稳定可解析 |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「Redis 主从 Operator」，目标是部署 1 主 N 从 Redis。请用 kubebuilder 给我完整项目：RedisCluster CRD（replicas 字段），Controller 创建 StatefulSet + Headless Service，从库启动时通过容器 DNS replicaof 主库，支持扩缩容（缩容保留主库）。只输出代码。`

**✅ 实测记录（2026-09-05，kind v1.36）**：主写从读 ✓（SET master → GET replica
同值）；INFO replication 确认 role:slave / master_link_status:up；CR replicas 1→2
新从库自动加入并同步同键；手改 STS 副本=3 被 Owns 拉回 2。**踩坑**：master
Service 忘挂 OwnerReference → 删 CR 后 svc 残留成孤儿（E2E 删除步骤抓出），
补 SetControllerReference 后级联正常。

---

## 🗂️ 第三阶段：运维自动化（项目 4-5）

### [x] 项目 4：定时扩缩容 + 滚动重启（原 12+13）✅ 2026-09-05

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~400 行 |
| **核心学习点** | 时间驱动的 Reconcile（Cron 判定）· annotation 触发模式 · patch 不覆盖用户字段 |
| **功能** | `Scaler` CR 按 Cron 表达式扩缩容目标 Deployment（早高峰扩、夜间缩）；`kubectl annotate` 触发目标逐 Pod 滚动重启 |
| **验收标准** | ① 到达 schedule 时间点副本数自动变化；② annotate 后 Pod 逐个重启、服务不中断；③ 手改副本数不会被误覆盖 |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「运维自动化 Operator」，包含两个能力：① Scaler CRD（schedule、targetReplicas、targetRef）按 Cron 调整 Deployment 副本数；② 给 Deployment 打 restart annotation 触发逐 Pod 滚动重启（等 Ready 再删下一个）。请用 kubebuilder 给我完整项目。只输出代码。`

### [~] 项目 5：金丝雀发布 Operator（原 14）· 代码完成，待修 stable 缩容

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~450 行 |
| **核心学习点** | 多 Deployment 流量切分 · 状态机驱动的发布流程 · 失败回滚 |
| **功能** | `Canary` CR 描述发布流程（steps: 5% → 50% → 100%），Controller 管理稳定/金丝雀两套 Deployment 与流量切换，任一步骤失败自动回滚 |
| **验收标准** | ① 创建 CR 后金丝雀版按第一步权重接入流量；② 推进 step 流量比例变化；③ 注入故障后自动回滚到稳定版 |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「金丝雀发布 Operator」，目标是管理渐进式发布。请用 kubebuilder 给我完整项目：Canary CRD（targetRef、stableImage、canaryImage、steps[].weight），Controller 创建稳定/金丝雀两套 Deployment，通过 Service selector 数量模拟流量权重，按 steps 推进，健康检查失败自动回滚。只输出代码。`

---

## 🗂️ 第四阶段：外部系统与 AI（项目 6-9）

### [x] 项目 6：Nginx 反向代理 Operator（原 17）✅ 2026-09-05

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~350 行 |
| **核心学习点** | 配置渲染（CR → nginx.conf）· ConfigMap 挂载 + 热加载 |
| **功能** | `NginxProxy` CR 声明 upstream/locations，Controller 渲染 nginx.conf 写入 ConfigMap，变更后触发 `nginx -s reload` |
| **验收标准** | ① CR 声明的路由生效；② 改 CR 后配置热更新、Nginx 不重启；③ 删 CR 级联清理（复用项目 1） |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「Nginx 反向代理 Operator」，目标是声明式管理 Nginx 配置。请用 kubebuilder 给我完整项目：NginxProxy CRD（upstreams、locations 字段），Controller 渲染 nginx.conf 到 ConfigMap 并挂载，配置变更后执行 nginx -s reload 热加载。只输出代码。`

### [ ] 项目 7：Kafka Topic Operator（原 18，外部 API 管理模式代表）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~400 行 |
| **核心学习点** | 管理"集群外资源"：调外部 AdminClient API · 创建/变更/删除三态 · Finalizer 防孤儿 |
| **功能** | `KafkaTopic` CR 管理 Topic 生命周期：分区数、副本因子、retention 配置，删除 CR 时同步删 Topic |
| **验收标准** | ① 创建 CR 后 Kafka 集群出现对应 Topic；② 改 partitions 生效；③ 删 CR 后 Topic 被清理 |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「Kafka Topic Operator」，目标是声明式管理 Kafka Topic。请用 kubebuilder 给我完整项目：KafkaTopic CRD（partitions、replicationFactor、retentionMs 字段），Reconcile 通过 Kafka AdminClient 对比并收敛 Topic 实际状态，结合 Finalizer 保证删除 CR 时清理 Topic。只输出代码。`

> 同模式举一反三：ES Index（原 19）、RabbitMQ Exchange/Queue（原 20）只是换了客户端 API。

### [x] 项目 8：GPU 训练任务 Operator（原 22，联动 labs/31）✅ 2026-09-05

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~400 行 |
| **核心学习点** | 扩展资源调度（nvidia.com/gpu）· 任务生命周期（Running→Succeeded→清理）· status 阶段上报 |
| **功能** | `TrainingJob` CR 提交训练任务（image/command/gpuCount），调度到有 GPU 的节点，完成后保留结果并按 TTL 清理 |
| **验收标准** | ① 在 labs/31 的 fake GPU 集群上：任务被调度"有卡"节点并 Running；② 完成后 status 显示 Succeeded；③ TTL 到期自动清理 |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「GPU 训练任务 Operator」，目标是管理 GPU 任务生命周期。请用 kubebuilder 给我完整项目：TrainingJob CRD（image、command、gpuCount、ttlSecondsAfterFinished），Reconcile 创建 Job（resources.requests 带 nvidia.com/gpu），status 上报阶段（Pending/Running/Succeeded），TTL 到期清理。只输出代码。`

### [x] 项目 9：PyTorch 分布式训练 Operator（原 23，新增名额）✅ 2026-09-05

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~450 行 |
| **核心学习点** | 多 Pod 编排（1 Master + N Worker）· 有状态环境变量注入（MASTER_ADDR/RANK/WORLD_SIZE）· Headless Service 成员发现 |
| **功能** | `PyTorchJob` CR 管理分布式训练：Master Pod + Worker StatefulSet，注入 torchrun 所需环境变量，训练完成回收 |
| **验收标准** | ① 创建 CR 后 Master 先起、Worker 陆续加入；② Worker 环境变量正确指向 Master；③ 训练完成全部 Pod Succeeded |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 项目「PyTorch 分布式训练 Operator」，目标是编排多 Pod 分布式训练。请用 kubebuilder 给我完整项目：PyTorchJob CRD（master/worker 镜像与命令、workers 数量），Controller 创建 Master Pod + Worker StatefulSet，注入 MASTER_ADDR/MASTER_PORT/RANK/WORLD_SIZE，训练完成后回收。只输出代码。`

> 进阶联动：项目 8 是"单卡"，本项目是"多卡协同"；模型服务（原 24）、数据缓存 Fluid（原 25）在此基础延伸。

---

## 🗂️ 第五阶段：毕业综合（项目 10）

### [ ] 项目 10：端到端微服务 Operator（原 26+27+30）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~600 行 |
| **核心学习点** | Validating Webhook 准入校验 · Leader Election 多副本高可用 · Prometheus Metrics · 全栈资源编排 |
| **功能** | `MicroService` CR 一键创建完整微服务栈（Deployment+Service+ConfigMap+Ingress+HPA+PDB），Webhook 拒绝不合规镜像，Operator 双副本高可用并暴露 Reconcile 指标 |
| **验收标准** | ① 一个 CR 拉起全套资源且 HPA 生效；② 不合规镜像（latest/root）被 Webhook 拒绝；③ 杀掉一个 Operator 副本服务不中断；④ /metrics 可见 reconcile 计数 |

**🤖 提示词**：
> `我要开始 Kubernetes Operator 毕业项目「端到端微服务 Operator」。请用 kubebuilder 给我完整项目：MicroService CRD（image、replicas、env、ingress、hpa 字段），Reconcile 编排 Deployment+Service+ConfigMap+Ingress+HPA+PDB 全栈；附带 Validating Webhook（拒绝 latest 镜像与 root 容器）、Leader Election 双副本、Prometheus Metrics 统计 reconcile 次数。只输出代码。`

---

## 📅 周计划（3~4 周）

| 周次 | 内容 | 要点 |
|:---|:---|:---|
| **第 1 周** | 项目 1-2（核心 + 首个有状态） | 全部基础模式 + StatefulSet/PVC |
| **第 2 周** | 项目 3-5（有状态 + 自动化） | 主从复制 / 时间驱动 / 渐进发布 |
| **第 3 周** | 项目 6-8（外部系统 + AI） | 配置渲染 / 外部 API / 扩展资源调度 |
| **第 4 周** | 项目 9-10（分布式 + 毕业） | 多 Pod 编排 / Webhook / HA / Metrics |

## 🏆 里程碑

- [ ] 项目 1 → 核心模式一次学全（编排/状态/Finalizer/漂移自愈）
- [ ] 项目 2-3 → 能用 Operator 管理真实有状态数据
- [ ] 项目 4-5 → 运维动作 Operator 化
- [ ] 项目 6-9 → 外部资源管理 + AI 工作负载两大生产场景
- [ ] 项目 10 → 毕业项目合入个人作品集

## 📝 每日日志

| 日期 | 项目 | 耗时 | 收获 | 踩坑 |
|:---|:---|:---:|:---|:---|
| 2026-09-04 | 1（资源编排部分） | 2h | OwnerReference/CreateOrPatch/Owns 自愈 | 目录数字前缀；CreateOrPatch 新签名 |
| 2026-09-05 | 1（status/finalizer）+ 2 开工 | 2h | 两阶段删除肉眼可见；镜像预载 playbook | 镜像未预载 ErrImagePull |

## 📦 工程目录

完成的 Operator 放在 `operators/NN_name/`：
- `01_app_operator` = 项目 1（核心模式全量）
- `02_mysql_operator` = 项目 2（进行中）

均为标准 kubebuilder 工程：`make install` 装 CRD、`make run` 本地跑、
`make deploy` 集群模式。

## 🔧 环境配置

```bash
brew install go kubebuilder kind          # 工具链
kind create cluster --name operator-dev   # 复用 labs/01 的集群亦可
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml  # Webhook 依赖（项目 10）

mkdir my-operator && cd my-operator
kubebuilder init --domain example.com --project-name my-operator   # 目录带数字前缀时必须显式指定项目名
kubebuilder create api --group app --version v1 --kind App
make install && make run      # 本地模式跑 Controller
make docker-build docker-push && make deploy   # 集群模式
```
