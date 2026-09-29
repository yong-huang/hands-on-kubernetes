# 14 · DNS 与服务发现：ClusterIP、Headless 与 Pod 级域名

> 集群里有 3 个 nginx Pod，客户端该连哪个 IP？答案是"一个都别连"。Pod IP 是易变的（重建、漂移、扩缩容都会变），把 IP 写死等于把脆弱性写进代码。Kubernetes 的解法是**用 DNS 做服务发现**：每个 Service 创建时，CoreDNS 自动为它生成一条域名记录，客户端只需要记名字。读完本篇，你将搞懂三种 DNS 记录的差异，并弄明白 ndots:5 为什么拖慢外部域名解析。

## Background

在 Kubernetes 之外，服务发现的常见做法是引入注册中心（ZooKeeper / Eureka / Consul）：服务启动时注册自己的地址，调用方查询后缓存，还要处理心跳与摘除。这套机制能用，但每个语言都要接一次 SDK，客户端多一份依赖。

Kubernetes 的做法更省：DNS 是所有语言、所有框架都内置的解析机制——`getaddrinfo("web")` 就完成了一次服务发现，客户端零依赖、零改造。

Kubernetes 只是把"名字 → 地址"的映射做成了声明式 API 的副产品：Service 对象的生灭就是 DNS 记录的生灭，没有额外的注册与心跳逻辑。

## What

K8s 服务发现的本质是"声明式 API 的 DNS 副产品"：创建 Service 即自动获得 `<service>.<namespace>.svc.cluster.local`。

一句话心智模型：**名字 → 地址的映射，由 CoreDNS（集群内置 DNS 服务器）根据 API Server 里的对象自动维护**——但和手工维护的 hosts 文件不同的是，这条映射的增删改查全部由控制器驱动，永远和集群实际状态一致。

三种 DNS 记录：

| 记录类型 | 触发条件 | nslookup 返回 |
|----------|----------|---------------|
| Service（ClusterIP） | 任何普通 Service | 单个虚拟 IP（VIP） |
| Headless Service | `clusterIP: None` | 所有就绪 Pod 的真实 IP 列表 |
| Pod 级 | hostname + subdomain，或 StatefulSet + serviceName | 单个 Pod 的 IP |

## When to Use

典型场景：服务间按名字互调（`http://order`，短名同命名空间直接解析）；客户端需要拿到全部实例 IP 自己做负载均衡（Headless）；按名直连特定实例（StatefulSet 的 `web-0.web-h`）。

何时不用：需要健康检查驱动的高级路由策略（DNS 缓存让摘除不即时，那是 Service/(mesh) 的职责）；集群外调用方解析集群内名字（DNS 只在集群网络内可见，对外用 Ingress/网关）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 硬编码 Pod IP | 重建即失效 | 不要用 |
| K8s DNS | 声明式副产品，零客户端依赖 | 集群内服务发现（默认） |
| 注册中心（Nacos 等） | 元数据更丰富、支持优雅摘除 | 混合云/非 K8s 环境的复杂发现 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/14_dns_discovery
./dns.sh deploy   # 部署 Headless Service + StatefulSet + ClusterIP Service + 自定义 DNS Pod
./dns.sh test     # 五组 nslookup 实测三种记录
./dns.sh clean
```

`./dns.sh test` 的关键输出（IP 以实际集群为准）：

```
# a) 普通 Service：一个 VIP
nslookup web        ->  Address: 10.96.0.35

# b) Headless：全部 Pod IP
nslookup web-h      ->  Address: 10.244.1.5
                        Address: 10.244.2.8

# c) Pod 级：单个 Pod IP
nslookup web-0.web-h ->  Address: 10.244.1.5
nslookup web-1.web-h ->  Address: 10.244.2.8

# e) DNS 服务本身也是被 DNS 发现的
nslookup kube-dns.kube-system.svc.cluster.local -> 10.96.0.10
```

关键字段（`manifests/dns_discovery.yaml`）：

```yaml
# Headless Service：DNS 直接返回 Pod IP，无 VIP、无 kube-proxy 规则
spec:
  clusterIP: None

# StatefulSet：Pod 名有序稳定，serviceName 指向 Headless 后自动生成 Pod 记录
spec:
  serviceName: web-h        # web-0.web-h.default.svc.cluster.local
  replicas: 2

