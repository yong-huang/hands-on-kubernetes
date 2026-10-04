# 33 · Gateway API：Ingress 的官方继任者

> Ingress 注解满天飞、Controller 各自为政的日子该结束了。Gateway API 是 K8s 官方的下一代路由标准：GatewayClass/Gateway/HTTPRoute 三层模型、角色化权限、原生按权重分流。本实验用 Envoy Gateway 在 kind 上跑通域名/路径/权重三种路由。读完本篇，你将能用 HTTPRoute 表达 lab 11 需要"注解魔法"才能做到的事。

## Background

Ingress 是 2015 年设计的，当时只有一个假设：每个集群装一个七层代理。十一年后的现实是：路由规则越写越依赖 Controller 私有注解（灰度、超时、重写各有各的写法）。

平台团队与应用团队共用一份 Ingress 清单，改个路由要跨权限审批；社区出现了几十种注解方言，可移植性归零。

Gateway API（2023 年 GA）是 K8s 官方对这套问题的回答：路由能力标准化为 CRD、按角色拆分资源——基础设施方管 GatewayClass/Gateway，应用团队管 HTTPRoute。它不做向后兼容，是"重新设计的 Ingress"。

## What

Gateway API 的三层模型把"想要什么"和"由谁实现"彻底分开：

| 资源 | 角色 | 类比 lab 11 |
|---|---|---|
| GatewayClass | 集群级：声明"由哪个 Controller 实现" | ingressClassName 的机制化 |
| Gateway | 基础设施方：监听哪些端口/协议 | Controller 的实例化入口 |
| HTTPRoute | 应用团队：域名/路径/权重路由规则 | Ingress 的 rules |

一句话心智模型：**Gateway 是"架好的桥头"，HTTPRoute 是"路牌"**——但和 Ingress 不同的是，路牌通过 `parentRefs` 显式挂到桥头，且两边可以由不同的人管、放在不同的 namespace、走不同的 RBAC。

| HTTPRoute 能力 | 写法 | 对照 Ingress |
|---|---|---|
| 域名路由 | `hostnames` | rules[].host |
| 路径路由 | `matches[].path` | paths[].path |
| **按权重分流** | `backendRefs[].weight` | nginx canary 注解（非标准） |

## When to Use

典型场景：新集群的七层入口（无历史包袱直接上标准）；多团队集群需要"网关归平台、路由归应用"的权限切分；金丝雀发布需要原生权重分流（不想上 lab 13 的 mesh 那么重的方案）。

何时不用：老 Controller 深度绑定且无迁移规划（Gateway API 要换 Controller 实现，如 Envoy Gateway/NGINX Gateway Fabric/Kong）。

TCP/UDP 路由是另一例外：TCPRoute/UDPRoute 还是实验性扩展，未进标准通道（只收录已转正 API 的 CRD 发布集）。

GRPCRoute 已于 v1.1 转正。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| Ingress（lab 11） | 注解方言、权限耦合 | 存量集群 |
| Gateway API（本实验） | 标准化、角色化、原生权重 | 新集群、多团队 |
| Service Mesh（lab 13） | 东西向 + 全链路治理 | 要灰度之外的熔断/mTLS |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；CRD 与 Envoy Gateway 清单需从 GitHub 下载（直连失败时按脚本提示缓存到本地）。

```bash
cd labs/33_gateway_api
./gateway.sh install   # Gateway API CRD + Envoy Gateway Controller
./gateway.sh deploy    # GatewayClass/Gateway + 两个后端 + HTTPRoute
./gateway.sh test      # 集群内 curl 验证域名/路径/权重
./gateway.sh clean
```

`test` 步骤的真实输出（节选）：

```
--- 域名路由 (Host: a.example.com) ---
v1
--- 路径路由 (/api 固定进 v2) ---
v2
--- 权重路由 (20 次请求统计 v1/v2 命中, 期望约 90/10) ---
v1=16 v2=4 (20 次是小样本, 围绕 18/2 波动、偶发 20/0 属正常)
```

诚实预期：Gateway 创建后 Envoy 数据面 Pod 要几十秒才出现（由 Controller 按需拉起）；在 kind 上 LoadBalancer 地址永远 `<pending>`，脚本用集群内 curl Pod 直连 Envoy Service 验证。

