# 04 · Service：稳定的服务入口与负载均衡

> Pod IP 随重建而变。Service 用「VIP + DNS 名 + label selector」给一组易变的 Pod 提供稳定入口——这是 K8s 服务发现与负载均衡的基石。

## 1. 为什么需要 Service

Pod 是脆弱的：可能被驱逐、被 OOM Kill、被滚动更新替换——每次重建都拿到**新的 Pod IP**。如果调用方直接硬编码 Pod IP：

- **Pod IP 易变**：滚动更新一次，所有调用方的配置全部失效
- **一组 Pod 需要负载均衡**：Deployment 扩到 3 个副本，谁来把流量均匀分给它们？
- **服务发现**：调用方如何知道"现在有哪些健康的 Pod"？

Service 为解决这三个问题而生：提供**稳定的虚拟 IP（ClusterIP）+ DNS 名字**，通过 label selector 自动追踪后端 Pod。

## 2. 总览：四种类型与流量路径

![service types](images/service_types.svg)

四种类型不是并列关系，而是**层层叠加**：LoadBalancer 在每个节点上开 NodePort，NodePort 在集群内 VIP（ClusterIP）之外加了一层节点端口；Headless 则是反例——`clusterIP: None`，连 VIP 都不要，DNS 直接返回 Pod IP 列表。

一句话心智模型：**Service = 稳定入口（VIP + DNS）+ 动态后端（Endpoints）+ 流量分发（kube-proxy）**。入口的四种形态见图，内部机制见 §4。

## 3. 快速开始

```bash
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

## 4. 内部机制

### 4.1 selector → Endpoints：Service 怎么记住 Pod

![service mechanism](images/service_mechanism.svg)

Service 本身不直接"记住"Pod，链路是：

1. Service 的 `selector`（如 `app: nginx`）匹配 Pod 的 label；
2. **Endpoints Controller**（控制面组件）持续 watch Pod，把所有 **Ready** 的 Pod IP:targetPort 写入同名 Endpoints 对象；
3. Pod 挂掉 / 新建 → Endpoints 自动增删；
4. 每个节点的 **kube-proxy** watch Service + Endpoints，把最新后端同步成本地转发规则。

两种转发模式：**iptables**（默认）为每个 Service 生成 DNAT 规则，请求路径上没有 proxy 进程、性能好，但规则线性匹配，数千条 Service 时更新和匹配都变慢；**ipvs** 用内核哈希表 O(1) 查找，支持多种均衡算法，大规模集群首选。

所以 `kubectl get endpoints <svc>` 是排查"Service 不通"的第一站：**Endpoints 为空 = selector 不匹配或没有 Ready 的 Pod**。

### 4.2 ClusterDNS：Service 名怎么变成 IP

![service dns](images/service_dns.svg)

创建 Service 时，CoreDNS 自动注册一条记录，集群内任何 Pod 都可以直接用短名访问：

```
<service-name>.<namespace>.svc.cluster.local
```

普通 Service 解析返回**一条 A 记录（VIP）**；Headless 没有可解析的 IP，CoreDNS 改为返回**所有 Ready Pod 的 A 记录列表**——客户端拿到真实 Pod IP，自己做负载均衡。StatefulSet 的每个 Pod 还有独立域名：`<pod-ordinal>.<svc>.<ns>.svc.cluster.local`。

## 5. 三个端口：port / targetPort / nodePort

最容易混淆的三个端口（对照 §2 图中的箭头标注看）：

```yaml
ports:
  - port: 80          # Service 的端口 —— 集群内访问 nginx-svc:80 用的是它
    targetPort: 8080  # 容器（Pod）真正监听的端口 —— 转发的终点
    nodePort: 30080   # 节点上对外暴露的端口（仅 NodePort/LoadBalancer 有意义）
```

记忆方法：**port 是"门牌号"（对外），targetPort 是"房间号"（对内），nodePort 是"大楼侧门"（对集群外）**。targetPort 还可以填容器声明的端口名（如 `name: http`），改容器端口时无需改 Service。

## 6. 文件结构

```
04_service/
├── README.md               # 本文档
├── service.sh              # 一键部署、验证访问、DNS 发现、Endpoints 检查、清理
├── manifests/
│   └── service.yaml        # Deployment + 4 种 Service（ClusterIP/NodePort/LB/Headless）
└── images/
    ├── service_types.svg      # 四种类型与流量路径（本文档 §2）
    ├── service_mechanism.svg  # selector → Endpoints → kube-proxy（本文档 §4.1）
    └── service_dns.svg        # ClusterDNS 解析规则（本文档 §4.2）
```

## 7. 面试要点

**Q1：Service 如何找到 Pod？**
通过 `selector` 匹配 Pod label → Endpoints Controller 把 Ready Pod 的 IP:port 写入 Endpoints 对象 → kube-proxy 依据 Endpoints 在节点上同步转发规则。排查时先看 `kubectl get endpoints`。

**Q2：ClusterIP 是虚拟 IP，是什么意思？**
它不绑定任何网络设备，没有进程监听它。访问 VIP 的数据包在节点上被 iptables/ipvs 的 DNAT 规则直接改写为目的 Pod IP，因此 `ping ClusterIP` 不通、但 `curl ClusterIP:port` 通。

**Q3：NodePort 有什么性能问题？**
端口范围有限（默认 30000-32767）；流量经过 kube-proxy 的 NAT 多一跳；大量 NodePort 难以管理，生产上通常用 LB 或 Ingress 收敛入口；且依赖节点 IP 可达性，节点故障需客户端自行切换。

**Q4：Headless Service 什么时候用？**
① StatefulSet：每个 Pod 需要稳定独立的 DNS 名（`pod-0.svc-name`）；② 客户端自己负载均衡（gRPC 长连接，避免 VIP 层 DNAT 打破连接粘性）；③ 需要直连特定实例的场景（主从数据库、Raft 选举）。

## 8. 总结

- Service = 稳定入口（VIP + DNS）+ 动态后端（Endpoints）+ 流量分发（kube-proxy）
- 类型层层叠加：ClusterIP ⊂ NodePort ⊂ LoadBalancer；Headless 是"无入口"的反例
- 三个端口各司其职：port 对外、targetPort 对内、nodePort 对节点外
- 排查链路：`kubectl get svc` → `kubectl get endpoints` → `kubectl describe endpoints` → Pod 内 curl

下一节：05 ConfigMap & Secret——把配置和敏感信息从镜像里解耦出来。