# 普通 Pod 想要自己的 DNS 记录，两个条件缺一不可
spec:
  hostname: myhost          # 条件 1：主机名
  subdomain: web-h          # 条件 2：必须指向一个已存在的 Headless Service
  dnsPolicy: ClusterFirst
  dnsConfig:                # 追加注入 resolv.conf
    nameservers: [8.8.8.8]
    searches: [default.svc.cluster.local]
    options:
      - { name: ndots, value: "2" }
```

## How It Works

**CoreDNS 与插件链**：CoreDNS 是集群的 DNS 服务器，以 Deployment 跑在 kube-system 里，通过名为 `kube-dns` 的 Service 暴露（通常 10.96.0.10）。

它的行为由 Corefile（存放在 ConfigMap——K8s 存配置数据的对象——里的 DNS 配置文件）驱动，采用**插件链**架构（一个请求依次流过的处理单元）：

```
.:53 {
    errors
    kubernetes cluster.local in-addr.arpa {   # 核心：监听 Service/Endpoint 变化生成记录
        pods insecure
    }
    forward . 8.8.8.8                         # 集群内查不到 → 转发外部 DNS
    hosts { ... }                             # 自定义 hosts 记录
    cache 30                                  # 缓存
}
```

请求进来后依次经过插件：`kubernetes` 插件管 `cluster.local` 后缀，`forward` 插件兜底外部域名。

**search domains 与 ndots**：每个 Pod 的 `/etc/resolv.conf` 大致如下：

```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

解析短名 `web` 时，glibc（Linux 标准C库的解析器）按 ndots 规则决定是否拼接搜索域：**名字中的点数 < ndots(5) 就先用搜索域逐个补全再查**，最后才把原始名当绝对域名。

所以 `web` 会按 `web.default.svc.cluster.local`（命中）→ `web.svc.cluster.local` → `web.cluster.local` → `web` 的顺序尝试。

完整解析路径：应用 getaddrinfo → **ndots:5 先拼搜索域** → CoreDNS 插件链（`kubernetes` 插件管 cluster.local，命中返回记录）→ 应答建连；

`cluster.local` 之外的域名才走 `forward` 插件兜底到外部 DNS——这正是 ndots:5 拖慢外部域名解析的根源。

**dnsPolicy 与 dnsConfig**：`dnsPolicy: ClusterFirst`（默认）——resolv.conf 指向 CoreDNS，外部域名由 CoreDNS forward 出去；

`dnsPolicy: None`——完全忽略集群 DNS，必须配合 `dnsConfig` 自定义 nameservers；`dnsConfig` 无论哪种 policy 都可追加 nameservers / searches / options（如把 ndots 调低）。

## Pitfalls & Q&A

踩坑清单：

- **subdomain 必须真实存在**：它要对应一个 Headless Service，否则 Pod 记录不生成。
- StatefulSet 的 Pod 记录只在 Pod Running 时存在，且（默认 `publishNotReadyAddresses: false`）只包含 Ready 的 Pod。
- `dnsPolicy: None` 而不写 dnsConfig 是非法配置，Pod 起不来。

**Q1: ndots:5 拖慢外部域名解析，怎么优化？**

外部域名如 `api.github.com` 只有 2 个点 < 5，解析器会先把它拼上 3 个搜索域各查一遍（全部返回 NXDOMAIN，即"该域名不存在"的应答），最后才查绝对域名——一次本可直接命中的解析变成了 4 次查询。

高频外部调用的优化手段：用 `dnsConfig` 调低 ndots、代码里写全 FQDN（全限定域名）、或结尾加点（`api.github.com.`）表示绝对域名。

**Q2: Headless Service 的典型使用场景？**

① 有状态集群的节点间互相发现（MySQL 主从、Cassandra、Kafka broker 用 `<pod>.<headless-svc>` 找到固定对端）；

② 客户端自己做负载均衡（gRPC 长连接会粘住 VIP 后的单个 Pod，Headless 让客户端拿到全量 IP 列表自选）；③ Service Mesh 中 sidecar 直连（见 lab 13）。

**Q3: CoreDNS 和 kube-dns 是什么关系？**
CoreDNS 是 CNCF 毕业项目，自 1.13 起取代 kube-dns 成为默认 DNS 服务器；但暴露它的 Service 名仍叫 `kube-dns`（兼容存量配置）——名字是历史的，实现是新的，排查 DNS 问题时别被这对名字迷惑。
