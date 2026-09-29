# 01 · App 资源管家 Operator

> 用 kubebuilder（K8s 官方的 Operator 脚手架框架，生成 Go 语言 Controller 项目骨架）实现的最小可用 Operator：一个 `App` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 声明镜像、副本数、环境变量与配置，Controller 自动编排 ConfigMap + Deployment + Service 三件套——覆盖 Reconcile 幂等、OwnerReference 级联删除、Owns 漂移自愈、status 上报、Finalizer 清理全部核心模式。读完本篇，你将跑通第一个"声明什么就是什么"的 Operator。

## Background

部署一个应用要同时维护 ConfigMap、Deployment、Service 三份清单，它们的关联全靠人记：配置挂载路径对不对、Service 选择器能不能选中 Pod、删应用时三件套是否删干净。靠人工维护这些关联，漏一步就是"配置更新了但 Pod 没挂到新配置"这类事故。

更早的对策是写部署脚本把这些步骤串起来——但脚本跑完就结束，之后有人手改了 Deployment 副本数，脚本不会知道。Operator 模式把"关联编排"变成常驻循环：一个 `App` CR 声明期望，Controller 持续把三件套收敛到声明状态。

本实验用 kubebuilder 实现这个最小闭环，覆盖 Operator 开发的全部核心模式。

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

apply 这段 YAML 后：三件套自动出现 → 改 `replicas` 自动伸缩 → 手改子资源自动拉回 → 删 CR 级联清理。一句话心智模型：**声明什么就是什么**——可以把 Controller 想象成"永不下班的运维"；但和运维不同的是，它只认 spec 与实际状态的差异，不认"我上次已经做过了"。

| 模式 | 在本实验中的体现 |
|---|---|
| Reconcile（调谐：Controller 的核心控制循环——对比 spec 期望与集群实际状态，有差异就收敛）幂等 | 所有写操作走 CreateOrPatch + mutate |
| OwnerReference 级联 | 三件套挂 ownerRef，删 CR 自动清理 |
| Owns 漂移自愈 | 子资源被手改触发重新调谐 |
| Finalizer 两阶段删除 | 先清理外部资源再放行删除 |

## When to Use

典型场景：团队要一个"提交一个 CR 就部署一个完整应用"的内部平台；多个服务共用同一套"ConfigMap + Deployment + Service"编排逻辑，想收敛成模板。

何时不用：单次部署、无持续收敛诉求（Helm/Kustomize 更轻）；领域逻辑复杂到需要状态机与外部系统交互（那是后续 Operator 实验的主题）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 裸 YAML 三件套 | 直白但关联靠人记 | 一次性部署 |
| Helm chart | 打包模板，无运行时收敛 | 无漂移防护诉求 |
| Operator（本实验） | 常驻循环 + 漂移自愈 + 级联 | 需要持续收敛的平台能力 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用（Controller 本地运行）。

```bash
cd operators/01_app_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller（另开终端）
kubectl apply -f config/samples/app_v1_app.yaml
kubectl get app,deploy,svc,cm -l app.kubernetes.io/name=app-sample
kubectl delete app app-sample   # 级联清理验证
```

诚实预期：`make run` 前台阻塞属正常；`delete app` 后可观察 Finalizer 两阶段——先清理模拟的外部资源（externalID），再放行删除。

## How It Works

**Reconcile 三步**：① 读 CR 期望 → ② CreateOrPatch 三个子资源（mutate 保证 spec 对齐）→ ③ 读 Deployment 实际状态回写 `status.conditions`。

反向通道是：子资源被手改触发 Owns 事件 → 重新调谐拉回；status 回写走 `/status` 子资源（避免事件风暴）。

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

验收记录（2026-09-04/05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR → 三件套自动出现，ownerRef=App | ✅ |
| patch replicas 2→4，Deployment 自动伸缩 | ✅ |
| 手改 Deployment 副本=1，Reconcile 自动拉回 4 | ✅ |
| status Available 随 Pod 就绪翻转 False→True | ✅ |
| 删 CR 三件套级联消失，Finalizer 两阶段可观测 | ✅ |

## Pitfalls & Q&A

踩坑清单：

- **CreateOrPatch vs Create**：Create 只管首次，已存在时会被跳过——spec 变更后就不再收敛，是新手最常踩的坑。
- 在 Reconcile 里记"我已经建过了"的本地状态：水平触发模型下重启即丢，每次都应对比期望与实际。

**Q1: Reconcile 为什么必须幂等？**

水平触发（每次调谐都重新对比期望与实际全量现状，不依赖"发生过什么事件"的记忆；相对的边缘触发只在事件发生那一刻动作一次）模型下同一对象可能被重复调谐（进程重启、事件丢失、周期兜底），Reconcile 不保证只跑一次。

只有"当前状态 ≠ 期望状态才有动作、否则无事发生"的幂等实现才安全。这也是为什么代码里所有写操作都走 CreateOrPatch + mutate，而不是记录"我已经建过了"。

**Q2: status 为什么走 /status 子资源，而不是直接改 CR？**

直接改 CR 会触发自己的 watch 事件：controller 回写 status → 自己被唤醒 → 再回写……事件风暴。

启用 `subresources.status` 后，status 写入只落在 status 字段、不改 spec（labs/29 的 spec/status 分权），controller 再配合"仅 spec 变化才触发调谐"的过滤，写 status 就不会唤醒自己。
