# 11 · Ingress：七层域名路由与 TLS 终止

> Service 的 NodePort 模式有三个痛点：端口随机难记、每个服务都要暴露一个端口、只能做四层转发。**Ingress** 把集群入口收敛成一个七层（HTTP/HTTPS）路由器：按**域名**（Host）和**路径**（Path）把流量转发给不同的 Service，还能集中做 TLS 终止（HTTPS 加密流量在入口处解密，证书只在这一处配置，后端只需明文 HTTP）。读完本篇，你将分清 Ingress 资源与 Controller 的分工，并在 kind 上跑通域名与路径路由。

## Background

服务多了以后，NodePort 入口的管理成本快速上升：每个服务占一个 30000+ 的随机端口，调用方记不住；想用"同一域名下不同路径"组织 API，NodePort 只有 IP:端口转发能力，做不到；HTTPS 证书要每个服务各配一份。

传统的解法是在集群外架一个 nginx，手工维护"域名 → 上游地址"的配置文件——但 Pod IP 一直在变，nginx 配置就要人工跟着改。Ingress 把这件事搬进 K8s：路由规则是声明式对象，反向代理（Controller）自动 watch 规则变化并热加载配置。

## What

Ingress 是七层路由规则：按域名和路径把外部流量转发给集群内的 Service。

一句话心智模型：**Ingress 资源只是规则，Ingress Controller 才是执行者**——Controller（最常用 ingress-nginx）watch Ingress 对象，把规则翻译成 nginx.conf 并热加载。

但和"nginx 配置文件"不同的是，规则存在 etcd（K8s 集群的统一存储库，所有资源对象的真源）里、走 K8s API 校验与审计，没有 Controller 时规则只是躺在 etcd 里的一纸空文。

| | Ingress 资源 | Ingress Controller |
|---|---|---|
| 本质 | 一条路由规则（声明式） | 运行中的反向代理（nginx） |
| 谁消费 | Controller watch 并翻译 | 真正接流量、转发 |
| 数量 | 可以有很多条 | 通常一套（或高可用多副本） |

两种路由维度，可组合使用：**域名路由**——`a.example.com` → web-a，`b.example.com` → web-b（虚拟主机）；

**路径路由**——`example.com/a` → web-a，`example.com/b` → web-b（同一域名下按 URL 前缀分流）。TLS 在 `spec.tls` 配置，生产用 cert-manager 自动签发。

## When to Use

典型场景：多个服务共用 80/443 对外入口（按域名区分）；单一域名下按路径拆分 API（`/api/user`、`/api/order`）；集中管理 HTTPS 证书与跳转。

何时不用：非 HTTP 协议（gRPC 裸 TCP、数据库连接——Ingress 是七层 HTTP 路由器，四层用 Service/LB）；集群内部服务互调（直接 ClusterIP，不必绕外部入口）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| NodePort | 每服务一个端口，无七层能力 | 临时调试 |
| LoadBalancer | 每服务一个云 LB，成本高 | 只有一两个对外服务 |
| Ingress | 一个入口 + 域名/路径路由 + TLS | 多个 HTTP 服务的标准收敛方案 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；国内网络需先预载 ingress-nginx 镜像（见本篇末尾）。

```bash
cd labs/11_ingress
./ingress.sh controller   # 安装 ingress-nginx（kind 定制清单，本地缓存）
./ingress.sh apply        # 部署两个后端 + 域名路由 Ingress + 路径路由 Ingress
./ingress.sh test         # curl -H "Host: ..." 验证域名/路径路由
./ingress.sh clean
```

成功判据：`test` 步骤同一个入口 IP、不同 `Host` 头分别返回 web-a 与 web-b 的响应；路径路由里 `/api` 前缀命中路径规则（实际响应以运行为准）。对应的关键字段：

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

**kind 集群的端口问题**：kind 节点跑在容器网络里，宿主机要用 80/443 直连，**建集群时必须配 extraPortMappings**（见 `ingress.sh` 的说明）。

不重建集群时可用 `kubectl port-forward` 测试，测试时用 `curl -H "Host: a.example.com"` 伪造域名，无需真实 DNS。

**国内网络注意**：ingress-nginx 的镜像来自 `registry.k8s.io`，节点内拉取会 TLS 超时，需先在宿主机预载：

```bash
cd ../../scripts && ./load_images.sh \
  registry.k8s.io/ingress-nginx/controller:v1.x.x \
  registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.x.x
# 具体 tag 以清单 image: 字段为准
```

安装清单从 raw.githubusercontent.com 下载，若超时可手动下载存为 `ingress-nginx-kind.yaml`（脚本优先用本地文件）。

## How It Works

关键字段速查：`ingressClassName` 绑定 Controller（不写会用默认 class，多 Controller 时必写）；`rules[].host` 匹配的域名（不写 = 匹配所有，即默认后端）。

`pathType: Prefix` 前缀匹配（`/a` 会命中 `/a/x`，Exact 只匹配 `/a`）。

`backend.service` 填 Service 名 + 端口（不是 Pod）；`tls.secretName` 指向 TLS 证书 Secret（cert-manager 可自动签发续期）。

**流量路径**：客户端带 Host 头请求 → **ingress-nginx Controller**（唯一入口）→ 按 Ingress 规则转发到 web-a / web-b 的 Service → Pod。

控制面是另一条线：Controller watch Ingress 资源，把规则翻译成 nginx.conf 并热加载——你在 `test` 步骤看到的"同一个 IP，不同 Host 头进不同服务"，就是这条"watch → 渲染 → 热加载"链路的效果。

没装 Controller 的 Ingress 就是一纸空文。

**TLS 终止发生在 Controller 上**：443 收加密流量，转发给后端的是明文 80。需要对后端也加密时配置 `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`。

**ingressClassName 的归属机制**：集群里可以同时跑多个 Controller（如 nginx + traefik），class 决定这条规则由谁处理；不指定则由默认 class（带 `ingressclass.kubernetes.io/is-default-class` 注解的那个）接管。

## Pitfalls & Q&A

踩坑清单：

- kind 上 80 端口不通：建集群时没配 extraPortMappings，重建集群或在测试时用 port-forward。
- 路由不生效先查两处：`ingressClassName` 是否写对；Controller 是否已安装并在运行。
- Prefix 匹配超出预期：`/a` 会命中 `/a/x`，需要精确匹配用 `pathType: Exact`。

**Q1: Ingress 和 Service 的区别？**
Service 是四层负载均衡（IP:Port），Ingress 在其之上提供七层路由（域名/路径/TLS）。Ingress 转发的目标仍然是 Service——它是"Service 的前台网关"，对应关系见 lab 04 的四种 Service 类型。

**Q2: 如何做灰度/金丝雀发布？**
nginx Ingress 支持 canary 注解（按权重/header/cookie 分流），适合"一小部分流量进新版本"的场景；更复杂的流量治理（重试/熔断/精细灰度）是 Service Mesh 的领域，见 lab 13 的 Istio VirtualService。
