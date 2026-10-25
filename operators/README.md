# 🤖 operators：Kubernetes Operator 开发（Go / kubebuilder，10 项目）

> 来源：`docs/kubernetes_operator.md` 清单的落地项目，从最小可用 Operator 写到端到端微服务平台（毕业项目），全部在本机 kind 集群真机验收。与兄弟系列的关系：labs 是前置——CRD 与调谐概念见 [labs/29](../labs/29_crd_controller/README.md)，项目 08 依赖 [labs/31](../labs/31_fake_gpu_operator/README.md) 的 fake GPU；与 mart 互补——mart 手写清单组装微服务，本线把同类编排写成常驻程序。每项目统一结构：kubebuilder（K8s 官方 Operator 脚手架）骨架 + 六段式教程 README + `config/samples/` 样例 CR + `make install` / `make run` 本地运行。

进度：**7/10**　███████░░░（01–04、06、08、09 已验收；05 待修、07 教学模式、10 毕业项未勾选）

## 🚀 快速开始

前置：kind 集群已就绪（见 [labs/01](../labs/01_setup_env/README.md)）；Go 环境可用（Controller 本地编译运行）。以下命令在仓库根执行。

```bash
cd operators/01_app_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller（前台阻塞属正常，另开终端）
kubectl apply -f config/samples/app_v1_app.yaml
kubectl get app,deploy,svc,cm -l app.kubernetes.io/name=app-sample
kubectl delete app app-sample   # 验证级联清理
```

诚实预期：`make run` 阻塞前台是 controller-runtime 的正常形态；各项目入口命令一致，样例 CR 以各自 `config/samples/` 为准。

## 📚 项目总表

| # | 项目 | 一句话产出 | 状态 |
|:--|:--|:--|:--|
| 01 | [App 资源管家](01_app_operator/README.md) | App CR 自动编排 ConfigMap + Deployment + Service 三件套，覆盖幂等 / 级联 / 漂移自愈 / status / Finalizer 全部核心模式 | ✅ |
| 02 | [MySQL Operator](02_mysql_operator/README.md) | CR 编排 StatefulSet + 双 Service + 备份 CronJob：删 Pod 数据还在、删 CR 连 PVC 清理干净 | ✅ |
| 03 | [Redis 主从](03_redis_operator/README.md) | CR 声明从库数量，1 主 N 从拓扑由 Controller 注入启动命令，扩缩从库 = 改一个字段 | ✅ |
| 04 | [运维自动化](04_ops_automation/README.md) | Cron 定时扩缩容 + 注解触发逐 Pod 滚动重启，两个协作 Controller | ✅ |
| 05 | [金丝雀发布](05_canary_operator/README.md) | steps 权重序列（25% → 50% → 100%）驱动的发布状态机 | 🚧 stable 缩容待修 |
| 06 | [Nginx 反向代理](06_nginx_operator/README.md) | CR 渲染 nginx.conf，SHA256 指纹写进 Pod 模板注解驱动滚动生效 | ✅ |
| 07 | [Kafka Topic](07_kafka_topic_operator/README.md) | 集群外资源管理模式：CR 声明分区数与副本因子，Controller 收敛外部系统 | 🚧 教学模式（外部 API 模拟） |
| 08 | [GPU 训练任务](08_gpu_job_operator/README.md) | 联动 labs/31 假卡：gpuCount 翻译成扩展资源调度，TTL 到期自动清理 | ✅ |
| 09 | [PyTorch 分布式](09_pytorch_operator/README.md) | 1 Master + N Worker 组网：Headless DNS 成员发现 + 环境变量身份分配 | ✅ |
| 10 | [端到端微服务（毕业）](10_microservice_operator/README.md) | MicroService CR 四字段编排四件套，内部开发者平台最小雏形 | 🚧 Webhook / LeaderElection / Metrics 未实现 |

## 🧭 学习路线

按编号即顺序：01 打底（幂等 / 级联 / 自愈全部核心模式）→ 02 / 03 有状态与多副本拓扑 → 04 运维自动化 → 05 发布状态机 → 06 配置渲染 → 07 集群外资源 → 08 / 09 AI 工作负载（08 先跑 labs/31）→ 10 毕业合体。

## 🖼️ 架构图

每项目 `images/` 内有交互式 HTML 与双主题 SVG（如 `01_app_operator/images/app_reconcile.html`），本地浏览器打开即可。

## ⚠️ 预期失败诚实标注

- 05 的 stable 副本在 step 推进时未实际缩减（只改 status 报告），是已知待修项——观察流量比例以 status 为准。
- 07 是教学模式：Controller 用 condition/message 模拟外部 API 调用，不需要真实 Kafka 集群。
- 08 的 gpuCount 超过节点假卡数时任务 Pending（FailedScheduling）——与真卡集群行为一致，是刻意保留的教学点。
- 手改子资源会被 Owns 拉回（如 scale StatefulSet 3 → 自动回 2）——这是漂移自愈在工作，不是故障。

## 🔧 环境要求

- 基线：Docker + kind 集群（直接复用 labs/01 的 k8s-learn）；Go（`make run` 本地编译运行 Controller）。
- 清理：`kubectl delete <cr>` 触发级联清理；删整个集群见 labs/01 的 `./setup.sh down`。
