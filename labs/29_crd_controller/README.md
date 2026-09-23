# 29 · CRD 与 Controller：Operator 模式的最小闭环

> K8s 的可扩展性核心在于：API Server 不需要内置所有概念。本实验自定义一个 `Database` CRD——用户声明"我要一个 postgres/10Gi"，**Controller 的 Reconcile 循环**负责创建对应的 StatefulSet 并回写 status——亲手实现 Operator Pattern 的最小闭环。

## What

CRD（Custom Resource Definition）给 API Server 长出新端点，Controller 让这个端点"有行为"：

| 部件 | 角色 |
|------|------|
| CRD | 注册新资源类型，`kubectl get db` 开箱即用 |
| Custom Resource（CR） | 用户的期望状态声明（"postgres/10Gi"） |
| Controller | Reconcile 循环：对比期望与实际，缺则建、漂移则 patch，回写 status |

一句话心智模型：**声明"我要什么"，控制器持续"调谐"到它**——这与命令式部署（跑一个脚本建资源）的本质区别在于：调谐没有"完成"的概念，只有"当前是否一致"。

## Why

"数据库"这类领域概念 K8s 不可能全部内置，但可以通过 CRD + Controller 让它们获得与原生资源同等的待遇：声明式 API、etcd 持久化、RBAC 控制、kubectl 可操作。掌握这个模式，就能读懂整个 K8s 生态——Prometheus Operator 的 ServiceMonitor、ArgoCD 的 Application（见 lab 28）都是同一模式的实例；也能把自己团队的运维经验沉淀成"提交一个 CR 就交付一个服务"的平台能力。

## How

```bash
cd labs/29_crd_controller
./crd_controller.sh crd      # 提交 Database CRD，验证 kubectl get db 可用
./crd_controller.sh deploy   # 提交 Database CR，观察 controller 创建 StatefulSet 并回写 status
./crd_controller.sh drift    # 手动把 STS 副本改成 2，看 controller 自动拉回 3（自愈）
./crd_controller.sh clean
```

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

## Deep Dive

**CRD 的三个关键点**：`openAPIV3Schema` 让非法 CR 在准入时就被拒（enum/pattern/min-max 全部生效）；`storage` 版本全局只能有一个；`v1alpha1 → v1beta1 → v1` 的演进靠 conversion webhook。

**spec/status 分权**：启用 `/status` 子资源后形成契约——**spec 由用户写**（期望状态），**status 只归 controller 写**（实际状态）。没有这一层，controller 回写状态会触发 watch 事件风暴——它自己写的东西又把自己唤醒。

**Reconcile 是水平触发，不是边沿触发**：Controller 不关心"发生了什么事件"（边缘触发），只对比"期望 vs 实际"（水平触发）。因此**幂等是灵魂**：重复执行、漏掉事件、进程重启都不会造成错误动作。drift 实验直接手动把 STS 副本改成 2，下一个循环 controller 自动拉回——这就是自愈的原理，也是 lab 03 Deployment 控制循环的同一机制。

**轮询只是教学版**：示例用 `while True + list` 每 10 秒轮询。生产级 Operator 用 **Informer + 工作队列**：watch 增量事件、按 `ns/name` 去重入队、限速重试。架构不变，只是驱动方式从"定时看一眼"变成"变化即触发 + 周期兜底"。

## Q&A

**Q1: 从教学版到生产级 Operator 还差什么？**
用 kubebuilder/controller-runtime（Operator SDK）替代裸 client-go，自动生成 informer/rbac/webhook 骨架；给 Database 加 defaulting/validation webhook，CR 提交时自动补默认值、拒绝非法值；加 Finalizer——删除 CR 时先清理外部资源（真实 DB 实例），避免孤儿。

**Q2: CRD 版本升级怎么演进？**
`v1alpha1 → v1` 的字段变更写 conversion webhook：API Server 在新旧版本之间自动转换，老 CR 无需迁移、消费方各自用自己认识的版本——版本是 API 的演进轨道，不是数据的迁移负担。

**Q3: 学会之后能读懂生态里的哪些东西？**
几乎所有"XXX Operator"：Prometheus Operator 把 ServiceMonitor 渲染成抓取配置，ArgoCD 把 Application 收敛到集群状态，本实验的 Database Controller 把 CR 变成 StatefulSet——同一个 Reconcile 模式，不同的领域对象。
