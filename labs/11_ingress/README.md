# Ingress 与域名路由

## 1. 引言

Service 的 NodePort 模式有三个痛点：端口随机难记、每个服务都要暴露一个端口、只能做四层转发。**Ingress** 把集群入口收敛成一个七层（HTTP/HTTPS）路由器：按**域名**（Host）和**路径**（Path）把流量转发给不同的 Service，还能集中做 TLS 终止。注意 Ingress 资源本身只是"路由规则"，真正干活的是 **Ingress Controller**（最常用是 ingress-nginx）——Controller watch Ingress 对象，把规则翻译成 nginx.conf 并热加载。

## 2. 文件结构

```
11_ingress/
├── README.md                 # 本文档
├── ingress.sh                # controller | apply | test | clean 四步演示
├── ingress-nginx-kind.yaml   # ingress-nginx 控制器清单（kind 定制版，本地缓存）
├── manifests/
│   └── ingress.yaml          # 两个后端 + 域名路由 Ingress + 路径路由 Ingress
└── images/
    ├── ingress_routing.architecture.json  # 图源（Archify Typed JSON IR）
    ├── ingress_routing.html               # 交互版架构图
    └── ingress_routing.svg                # 双主题矢量版（本文档 §6 内嵌）
```

## 3. 核心概念

### Ingress 资源 vs Ingress Controller

| | Ingress 资源 | Ingress Controller |
|---|---|---|
| 本质 | 一条路由规则（声明式） | 运行中的反向代理（nginx） |
| 谁消费 | Controller watch 并翻译 | 真正接流量、转发 |
| 数量 | 可以有很多条 | 通常一套（或高可用多副本） |

```yaml
spec:
  ingressClassName: nginx    # 指定由哪个 Controller 处理 (可以共存多个)
  rules:
    - host: a.example.com    # 域名路由
      http:
        paths:
          - path: /
            pathType: Prefix # Prefix 前缀匹配 / Exact 精确匹配
            backend:
              service:
                name: web-a
                port: {number: 80}
```

### 域名路由 vs 路径路由

- **域名路由**：`a.example.com` → web-a，`b.example.com` → web-b（虚拟主机）
- **路径路由**：`example.com/a` → web-a，`example.com/b` → web-b（同一域名下按 URL 前缀分流）
- 两者可组合使用；TLS 在 `spec.tls` 配置（生产用 cert-manager 自动签发）

### kind 集群的端口问题

kind 节点跑在容器网络里，宿主机要用 80/443 直连，**建集群时必须配 extraPortMappings**（见 ingress.sh 的说明）。不重建集群时可用 `kubectl port-forward` 测试，测试时用 `curl -H "Host: a.example.com"` 伪造域名。

## 4. YAML 关键字段

| 字段 | 含义 | 坑 |
|---|---|---|
| `ingressClassName` | 绑定 Controller | 不写会用默认 class，多 Controller 时必写 |
| `rules[].host` | 匹配的域名 | 不写 host = 匹配所有（默认后端） |
| `pathType: Prefix` | 前缀匹配 | `/a` 会匹配 `/a/x`；Exact 则只匹配 `/a` |
| `backend.service` | 转发目标 | 填 Service 名 + 端口，不是 Pod |
| `tls.secretName` | TLS 证书 Secret | cert-manager 可自动签发续期 |

## 5. 国内网络注意

ingress-nginx 的镜像来自 `registry.k8s.io`，节点内拉取会 TLS 超时，需先在宿主机预载：

```bash
cd ../../scripts && ./load_images.sh \
  registry.k8s.io/ingress-nginx/controller:v1.x.x \
  registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.x.x
# 具体 tag 以清单 image: 字段为准
```

安装清单从 raw.githubusercontent.com 下载，若超时可手动下载存为 `ingress-nginx-kind.yaml`（脚本优先用本地文件）。

## 6. 可视化

![Ingress 路由](images/ingress_routing.svg)

流量路径：客户端带 Host 头请求 → **ingress-nginx Controller**（唯一入口）→ 按 Ingress 规则转发到 web-a / web-b 的 Service → Pod。虚线是控制面：Controller watch Ingress 资源，把规则翻译成 nginx.conf 并热加载——**资源只是规则，Controller 才是执行者**。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/11_ingress/images/ingress_routing.html)（或本地打开 [`images/ingress_routing.html`](images/ingress_routing.html)）。

## 7. 面试要点

**Q1: Ingress 和 Service 的区别？**
Service 是四层负载均衡（IP:Port），Ingress 在其之上提供七层路由（域名/路径/TLS）。Ingress 转发的目标仍然是 Service——它是"Service 的前台网关"。

**Q2: Ingress 资源本身能转发流量吗？**
不能。它只是存在 etcd 里的规则；必须部署 Ingress Controller 来 watch 并执行。没装 Controller 的 Ingress 就是一纸空文。

**Q3: ingressClassName 的作用？**
集群里可以同时跑多个 Controller（如 nginx + traefik），class 决定这条规则由谁处理。不指定则由默认 class（`ingressclass.kubernetes.io/is-default-class`）接管。

**Q4: 如何做灰度/金丝雀？**
nginx Ingress 支持 canary 注解（按权重/header/cookie 分流）；更复杂的流量治理用 Service Mesh（Istio VirtualService）。

**Q5: TLS 终止发生在哪？**
在 Controller 上（443 → 后端明文 80）。需要对后端也加密时配置 `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`。

## 8. 总结

- Ingress = 一个入口 + 域名/路径路由 + TLS 终止，解决 NodePort 的端口爆炸问题
- Ingress 资源只是规则，Controller（nginx）才是执行者，靠 watch 机制热加载配置
- kind 上要在宿主机用 80 端口，建集群时需 extraPortMappings
- 测试用 `curl -H "Host: xxx"` 伪造域名，无需真实 DNS
- 更复杂的七层治理（重试/熔断/灰度）是 Service Mesh 的领域
