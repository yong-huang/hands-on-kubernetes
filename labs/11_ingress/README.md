# 11 · Ingress 与域名路由

> Service 的 NodePort 模式有三个痛点：端口随机难记、每个服务都要暴露一个端口、只能做四层转发。**Ingress** 把集群入口收敛成一个七层（HTTP/HTTPS）路由器：按**域名**（Host）和**路径**（Path）把流量转发给不同的 Service，还能集中做 TLS 终止。

## What

Ingress 是七层路由规则：按域名和路径把外部流量转发给集群内的 Service。一句话心智模型：**Ingress 资源只是规则，Ingress Controller 才是执行者**——Controller（最常用 ingress-nginx）watch Ingress 对象，把规则翻译成 nginx.conf 并热加载。

| | Ingress 资源 | Ingress Controller |
|---|---|---|
| 本质 | 一条路由规则（声明式） | 运行中的反向代理（nginx） |
| 谁消费 | Controller watch 并翻译 | 真正接流量、转发 |
| 数量 | 可以有很多条 | 通常一套（或高可用多副本） |

两种路由维度，可组合使用：**域名路由**——`a.example.com` → web-a，`b.example.com` → web-b（虚拟主机）；**路径路由**——`example.com/a` → web-a，`example.com/b` → web-b（同一域名下按 URL 前缀分流）。TLS 在 `spec.tls` 配置，生产用 cert-manager 自动签发。

## Why

NodePort 的三个痛点决定了它只能当调试入口：端口随机难记、每个服务都要占一个节点端口、只有四层转发能力（没有域名/路径/TLS 概念）。服务一多，节点端口就爆炸，而且无法用"一个域名下的不同路径"组织 API。Ingress 把所有七层入口收敛到一个反向代理，对外只需要 80/443。

## How

```bash
cd labs/11_ingress
./ingress.sh controller   # 安装 ingress-nginx（kind 定制清单，本地缓存）
./ingress.sh apply        # 部署两个后端 + 域名路由 Ingress + 路径路由 Ingress
./ingress.sh test         # curl -H "Host: ..." 验证域名/路径路由
./ingress.sh clean
```

关键字段（`manifests/ingress.yaml`）：

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

| 字段 | 含义 | 坑 |
|---|---|---|
| `ingressClassName` | 绑定 Controller | 不写会用默认 class，多 Controller 时必写 |
| `rules[].host` | 匹配的域名 | 不写 host = 匹配所有（默认后端） |
| `pathType: Prefix` | 前缀匹配 | `/a` 会匹配 `/a/x`；Exact 则只匹配 `/a` |
| `backend.service` | 转发目标 | 填 Service 名 + 端口，不是 Pod |
| `tls.secretName` | TLS 证书 Secret | cert-manager 可自动签发续期 |

**kind 集群的端口问题**：kind 节点跑在容器网络里，宿主机要用 80/443 直连，**建集群时必须配 extraPortMappings**（见 `ingress.sh` 的说明）。不重建集群时可用 `kubectl port-forward` 测试，测试时用 `curl -H "Host: a.example.com"` 伪造域名，无需真实 DNS。

**国内网络注意**：ingress-nginx 的镜像来自 `registry.k8s.io`，节点内拉取会 TLS 超时，需先在宿主机预载：

```bash
cd ../../scripts && ./load_images.sh \
  registry.k8s.io/ingress-nginx/controller:v1.x.x \
  registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.x.x
# 具体 tag 以清单 image: 字段为准
```

安装清单从 raw.githubusercontent.com 下载，若超时可手动下载存为 `ingress-nginx-kind.yaml`（脚本优先用本地文件）。

## Deep Dive

**流量路径**：客户端带 Host 头请求 → **ingress-nginx Controller**（唯一入口）→ 按 Ingress 规则转发到 web-a / web-b 的 Service → Pod。虚线是控制面：Controller watch Ingress 资源，把规则翻译成 nginx.conf 并热加载——没装 Controller 的 Ingress 就是一纸空文。

**TLS 终止发生在 Controller 上**：443 收加密流量，转发给后端的是明文 80。需要对后端也加密时配置 `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`。

**ingressClassName 的归属机制**：集群里可以同时跑多个 Controller（如 nginx + traefik），class 决定这条规则由谁处理；不指定则由默认 class（带 `ingressclass.kubernetes.io/is-default-class` 注解的那个）接管。

## Q&A

**Q1: Ingress 和 Service 的区别？**
Service 是四层负载均衡（IP:Port），Ingress 在其之上提供七层路由（域名/路径/TLS）。Ingress 转发的目标仍然是 Service——它是"Service 的前台网关"，对应关系见 lab 04 的四种 Service 类型。

**Q2: 如何做灰度/金丝雀发布？**
nginx Ingress 支持 canary 注解（按权重/header/cookie 分流），适合"一小部分流量进新版本"的场景；更复杂的流量治理（重试/熔断/精细灰度）是 Service Mesh 的领域，见 lab 13 的 Istio VirtualService。
