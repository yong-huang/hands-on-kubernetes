# 01 · App 资源管家 Operator

> 用 kubebuilder 实现的最小可用 Operator：一个 `App` CR 声明镜像、副本数、环境变量与配置，Controller 自动编排 ConfigMap + Deployment + Service 三件套——覆盖 Reconcile 幂等、OwnerReference 级联删除、Owns 漂移自愈、status 上报、Finalizer 清理全部核心模式。

## What

一个 `App` CR 长这样：

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

apply 这段 YAML 后：三件套自动出现 → 改 `replicas` 自动伸缩 → 手改子资源自动拉回 → 删 CR 级联清理。一句话心智模型：**声明什么就是什么**——这就是 Operator 模式。

## Why

一个应用的运行要靠 ConfigMap + Deployment + Service 三件套配合：配置变了要同步挂载、组件要一起创建一起清理、副本数被人改了要有人发现。手工维护这些关联，漏一步就是事故。Operator 把"一组资源的管理经验"封装进 Controller：用户只声明期望（一个 CR），关联编排、漂移自愈、级联清理全部由 Reconcile 循环收敛——这也是 lab 29 的 CRD 模式第一次拥有完整的"生老病死"生命周期。

## How

```bash
cd operators/01_app_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller（另开终端）
kubectl apply -f config/samples/app_v1_app.yaml
kubectl get app,deploy,svc,cm -l app.kubernetes.io/name=app-sample
kubectl delete app app-sample   # 级联清理验证
```

诚实预期：`make run` 前台阻塞属正常；`delete app` 后可观察 Finalizer 两阶段——先清理模拟的外部资源（externalID），再放行删除。

## Deep Dive

**Reconcile 三步**：① 读 CR 期望 → ② CreateOrPatch 三个子资源（mutate 保证 spec 对齐）→ ③ 读 Deployment 实际状态回写 `status.conditions`。虚线是反向通道：子资源被手改触发 Owns 事件 → 重新调谐拉回；status 回写走 `/status` 子资源（避免事件风暴）。

三个子资源是同一模式的复制——构造期望 → SetControllerReference → CreateOrPatch：

```go
cm := r.desiredConfigMap(&app)
controllerutil.SetControllerReference(&app, cm, r.Scheme)
op, err := controllerutil.CreateOrPatch(ctx, r.Client, cm, func() error {
    cm.Data = app.Spec.ConfigData     // mutate：每次以 spec 覆盖，漂移被拉回
    return controllerutil.SetControllerReference(&app, cm, r.Scheme)
})
```

- **Owns()**：等价于手动 watch 子资源 + ownerRef 映射回主资源，是"派生资源变化触发调谐"的声明式写法——Deployment/ConfigMap/Service 变化都触发 Reconcile，手改子资源会被拉回；
- **status 上报**：读 Deployment `ReadyReplicas` → 写 `Available` Condition；
- **Finalizer**（`app.example.com/finalizer`）：删除时先清理模拟的外部资源（externalID），再移除 finalizer 放行——完整两阶段删除。

踩坑清单：

- **CreateOrPatch vs Create**：Create 只管首次，已存在时会被跳过——spec 变更后就不再收敛，是新手最常踩的坑。

验收记录（2026-09-04/05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR → 三件套自动出现，ownerRef=App | ✅ |
| patch replicas 2→4，Deployment 自动伸缩 | ✅ |
| 手改 Deployment 副本=1，Reconcile 自动拉回 4 | ✅ |
| status Available 随 Pod 就绪翻转 False→True | ✅ |
| 删 CR 三件套级联消失，Finalizer 两阶段可观测 | ✅ |

## Q&A

**Q1: Reconcile 为什么必须幂等？**
水平触发模型下同一对象可能被重复调谐（进程重启、事件丢失、周期兜底），Reconcile 不保证只跑一次——只有"当前状态 ≠ 期望状态才有动作、否则无事发生"的幂等实现才安全。这也是为什么代码里所有写操作都走 CreateOrPatch + mutate，而不是记录"我已经建过了"。

**Q2: status 为什么走 /status 子资源，而不是直接改 CR？**
直接改 CR 会触发自己的 watch 事件：controller 回写 status → 自己被唤醒 → 再回写……事件风暴。`subresources.status` 让 status 写入不更新 `resourceVersion` 的主资源语义（lab 29 的 spec/status 分权），controller 写 status 不会唤醒自己。
