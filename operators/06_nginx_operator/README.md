# 06 · Nginx 反向代理 Operator：配置即资源

> 声明式 Nginx 配置：一个 `NginxProxy` CR 定义 upstreams 和 locations，Controller 把它们**渲染成 nginx.conf**、写入 ConfigMap 并挂载到 nginx Deployment——改 CR = 改 Nginx 配置，无需手动编辑文件或重启。

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

apply 后：nginx.conf 自动渲染 → ConfigMap → Deployment 挂载 → Service 暴露；改 CR 里的 upstream，配置自动更新并滚动生效。一句话心智模型：**配置即资源**——nginx.conf 不再是机器上的一个文件，而是 CR 渲染出的产物，版本、回滚、审计全部复用 CR 的工作流。

## Why

手工管 Nginx 配置的经典困境：配置文件散在各处、改了谁记不清、reload 之前不知道配置对不对。渲染-指纹模式把这些问题一次性解决：CR 是唯一事实源，渲染是可单测的纯函数，confHash 是"配置是否已部署"的幂等哨兵——`status` 里一句 `config <hash> deployed` 就能对账。这一模式同样适用于 Prometheus、Envoy、HAProxy 的配置管理类 Operator，是配置类 Operator 的通用套路。

## How

```bash
cd operators/06_nginx_operator
make install && make run
kubectl apply -f config/samples/web_v1_nginxproxy.yaml
kubectl get nginxproxy,cm,deploy,svc -l app.kubernetes.io/name=reverse-proxy
# 改 CR 里的 upstream 再观察 Pod 逐个滚动（config-hash 变化驱动）
```

## Deep Dive

渲染-比对的经典模式：`renderNginxConf()` 纯函数把 CR 渲染成配置文本 → SHA256 取 12 位 `confHash` → CreateOrPatch ConfigMap、Deployment（confHash 写入 Pod 模板注解 `config-hash`）、Service → **hash 变化 = 配置变化**，Pod 模板注解变更触发滚动更新，新配置随新 Pod 生效；status 上报 `config <hash> deployed`。

```go
// 纯函数渲染：CR → nginx.conf 文本（无副作用，好测试）
confHash := fmt.Sprintf("%x", sha256.Sum256([]byte(renderNginxConf(&np))))[:12]
// confHash 进 Pod 模板注解：模板一变，Deployment 自动滚动出新 Pod
dep.Spec.Template.Annotations = map[string]string{"config-hash": confHash}
// status 上报部署了哪个版本的配置，可观测可回溯
cond := metav1.Condition{ Message: fmt.Sprintf("config %s deployed", confHash), ... }
```

踩坑清单：

- **ConfigMap 热加载的延迟**：kubelet 同步 ConfigMap 有约 1 分钟延迟且文件是符号链接原子替换（见 lab 05），依赖"改了 ConfigMap 立即生效"必然踩坑——应用要么轮询、要么 `nginx -s reload`、要么滚动更新，三选一必须明确；本实验选择滚动。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR 声明的 upstream/location 路由生效 | ✅ |
| 改 CR 后 config-hash 变化、Pod 滚动、新配置生效 | ✅ |
| 删 CR 级联清理（复用 lab 01 的 OwnerReference 模式） | ✅ |

## Q&A

**Q1: 为什么用滚动更新而不是 `nginx -s reload`？**
滚动更稳妥——新配置跑在新 Pod 里，出问题回滚就是模板回滚；reload 更快（不换 Pod）但要求 Pod 能看到新 ConfigMap 且能收到信号，时序依赖多。教学实现选前者；生产高流量场景可用 reload + 共享 ConfigMap，但要把"reload 失败怎么办"也纳入 Reconcile。

**Q2: 为什么把 confHash 写进 Pod 模板注解，而不是只写 status？**
注解是 Pod 模板的一部分——注解变化必然触发滚动更新，等于把"配置版本"物化成了工作负载的定义。只写 status 的话，配置变了但 Pod 模板没变，K8s 不会做任何事。顺带的收益：回滚 = 模板回滚，hash 就是配置的版本号。

**Q3: 渲染函数为什么要写成纯函数？**
输入 CR、输出文本，没有 K8s API 调用和副作用——单元测试直接喂 CR 对象断言输出文本，不需要 fake client 和环境。配置渲染逻辑最容易藏边角案例（转义、空列表、重复 key），可单测性决定了它的可靠性上限。
