# 10 · 端到端微服务 Operator（毕业项目）

> 一个 `MicroService` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 编排完整微服务栈：ConfigMap + Deployment + Service + Ingress，全部子资源挂 OwnerReference 实现级联清理——融合 Reconcile 幂等 / 级联删除 / status 上报 / 声明式 API 等全部已学核心模式。读完本篇，你将看到前 9 个实验的模式如何合体成"平台 API"的雏形，以及从"能跑"到"生产可用"还差什么。

## Background

业务团队要的从来不是"四份 YAML"，而是"把我的服务跑起来并可以从外部访问"。

在没有平台封装的团队里，每个服务上线都要重走一遍：写 ConfigMap、Deployment、Service、Ingress 四份清单，检查选择器、端口、域名是否对齐——同样的错误（selector 拼错、端口不匹配）每个新服务都会再犯一次。

毕业项目的任务是把前 9 个实验练的模式合体：Reconcile 幂等（operators/01）、有状态编排（02/03）、运维自动化（04）、发布状态机（05）、配置渲染（06）、外部资源（07）、领域翻译（08/09）。

最终交付一个 `MicroService` CR：镜像、副本、端口、域名四个字段说清意图，编排细节全部由 Operator 承担。

这正是内部开发者平台（IDP）的最小雏形。

## What

一个 `MicroService` CR 长这样：

```yaml
apiVersion: platform.example.com/v1
kind: MicroService
metadata: { name: user-service }
spec:
  image: "nginx:alpine"
  replicas: 2
  env: { TZ: Asia/Shanghai }
  port: 8080
  ingressHost: user.example.com
```

apply 后：ConfigMap（env/configData）→ Deployment → Service → Ingress 四件套自动出现；status 上报 `Available` Condition；删 CR 四件套级联消失。

一句话心智模型：**CR 是平台的 API，Controller 是平台的引擎**——但和"模板渲染"不同的是，引擎是常驻的：子资源漂移会被拉回，就绪状态实时上报。

| 编排产物 | 来源字段 |
|---|---|
| ConfigMap | env / configData |
| Deployment | image / replicas / port / env |
| Service | port |
| Ingress | ingressHost |

## When to Use

典型场景：平台团队给业务方提供"四字段上线一个服务"的门户；统一治理路由与配置的挂载规范；作为 IDP 的最小原型逐步长出配额、发布、观测能力。

何时不用：服务需要独立演化部署细节（四件套绑死会限制）；已有成熟 PaaS 平台承载（不必再造一层）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 业务团队自管四件套 YAML | 灵活但重复出错 | 平台缺位时的现状 |
| MicroService Operator（本实验） | 四字段 + 全托管编排 | IDP 雏形 |
| 成熟 IDP（Backstage + 交付平台） | 全流程门户 | 组织规模更大时 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用。

```bash
cd operators/10_microservice_operator
make install && make run
kubectl apply -f config/samples/platform_v1_microservice.yaml
kubectl get microservice,deploy,svc,ingress,cm -l app.kubernetes.io/managed-by=microservice-operator
kubectl delete microservice user-service    # 验证级联清理
```

诚实预期（实现范围）：

| 能力 | 状态 |
|:---|:---|
| ConfigMap + Deployment + Service + Ingress 四件套编排 | ✅ |
| OwnerReference 级联清理 | ✅ |
| status Available Condition | ✅ |
| HPA（hpaEnabled/minReplicas 字段） | 🚧 字段已预留，Reconcile 未实现 |
| Validating Webhook / LeaderElection / Metrics（清单规划项） | ⬜ 未实现 |

本实验在 kubernetes_operator.md 清单中未勾选——Webhook、LeaderElection、Metrics 是毕业部分的剩余内容。

## How It Works

Reconcile 串行编排四种子资源，同一模式复制四遍：env/configData 进 ConfigMap，port/ingressHost 决定 Service 与 Ingress 形态，Condition 随子资源就绪情况翻转。

```go
// 四种子资源同一模式：构造期望 → SetControllerReference → CreateOrPatch
cm := &corev1.ConfigMap{ Data: envFromSpec(ms.Spec.Env) + configData ... }
dep := &appsv1.Deployment{ Spec: ...(port、replicas、env 注入)... }
svc := &corev1.Service{ ... }
ing := &networkingv1.Ingress{ Spec: ...(ingressHost 路由)... }
// 逐个 CreateOrPatch 后汇总就绪情况，status 上报 Available Condition
cond := metav1.Condition{ Type: "Available", ... }
```

每种资源都是 operators/01 练过的 `构造期望 → SetControllerReference → CreateOrPatch`——毕业项目的价值不在新知识，而在把模式组合成一个有真实用户视角（业务方只看四个字段）的 API。

## Pitfalls & Q&A

**Q1: 一个 CR 编排多少资源算合适？**
按"独立生命周期"划分：同生共死的放一个 CR（本实验四件套跟着服务走），可独立演化的拆开（数据库、缓存不该和微服务绑死，见 operators/02/03 的独立 CRD）。资源越多 Reconcile 越重、级联爆炸半径越大——"CR 数量"本身就是架构决策。

**Q2: OwnerReference 级联清理方便但有什么代价？**
它太隐式了：误删 CR = 全栈消失，没有二次确认。生产可给关键资源改用"无 ownerRef + Finalizer"的显式清理（operators/02 的做法）——删除前有机会执行备份、通知、审批，把"删"从副作用变成流程。

**Q3: 从"能跑"到"生产可用"还差什么？**

三件事：准入校验（Validating Webhook 拒掉 latest 镜像、root 容器，见 labs/21 的 Kyverno 思路）、多副本高可用（LeaderElection 让 Controller 本身不成为单点）、可观测（暴露 metrics 接进 Prometheus，见 labs/23）。

实验覆盖的是 Reconcile 正确性，这三项覆盖的是运营正确性。