核心清单三段（`manifests/`）：

```yaml
# gatewayclass.yaml —— 声明"由谁实现"
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller

# gateway.yaml —— 基础设施方架桥
spec:
  gatewayClassName: eg             # 指向上面声明的类
  listeners:
    - {name: http, protocol: HTTP, port: 80}

# httproute.yaml —— 应用团队挂牌子 (节选权重段)
spec:
  parentRefs:
    - {name: demo-gateway, kind: Gateway}
  hostnames: ["a.example.com"]
  rules:
    - backendRefs:
        - {name: route-v1, port: 80, weight: 90}   # 90% -> v1
        - {name: route-v2, port: 80, weight: 10}   # 10% -> v2
```

## How It Works

**三层各司其职**：GatewayClass 的 `controllerName` 指向 Envoy Gateway 的控制器——Gateway 的 `Accepted: True`（被调度给 Controller）与 `Programmed`（数据面就绪）两个条件分开汇报。

Envoy Gateway 检测到 Gateway 对象后**自动拉起一个 Envoy 数据面 Deployment**（Pod 名 `envoy-default-demo-gateway-*`），把 HTTPRoute 渲染成 Envoy 配置。

你在 `test` 步骤看到的分流结果，来自这条"CR → xDS → Envoy"链路——与 lab 13 的 Istio 同构，只是治理范围是入口而非服务间。

**kind 上的 Programmed=False**：Envoy 数据面用 LoadBalancer Service 暴露，kind 没有 LB 控制器、EXTERNAL-IP 永远 `<pending>`，于是 Gateway 的 Programmed 条件为 False。

但数据面实际已在正常服务（脚本改用集群内 Service DNS 直连验证）。生产集群装了 MetalLB/云 LB 时该条件为 True。

**权重分流的实现层**：`backendRefs` 的 weight 不是"精确每 10 个切一次"，而是 Envoy 加权轮询的统计行为。

20 次请求出现 16/4 或 20/0 都在正态波动内，验证精确比例请加大样本（与 lab 13 的金丝雀同款注意事项）。

## Pitfalls & Q&A

踩坑清单：

- `gatewayClassName` 写错（或没先建 GatewayClass）：Gateway 停在 Accepted=False，Controller 根本不认领——对照 `kubectl get gatewayclass` 里 CONTROLLER 列。
- 数据面 Pod 在 **envoy-gateway-system** 命名空间，不在业务 ns；label 是 `gateway.envoyproxy.io/owning-gateway-name=<gateway名>`。
- Envoy 数据面监听 **10080**（非 80）；宿主机 port-forward 转发目标写 8080 会一直空响应——或者干脆像本实验一样用集群内 curl Pod 直连 Service DNS，绕开宿主机网络。

**Q1: 已有 Ingress 的集群要迁移吗？**
不必激进，两者可共存——各占各的 80 端口由 Controller 层面协调，或分阶段切流量。

存量 Ingress 用官方工具 ingress2gateway 转换成 HTTPRoute，迁到仍在维护的 Controller（如 NGINX Gateway Fabric）——ingress-nginx 已于 2026 年 3 月退役，不应继续作为长期方案。

判断信号：当你开始大量使用注解实现灰度/超时/重写时，就是该看 Gateway API 的时刻。

**Q2: HTTPRoute 能跨命名空间引用后端吗？**
能，但需要后端方显式授权：后端 namespace 里建一个 ReferenceGrant，声明"允许来自某 namespace 的 HTTPRoute 引用我"。

这是 Gateway API"角色化"设计的体现——跨团队引用必须双向声明，防止路由规则悄悄指向别人的服务。

**Q3: 和 lab 13 的金丝雀怎么分工？**
入口灰度（南北向）用 HTTPRoute 的 weight 就够了——本实验 90/10 与 lab 13 的 VirtualService 权重是同一个思想在不同层的实现，服务间灰度（东西向）才需要 mesh。

选型顺序：先 Gateway API，治理需求超出七层入口（重试/熔断/mTLS）再上 mesh。
