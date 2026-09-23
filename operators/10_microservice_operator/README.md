# 10 · 端到端微服务 Operator（毕业项目）

> 一个 `MicroService` CR 编排完整微服务栈：ConfigMap + Deployment + Service + Ingress，全部子资源挂 OwnerReference 实现级联清理——融合 Reconcile 幂等 / 级联删除 / status 上报 / 声明式 API 等全部已学核心模式。

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

apply 后：ConfigMap（env/configData）→ Deployment → Service → Ingress 四件套自动出现；status 上报 `Available` Condition；删 CR 四件套级联消失。一句话心智模型：**前 9 个实验的模式合体**——每种子资源都是 lab 01 练过的 CreateOrPatch + SetControllerReference，只是规模从三件套扩到四件套、从"资源管家"长成"平台 API"。

## Why

业务团队要的从来不是"四份 YAML"，而是"把我的服务跑起来并可以从外部访问"。MicroService CR 就是这个承诺的载体：镜像、副本、端口、域名四个字段说清意图，平台侧的编排细节（ConfigMap 挂载、Ingress 规则、级联清理）全部由 Operator 承担。这正是内部开发者平台（IDP）的最小雏形——CR 是平台的 API，Controller 是平台的引擎。

## How

```bash
cd operators/10_microservice_operator
make install && make run
kubectl apply -f config/samples/platform_v1_microservice.yaml
kubectl get microservice,deploy,svc,ingress,cm -l app.kubernetes.io/managed-by=microservice-operator
kubectl delete microservice user-service    # 验证级联清理
```

## Deep Dive

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

实现范围（诚实清单）：

| 能力 | 状态 |
|:---|:---|
| ConfigMap + Deployment + Service + Ingress 四件套编排 | ✅ |
| OwnerReference 级联清理 | ✅ |
| status Available Condition | ✅ |
| HPA（hpaEnabled/minReplicas 字段） | 🚧 字段已预留，Reconcile 未实现 |
| Validating Webhook / LeaderElection / Metrics（清单规划项） | ⬜ 未实现 |

本实验在 kubernetes_operator.md 清单中未勾选——Webhook、LeaderElection、Metrics 是毕业部分的剩余内容。

## Q&A

**Q1: 一个 CR 编排多少资源算合适？**
按"独立生命周期"划分：同生共死的放一个 CR（本实验四件套跟着服务走），可独立演化的拆开（数据库、缓存不该和微服务绑死，见 lab 02/03 的独立 CRD）。资源越多 Reconcile 越重、级联爆炸半径越大——"CR 数量"本身就是架构决策。

**Q2: OwnerReference 级联清理方便但有什么代价？**
它太隐式了：误删 CR = 全栈消失，没有二次确认。生产可给关键资源改用"无 ownerRef + Finalizer"的显式清理（lab 02 的做法）——删除前有机会执行备份、通知、审批，把"删"从副作用变成流程。

**Q3: 从"能跑"到"生产可用"还差什么？**
三件事：准入校验（Validating Webhook 拒掉 latest 镜像、root 容器，见 lab 21 的 Kyverno 思路）、多副本高可用（LeaderElection 让 Controller 本身不成为单点）、可观测（暴露 metrics 接进 Prometheus，见 lab 23）。实验覆盖的是 Reconcile 正确性，这三项覆盖的是运营正确性。
