# App 资源管家 Operator（项目 1）

> 用 kubebuilder 实现的最小可用 Operator：一个 `App` CR 声明镜像、副本数、环境变量与配置，
> Controller 自动编排 ConfigMap + Deployment + Service 三件套——覆盖 Reconcile 幂等、
> OwnerReference 级联删除、Owns 漂移自愈、status 上报、Finalizer 清理全部核心模式。

## 1. 它做什么

```yaml
apiVersion: app.example.com/v1
kind: App
metadata: { name: app-sample }
spec:
  image: nginx:alpine
  replicas: 2
  env: { TZ: Asia/Shanghai }
  configData: { APP_MODE: production }
```

apply 这段 YAML 后：三件套自动出现 → 改 `replicas` 自动伸缩 → 手改子资源自动拉回 →
删 CR 级联清理。**声明什么就是什么**，这就是 Operator 模式。

## 2. 架构总览

![App Reconcile](images/app_reconcile.svg)

Reconcile 三步：① 读 CR 期望 → ② CreateOrPatch 三个子资源（mutate 保证 spec 对齐）→
③ 读 Deployment 实际状态回写 `status.conditions`。虚线是反向通道：子资源被手改触发
Owns 事件 → 重新调谐拉回；status 回写走 `/status` 子资源（避免事件风暴）。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/01_app_operator/images/app_reconcile.html)
> （或本地打开 [`images/app_reconcile.html`](images/app_reconcile.html)）。

## 3. 快速开始

```bash
cd operators/01_app_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller（另开终端）
kubectl apply -f config/samples/app_v1_app.yaml
kubectl get app,deploy,svc,cm -l app.kubernetes.io/name=app-sample
kubectl delete app app-sample   # 级联清理验证
```

## 4. Reconcile 代码走读

```go
// 三个子资源同一模式：构造期望 → SetControllerReference → CreateOrPatch
cm := r.desiredConfigMap(&app)
controllerutil.SetControllerReference(&app, cm, r.Scheme)
op, err := controllerutil.CreateOrPatch(ctx, r.Client, cm, func() error {
    cm.Data = app.Spec.ConfigData     // mutate：每次以 spec 覆盖，漂移被拉回
    return controllerutil.SetControllerReference(&app, cm, r.Scheme)
})
```

- **Owns()**：Deployment/ConfigMap/Service 变化都触发 Reconcile——手改子资源会被拉回；
- **status 上报**：读 Deployment `ReadyReplicas` → 写 `Available` Condition；
- **Finalizer**（`app.example.com/finalizer`）：删除时先清理模拟的外部资源
  （externalID），再移除 finalizer 放行——完整两阶段删除。

## 5. 验收记录（2026-09-04/05，kind v1.36）

| 验收项 | 结果 |
|:---|:---|
| CR → 三件套自动出现，ownerRef=App | ✅ |
| patch replicas 2→4，Deployment 自动伸缩 | ✅ |
| 手改 Deployment 副本=1，Reconcile 自动拉回 4 | ✅ |
| status Available 随 Pod 就绪翻转 False→True | ✅ |
| 删 CR 三件套级联消失，Finalizer 两阶段可观测 | ✅ |

## 6. 文件结构

```
01_app_operator/
├── README.md                        # 本文档
├── cmd/main.go                      # kubebuilder 入口
├── api/v1/                          # App 类型定义 + deepcopy
├── internal/controller/             # Reconcile 核心（app_controller.go）
├── config/                          # CRD / RBAC / manager 部署清单
└── images/
    ├── app_reconcile.architecture.json  # 图源（Typed JSON IR）
    ├── app_reconcile.html               # 交互版架构图
    └── app_reconcile.svg                # 双主题矢量版（本文档 §2 内嵌）
```

## 7. 面试要点

1. **Reconcile 为什么必须幂等**：水平触发模型下同一对象可能被重复调谐（重启/事件丢失），只有幂等才安全；
2. **Owns() 的作用**：等价于手动 watch 子资源 + ownerRef 映射回主资源，是"派生资源变化触发调谐"的声明式写法；
3. **status 为什么走子资源**：避免 controller 回写 status 触发自己的 watch 事件风暴；
4. **CreateOrPatch vs Create**：Create 只管首次，已存在时会被跳过——spec 变更后就不再收敛，是新手最常踩的坑。
