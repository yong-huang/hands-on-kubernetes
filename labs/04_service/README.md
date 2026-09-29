# 04 · Service：稳定的服务入口与负载均衡

> Pod IP 随重建而变。Service 用「VIP + DNS 名 + label selector」给一组易变的 Pod 提供稳定入口——这是 K8s 服务发现与负载均衡的基石。读完本篇，你将分清四种 Service 类型和三个端口字段，并掌握"Service 不通"的第一排查动作。

## Background

有了 Deployment 之后，一组 Pod 跑起来了，但调用方连谁？在 Service 出现之前，常见的做法是把 Pod IP 写进调用方配置：滚动更新一次，所有调用方的配置全部失效；Deployment 扩到 3 个副本，还得自己搭个 nginx 做负载均衡；副本挂了，配置里那个 IP 就成了死地址。

这三件事的共性是"后端易变，入口必须稳定"。Kubernetes 的解法是 Service：它提供一个不变的虚拟 IP（VIP）和 DNS 名字，通过 label selector 自动追踪后端 Pod——后端怎么生怎么死，入口一动不动。

## What

Service = **稳定入口（VIP + DNS）+ 动态后端（Endpoints）+ 流量分发（kube-proxy）**。可以把 Service 想象成公司总机号码；但和总机不同的是，接线规则是控制器根据后端存活状态自动维护的，不需要人工更新分机表。

Endpoints 是"当前所有健康后端 Pod 的 IP:端口清单"，由控制面组件自动维护。

四种类型不是并列关系，而是**层层叠加**：

| 类型 | 入口形态 | 叠加了什么 |
|---|---|---|
| ClusterIP | 集群内 VIP + DNS 名 | 基础形态 |
| NodePort | 每个节点上开一个节点端口 | 在 ClusterIP 之外加节点端口层 |
| LoadBalancer | 外部负载均衡器 | 在 NodePort 之外再包一层 LB |
| Headless | 无 VIP（`clusterIP: None`） | 反例：连 VIP 都不要，DNS 直接返回 Pod IP 列表 |

## When to Use

典型场景：集群内服务互调（ClusterIP 是默认选择）；临时从集群外访问某个服务做调试（NodePort 或 port-forward）；客户端需要直连每个实例而非经过 VIP（Headless，如 gRPC 长连接、数据库主从寻址）。

何时不用：把 NodePort 当生产入口——端口范围有限（默认 30000-32767）、NAT 多一跳、节点故障需客户端自行切换；生产入口应收敛到 Ingress（见 lab 11）或 LB。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 硬编码 Pod IP | 无任何稳定性 | 不要用 |
| ClusterIP Service | 集群内稳定入口 | 服务间互调（默认） |
| Ingress | 七层域名/路径路由 | 对外 HTTP 入口收敛 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/04_service
./service.sh deploy    # 部署后端 Deployment + 4 种 Service
kubectl get svc        # 观察 TYPE / CLUSTER-IP / PORT(S) 四列的差异
./service.sh test      # 集群内 curl / NodePort 访问 / nslookup / endpoints 检查
./service.sh clean
```

`kubectl get svc` 预期输出（关注四行哪里不一样）：

```
NAME                 TYPE           CLUSTER-IP   PORT(S)
nginx-clusterip      ClusterIP      10.96.x.x    80/TCP
nginx-nodeport       NodePort       10.96.x.x    80:30080/TCP
nginx-loadbalancer   LoadBalancer   10.96.x.x    80:31xxx/TCP   ← EXTERNAL-IP 一直 <pending>
nginx-headless       ClusterIP      None         80/TCP         ← 没有 VIP！
```

最容易混淆的三个端口（`manifests/service.yaml`）：

```yaml
ports:
  - port: 80          # Service 的端口 —— 集群内访问 nginx-svc:80 用的是它
    targetPort: 8080  # 容器（Pod）真正监听的端口 —— 转发的终点
    nodePort: 30080   # 节点上对外暴露的端口（仅 NodePort/LoadBalancer 有意义）
```

三个端口的分工：**port 是"门牌号"（对外），targetPort 是"房间号"（对内），nodePort 是"大楼侧门"（对集群外）**——但和真实大楼不同的是，房间号（targetPort）还可以填容器声明的端口名（如 `name: http`），改容器端口时无需改 Service。

## How It Works

**selector → Endpoints → kube-proxy**：Service 本身不直接"记住"Pod，链路是：

1. Service 的 `selector`（本实验用 `app: nginx-svc`）匹配 Pod 的 label；
2. **Endpoints Controller**（控制面组件）持续 watch Pod，把所有 **Ready** 的 Pod IP:targetPort 写入同名 Endpoints 对象；
3. Pod 挂掉 / 新建 → Endpoints 自动增删；
4. 每个节点的 **kube-proxy** watch Service + Endpoints，把最新后端同步成本地转发规则。

你在 Quick Start 的 `service.sh test` 里看到的访问成功，走的就是这条链：名字解析到 VIP → 节点上的转发规则改写目的地址 → 真实 Pod。

两种转发模式：**iptables**（默认）为每个 Service 生成 DNAT 规则（改写数据包目的地址），请求路径上没有 proxy 进程、性能好，但规则线性匹配，数千条 Service 时更新和匹配都变慢；**ipvs** 用内核哈希表 O(1) 查找，支持多种均衡算法，大规模集群首选。

所以 `kubectl get endpoints <svc>` 是排查"Service 不通"的第一站：**Endpoints 为空 = selector 不匹配或没有 Ready 的 Pod**。

> 注：v1.33 起 v1 Endpoints API 已标记废弃（概念不变，对象被拆成 EndpointSlice 分片），现行查看命令是 `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`，演示脚本里两种都跑给你看。

**ClusterDNS**：创建 Service 时，CoreDNS（集群内建 DNS 服务器）自动注册一条记录，集群内任何 Pod 都可以直接用短名访问：

```
<service-name>.<namespace>.svc.cluster.local
```

普通 Service 解析返回**一条 A 记录（VIP）**；Headless 没有可解析的 IP，CoreDNS 改为返回**所有 Ready Pod 的 A 记录列表**——客户端拿到真实 Pod IP，自己做负载均衡。

StatefulSet 的每个 Pod 还有独立域名：`<pod-ordinal>.<svc>.<ns>.svc.cluster.local`。

## Pitfalls & Q&A

踩坑清单：

- **Headless 排查方向反了**：`nslookup nginx-headless` 返回多个 IP 不是异常，是设计行为。
- **ClusterIP ping 不通**：`ping ClusterIP` 不通但 `curl ClusterIP:port` 通是正常的（见 Q1），别据此判断服务坏了。
- NodePort 范围写越界（如 80）：会被 API 校验拒绝，必须在 30000-32767 内。

**Q1: ClusterIP 是"虚拟"IP，是什么意思？**

它不绑定任何网络设备，没有进程监听它。访问 VIP 的数据包在节点上被 iptables/ipvs 的 DNAT 规则直接改写为目的 Pod IP，因此 `ping ClusterIP` 不通、但 `curl ClusterIP:port` 通——这也是一条常用的快速判障经验。

**Q2: Headless Service 什么时候用？**
① StatefulSet：每个 Pod 需要稳定独立的 DNS 名（`pod-0.svc-name`）；② 客户端自己负载均衡（gRPC 长连接，避免 VIP 层 DNAT 打破连接粘性）；③ 需要直连特定实例的场景（主从数据库、Raft 选举）。
