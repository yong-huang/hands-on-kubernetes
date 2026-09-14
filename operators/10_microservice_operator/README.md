# 端到端微服务 Operator（项目 10 · 毕业项目）

> 一个 `MicroService` CR 编排完整微服务栈：ConfigMap + Deployment + Service + Ingress，
> 全部子资源挂 OwnerReference 实现级联清理——融合 Reconcile 幂等 / 级联删除 /
> status 上报 / 声明式 API 等全部已学核心模式。

## 1. 它做什么

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

apply 后：ConfigMap（env/configData）→ Deployment → Service → Ingress 四件套自动出现；
status 上报 `Available` Condition；删 CR 四件套级联消失。

## 2. 架构总览

![ms stack](images/ms_stack.svg)

Reconcile 串行编排四种子资源，每种都是项目 1 练过的 CreateOrPatch +
SetControllerReference 模式：env/configData 进 ConfigMap，port/ingressHost
决定 Service 与 Ingress 形态， Condition 随子资源就绪情况翻转。
这是清单里前 9 个项目的"毕业合体"。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/10_microservice_operator/images/ms_stack.html)
> （或本地打开 [`images/ms_stack.html`](images/ms_stack.html)）。

## 3. 快速开始

```bash
cd operators/10_microservice_operator
make install && make run
kubectl apply -f config/samples/platform_v1_microservice.yaml
kubectl get microservice,deploy,svc,ingress,cm -l app.kubernetes.io/managed-by=microservice-operator
kubectl delete microservice user-service    # 验证级联清理
```

## 4. Reconcile 代码走读

```go
// 四种子资源同一模式：构造期望 → SetControllerReference → CreateOrPatch
cm := &corev1.ConfigMap{ Data: envFromSpec(ms.Spec.Env) + configData ... }
dep := &appsv1.Deployment{ Spec: ...(port、replicas、env 注入)... }
svc := &corev1.Service{ ... }
ing := &networkingv1.Ingress{ Spec: ...(ingressHost 路由)... }
// 逐个 CreateOrPatch 后汇总就绪情况，status 上报 Available Condition
cond := metav1.Condition{ Type: "Available", ... }
```

## 5. 实现范围（诚实清单）

| 能力 | 状态 |
|:---|:---|
| ConfigMap + Deployment + Service + Ingress 四件套编排 | ✅ |
| OwnerReference 级联清理 | ✅ |
| status Available Condition | ✅ |
| HPA（hpaEnabled/minReplicas 字段） | 🚧 字段已预留，Reconcile 未实现 |
| Validating Webhook / LeaderElection / Metrics（清单规划项） | ⬜ 未实现 |

项目 10 在 kubernetes_operator.md 清单中未勾选——Webhook、LeaderElection、
Metrics 是毕业部分的剩余内容。

## 6. 文件结构

```
10_microservice_operator/
├── internal/controller/microservice_controller.go   # 四件套编排 + status
├── config/samples/platform_v1_microservice.yaml
└── images/ms_stack.*                                # 架构图三件套
```

## 7. 深入要点

1. **一个 CR 编排多资源的边界**：资源越多 Reconcile 越重，拆分粒度应按"独立生命周期"
   划分——同生共死的放一个 CR，可独立演化的拆开；
2. **级联清理的代价**：OwnerReference 方便但隐式，误删 CR = 全栈消失；
   生产可给关键资源改用无 ownerRef + Finalizer 的显式清理；
3. **毕业清单还差什么**：准入校验（Webhook 拒 latest/root）、多副本高可用
   （LeaderElection）、可观测（metrics）——从"能跑"到"生产可用"的分界线。
