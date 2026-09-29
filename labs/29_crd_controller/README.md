# 29 · CRD 与 Controller：Operator 模式的最小闭环

> K8s 的可扩展性核心在于：API Server 不需要内置所有概念。本实验自定义一个 `Database` CRD——用户声明"我要一个 postgres/10Gi"，**Controller 的 Reconcile 循环**负责创建对应的 StatefulSet 并回写 status——亲手实现 Operator Pattern 的最小闭环。读完本篇，你将理解"调谐"与"命令式部署"的本质区别，并跑通自愈演示。

## Background

数据库、消息队列这类领域概念，K8s 内置对象管不了：Deployment 不知道"从库要等主库就绪"，更不知道"主库挂了怎么选新主"。早期的做法是运维把领域知识写成 runbook（操作手册）和脚本，出事按手册一步步敲——知识存在人脑和文档里，执行靠人。

Operator 模式把 runbook 变成程序：用 CRD（自定义资源定义）注册一个领域对象（如 `Database`），用一个 Controller 持续把实际状态向对象声明的期望状态调谐。

领域知识从"人读的文档"变成"机器执行的代码"——这是 K8s 生态繁荣的底层机制：Prometheus Operator、ArgoCD 全是这么造出来的。

## What

CRD（Custom Resource Definition）给 API Server 长出新端点，Controller 让这个端点"有行为"：

| 部件 | 角色 |
|------|------|
| CRD | 注册新资源类型，`kubectl get db` 开箱即用 |
| Custom Resource（CR） | 用户的期望状态声明（"postgres/10Gi"） |
| Controller | Reconcile 循环：对比期望与实际，缺则建、漂移则 patch，回写 status |

一句话心智模型：**声明"我要什么"，控制器持续"调谐"到它**——这与命令式部署（跑一个脚本建资源）的本质区别在于：调谐没有"完成"的概念，只有"当前是否一致"；脚本跑完就结束了，调谐循环永远在岗。

## When to Use

典型场景：把团队的运维经验（怎么部署、怎么备份、怎么扩容）沉淀成"提交一个 CR 就交付一个服务"的平台能力；管理 K8s 外部资源（见 lab 07 的模式）；为有状态中间件封装领域逻辑。

何时不用：一次性的内部小工具（CRD + Controller 的开发和维护成本不低，脚本可能更合适）；K8s 内置对象已覆盖的场景（能用 Deployment 就别造 `MyAppDeployment` CRD）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| runbook + 脚本 | 知识在文档里，执行靠人 | 临时运维 |
| Helm/Kustomize 模板 | 静态打包，无运行时行为 | 无持续调谐诉求 |
| CRD + Controller（Operator） | 领域对象 + 持续调谐 | 领域知识需要自动化 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；本地可运行 Go（`make run` 前台跑 Controller）。

```bash
cd labs/29_crd_controller
./crd_controller.sh crd      # 提交 Database CRD，验证 kubectl get db 可用
./crd_controller.sh deploy   # 提交 Database CR，观察 controller 创建 StatefulSet 并回写 status
./crd_controller.sh drift    # 手动把 STS（StatefulSet 的缩写）副本改成 2，看 controller 自动拉回 3（自愈）
./crd_controller.sh clean
```

诚实预期：`make run` 是前台进程，需要另开终端执行后续步骤；drift 实验的拉回发生在下一个轮询周期（约 10 秒内）。

CRD 关键字段（`manifests/database_crd.yaml`）：

```yaml
spec:
  group: demo.example.com
  names: {plural: databases, singular: database, shortNames: ["db"]}
  versions: [{name: v1alpha1, served: true, storage: true}]
  subresources:
    status: {}                 # 启用 /status 子资源
```

Controller 的 Reconcile 骨架（`controller.py`）：

```python
def reconcile(name):
    cr = CO.get_namespaced_custom_object(...)   # 读期望
    try: APPS.read_namespaced_stateful_set(...)
    except ApiException as e:
        if e.status == 404: APPS.create_(...)    # 缺 -> 建
        # 存在但漂移 -> patch
```

## How It Works

**CRD 的三个关键点**：`openAPIV3Schema` 让非法 CR 在准入时就被拒（enum/pattern/min-max 全部生效）；`storage` 版本全局只能有一个；`v1alpha1 → v1beta1 → v1` 的演进靠 conversion webhook。

**spec/status 分权**：启用 `/status` 子资源后形成契约——**spec 由用户写**（期望状态），**status 只归 controller 写**（实际状态）。没有这一层，controller 回写状态会触发 watch 事件风暴——它自己写的东西又把自己唤醒。

**Reconcile 是水平触发，不是边沿触发**：Controller 不关心"发生了什么事件"（边缘触发），只对比"期望 vs 实际"（水平触发，即每次都看全量现状）。因此**幂等是灵魂**：重复执行、漏掉事件、进程重启都不会造成错误动作。

drift 实验直接手动把 STS 副本改成 2，下一个循环 controller 自动拉回（STS 即 StatefulSet，见 Quick Start 的标注）——这就是自愈的原理，也是 lab 03 Deployment 控制循环的同一机制。

**轮询只是教学版**：示例用 `while True + list` 每 10 秒轮询。生产级 Operator 用 **Informer + 工作队列**：watch 增量事件、按 `ns/name` 去重入队、限速重试。架构不变，只是驱动方式从"定时看一眼"变成"变化即触发 + 周期兜底"。

## Pitfalls & Q&A

踩坑清单：

- 忘启用 `/status` 子资源：controller 回写状态触发事件风暴（见 How It Works）。
- Reconcile 里记录"我已经建过了"的本地状态：水平触发模型下必然出错——每次都对比期望与实际。
- CR 字段没写 openAPIV3Schema：非法值直到 Reconcile 才报错，排障成本高。

**Q1: 从教学版到生产级 Operator 还差什么？**

用 kubebuilder/controller-runtime（Operator SDK）替代裸 client-go，自动生成 informer/rbac/webhook 骨架；

给 Database 加 defaulting/validation webhook，CR 提交时自动补默认值、拒绝非法值；加 Finalizer——删除 CR 时先清理外部资源（真实 DB 实例），避免孤儿。

**Q2: CRD 版本升级怎么演进？**
`v1alpha1 → v1` 的字段变更写 conversion webhook：API Server 在新旧版本之间自动转换，老 CR 无需迁移、消费方各自用自己认识的版本——版本是 API 的演进轨道，不是数据的迁移负担。

**Q3: 学会之后能读懂生态里的哪些东西？**

几乎所有"XXX Operator"：Prometheus Operator 把 ServiceMonitor 渲染成抓取配置，ArgoCD 把 Application 收敛到集群状态（lab 28），

本实验的 Database Controller 把 CR 变成 StatefulSet——同一个 Reconcile 模式，不同的领域对象。
