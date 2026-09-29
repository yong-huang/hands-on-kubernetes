# 06 · Nginx 反向代理 Operator：配置即资源

> 声明式 Nginx 配置：一个 `NginxProxy` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 定义 upstreams（上游后端列表：请求最终转发给谁）和 locations（路径规则：什么路径转发给哪个 upstream），Controller 把它们**渲染成 nginx.conf**、写入 ConfigMap 并挂载到 nginx Deployment——改 CR = 改 Nginx 配置，无需手动编辑文件或重启。读完本篇，你将掌握"渲染 → 指纹 → 收敛"这一配置类 Operator 的通用套路。

## Background

手工管 Nginx 配置的日常是：ssh 到机器（或进 Pod）编辑 nginx.conf，检查语法，reload——配置文件散落在各处，改了谁、改了什么、什么时候改的，全靠记忆和备份文件。配置错了 reload 失败，线上还是旧配置，排查从"哪份配置是对的"开始。

渲染-指纹模式把这些问题一次性解决：CR 是唯一事实源，渲染是可单测的纯函数，confHash 是"配置是否已部署"的幂等哨兵——`status` 里一句 `config <hash> deployed` 就能对账。这一模式同样适用于 Prometheus、Envoy、HAProxy 的配置管理类 Operator。

## What

一个 `NginxProxy` CR 长这样：

```yaml
apiVersion: web.example.com/v1
kind: NginxProxy
metadata: { name: reverse-proxy }
spec:
  upstreams:
    - { name: app, servers: ["web-a:80", "web-b:80"] }
  locations:
    - { path: "/", upstream: "app" }
```

apply 后：nginx.conf 自动渲染 → ConfigMap → Deployment 挂载 → Service 暴露；改 CR 里的 upstream，配置自动更新并滚动生效。

一句话心智模型：**配置即资源**——可以把 CR 想象成"nginx.conf 的源码"；但和源码不同的是，它有运行时的对账信息（status 里的 hash），"配置是否已生效"不再靠猜。

| 产物 | 角色 |
|---|---|
| renderNginxConf() 纯函数 | CR → nginx.conf 文本 |
| confHash（SHA256 前 12 位） | 配置版本指纹 |
| ConfigMap | 挂载到 Pod 的实际配置 |
| `config-hash` 注解 | 驱动滚动更新的版本标记 |

## When to Use

典型场景：多个环境统一管理代理路由（每个环境一份 CR，diff 即知差异）；给不熟悉 nginx 语法的团队提供受约束的配置面；配置变更需要审计与回滚（hash 就是版本号）。

何时不用：需要 nginx 全量能力（stream、lua、复杂 rewrite）的场景——CR 只暴露了 upstream/location 子集；配置变更极频繁且要求秒级生效（滚动更新分钟级，reload 模式更合适，见 Q1）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 手工编辑 nginx.conf | 灵活但无对账无审计 | 单机临时场景 |
| ConfigMap 手挂 | 有声明式但无渲染与版本指纹 | 简单固定配置 |
| 渲染型 Operator（本实验） | CR → 渲染 → 指纹 → 收敛 | 配置面需要收敛与审计 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用。

```bash
cd operators/06_nginx_operator
make install && make run
kubectl apply -f config/samples/web_v1_nginxproxy.yaml
kubectl get nginxproxy,cm,deploy,svc -l app.kubernetes.io/name=reverse-proxy
# 改 CR 里的 upstream 再观察 Pod 逐个滚动（config-hash 变化驱动）
```

诚实预期：改 CR 后配置生效走滚动更新（新配置跑在新 Pod 里），全程几十秒，不是 reload 的秒级——这是刻意的取舍（见 Q1）。

## How It Works

渲染-比对的经典模式：`renderNginxConf()` 纯函数把 CR 渲染成配置文本，SHA256 取 12 位 `confHash`，随后 CreateOrPatch ConfigMap、Deployment（confHash 写入 Pod 模板注解 `config-hash`）、Service。

**hash 变化 = 配置变化**：Pod 模板注解变更触发滚动更新，新配置随新 Pod 生效，status 上报 `config <hash> deployed`。

```go
// 纯函数渲染：CR → nginx.conf 文本（无副作用，好测试）
confHash := fmt.Sprintf("%x", sha256.Sum256([]byte(renderNginxConf(&np))))[:12]
// confHash 进 Pod 模板注解：模板一变，Deployment 自动滚动出新 Pod
dep.Spec.Template.Annotations = map[string]string{"config-hash": confHash}
// status 上报部署了哪个版本的配置，可观测可回溯
cond := metav1.Condition{ Message: fmt.Sprintf("config %s deployed", confHash), ... }
```

踩坑清单：

- **ConfigMap 热加载的延迟**：kubelet 同步 ConfigMap 有约 1 分钟延迟且文件是符号链接原子替换（labs/05），依赖"改了 ConfigMap 立即生效"必然踩坑——应用要么轮询、要么 `nginx -s reload`、要么滚动更新，三选一必须明确；本实验选择滚动。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR 声明的 upstream/location 路由生效 | ✅ |
| 改 CR 后 config-hash 变化、Pod 滚动、新配置生效 | ✅ |
| 删 CR 级联清理（复用 operators/01 的 OwnerReference 模式） | ✅ |

## Pitfalls & Q&A

**Q1: 为什么用滚动更新而不是 `nginx -s reload`？**

滚动更稳妥——新配置跑在新 Pod 里，出问题回滚就是模板回滚；reload 更快（不换 Pod）但要求 Pod 能看到新 ConfigMap 且能收到信号，时序依赖多。教学实现选前者；生产高流量场景可用 reload + 共享 ConfigMap，但要把"reload 失败怎么办"也纳入 Reconcile。

**Q2: 为什么把 confHash 写进 Pod 模板注解，而不是只写 status？**

注解是 Pod 模板的一部分——注解变化必然触发滚动更新，等于把"配置版本"物化成了工作负载的定义。只写 status 的话，配置变了但 Pod 模板没变，K8s 不会做任何事。顺带的收益：回滚 = 模板回滚，hash 就是配置的版本号。

**Q3: 渲染函数为什么要写成纯函数？**
输入 CR、输出文本，没有 K8s API 调用和副作用——单元测试直接喂 CR 对象断言输出文本，不需要 fake client 和环境。配置渲染逻辑最容易藏边角案例（转义、空列表、重复 key），可单测性决定了它的可靠性上限。
