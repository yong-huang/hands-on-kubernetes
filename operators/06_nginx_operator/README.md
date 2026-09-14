# Nginx 反向代理 Operator（项目 6）

> 声明式 Nginx 配置：一个 `NginxProxy` CR 定义 upstreams 和 locations，
> Controller 把它们**渲染成 nginx.conf**、写入 ConfigMap 并挂载到 nginx Deployment——
> 改 CR = 改 Nginx 配置，无需手动编辑文件或重启。

## 1. 它做什么

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

apply 后：nginx.conf 自动渲染 → ConfigMap → Deployment 挂载 → Service 暴露。
改 CR 里的 upstream，配置自动更新并滚动生效。

## 2. 架构总览

![Nginx flow](images/nginx_flow.svg)

渲染-比对的经典模式：`renderNginxConf()` 纯函数把 CR 渲染成配置文本 →
SHA256 取 12 位 `confHash` → CreateOrPatch ConfigMap、Deployment（confHash 写入
Pod 模板注解 `config-hash`）、Service → **hash 变化 = 配置变化**，Pod 模板注解变更
触发滚动更新，新配置随新 Pod 生效；status 上报 `config <hash> deployed`。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/06_nginx_operator/images/nginx_flow.html)
> （或本地打开 [`images/nginx_flow.html`](images/nginx_flow.html)）。

## 3. 快速开始

```bash
cd operators/06_nginx_operator
make install && make run
kubectl apply -f config/samples/web_v1_nginxproxy.yaml
kubectl get nginxproxy,cm,deploy,svc -l app.kubernetes.io/name=reverse-proxy
# 改 CR 里的 upstream 再观察 Pod 逐个滚动（config-hash 变化驱动）
```

## 4. Reconcile 代码走读

```go
// 纯函数渲染：CR → nginx.conf 文本（无副作用，好测试）
confHash := fmt.Sprintf("%x", sha256.Sum256([]byte(renderNginxConf(&np))))[:12]
// confHash 进 Pod 模板注解：模板一变，Deployment 自动滚动出新 Pod
dep.Spec.Template.Annotations = map[string]string{"config-hash": confHash}
// status 上报部署了哪个版本的配置，可观测可回溯
cond := metav1.Condition{ Message: fmt.Sprintf("config %s deployed", confHash), ... }
```

- **配置渲染为什么用纯函数**：输入 CR 输出文本，单测不需要 mock K8s；
- **hash 做幂等哨兵**：文本级 diff 转成一个 12 位指纹，status 对比即可判断"配置是否已部署"；
- **滚动更新 vs nginx -s reload**：滚动更稳妥（新配置新 Pod），reload 更快但要求共享
  ConfigMap 且旧 Pod 能收到信号——教学实现选前者。

## 5. 验收记录（2026-09-05，kind v1.36）

| 验收项 | 结果 |
|:---|:---|
| CR 声明的 upstream/location 路由生效 | ✅ |
| 改 CR 后 config-hash 变化、Pod 滚动、新配置生效 | ✅ |
| 删 CR 级联清理（复用项目 1 的 OwnerReference 模式） | ✅ |

## 6. 文件结构

```
06_nginx_operator/
├── internal/controller/nginxproxy_controller.go   # 渲染 + 三件套编排 + hash 上报
├── config/samples/web_v1_nginxproxy.yaml
└── images/nginx_flow.*                            # 架构图三件套
```

## 7. 深入要点

1. **声明式配置管理的通用套路**：CR（期望）→ 渲染（纯函数）→ 指纹（hash）→ 子资源收敛，
   这一模式同样适用于 Prometheus/Envoy/Haproxy 的配置管理类 Operator；
2. **ConfigMap 热加载的坑**：kubelet 同步 ConfigMap 有约 1 分钟延迟且文件是符号链接
   原子替换，应用要么轮询、要么 nginx -s reload、要么滚动——三选一必须明确；
3. **为什么把 hash 写进 Pod 注解**：注解变化必然触发滚动，把"配置版本"变成
   Pod 模板的一部分，回滚 = 模板回滚。
