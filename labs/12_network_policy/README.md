# 12 · NetworkPolicy：默认拒绝与白名单隔离

> Service 解决的是"找到并负载均衡"，但默认情况下 Kubernetes 集群里**任何 Pod 都能访问任何 Pod**——数据库能被任意命名空间里跑偏的脚本连上，一个被攻破的 Pod 可以横向扫遍整个集群。NetworkPolicy 在 IP/端口层声明"谁能访问谁"，是零信任（Zero Trust）"默认不信任，按需放行"的落地。

## What

NetworkPolicy 是命名空间级的 L3/L4 隔离规则，由 **podSelector（选中受影响的 Pod）+ 分方向规则（ingress 的 from/ports、egress 的 to/ports）**构成。一句话心智模型：**先"选中"再"加规则"**——`podSelector: {}` 选中命名空间内所有 Pod，ingress 描述"允许什么来源进来"，egress 描述"允许去哪些目标"。

判定规则三条主线：**某方向没有任何策略选中某 Pod → 该方向全放行；一旦有至少一条策略选中 → 该方向只放行规则匹配的流量、其余全拒绝；多条策略之间是叠加（并集），没有优先级、也没有 deny 规则**。

`policyTypes` 决定管哪个方向：`[Ingress]` 只限入站、`[Ingress, Egress]` 双向都限；不写时默认 `["Ingress"]`（写了 egress 规则则自动加 Egress）。

## Why

微服务架构下的零信任要求"默认不信任，按需放行"：backend 应该只接受 frontend 的流量，"恶意" Pod 应该连不上任何东西。没有 NetworkPolicy，一个被攻破的 Pod 可以横向扫遍整个集群，安全边界只剩命名空间的名字——而网络层默认连命名空间都不隔离，跨命名空间的 Pod 可以直接互访。

一个前提要先钉死：**NetworkPolicy 只是声明，执行者是 CNI 插件**。API server 只做格式校验，真正在节点上编程 iptables/eBPF 的是 Calico、Cilium 这类 CNI。

## How

```bash
cd labs/12_network_policy
./network_policy.sh          # CNI 检查 / deploy / test / isolate / verify / clean
# YAML 里用 tier 标签分组，可分阶段演示"隔离前 vs 隔离后"：
kubectl apply -f manifests/network_policy.yaml -l tier=workload   # 先只部署应用
kubectl apply -f manifests/network_policy.yaml -l tier=policy     # 再上隔离策略
```

`from` 的三种来源选择器（列表项之间 **OR**，同一列表项内多个选择器是 **AND**）：

```yaml
ingress:
  - from:
      - podSelector:                  # ① 同命名空间内按标签选 Pod
          matchLabels: {app: frontend}
      - namespaceSelector:            # ② 按标签选整个命名空间(所有 Pod)
          matchLabels: {ns: demo-netpol}
      - namespaceSelector:            # ②+① 组合 = "某命名空间里的某些 Pod" (同一列表项内是 AND)
          matchLabels: {kubernetes.io/metadata.name: kube-system}
        podSelector:
          matchLabels: {k8s-app: kube-dns}
      - ipBlock:                      # ③ CIDR 网段, 常用于放行集群外/节点地址
          cidr: 10.244.0.0/16
          except: [10.244.1.0/24]     # 排除例外段
```

典型策略（`manifests/network_policy.yaml`）：

```yaml
spec:
  podSelector:                # 策略作用于哪些 Pod (受影响方)
    matchLabels:
      app: backend
  policyTypes: ["Ingress"]    # 管哪个方向; 不列的方向不受限
  ingress:
    - from:                   # 一个列表项 = 一条规则 (多条规则之间 OR)
        - podSelector:
            matchLabels:
              app: frontend   # 只放行同命名空间 app=frontend 的 Pod
      ports:
        - protocol: TCP
          port: 80            # 注意: 指的是 Pod 的端口(targetPort), 不是 Service 端口
```

## Deep Dive

**默认拒绝（default-deny）模式**：零信任的第一步不是"写放行规则"，而是先**全网拒绝**再按需打洞——选中所有 Pod、只声明方向、不写规则字段，该方向即全拒绝：

```yaml
spec:
  podSelector: {}        # 选中所有 Pod
  policyTypes: [Ingress] # 只声明方向, 不写 ingress 字段 => 入站全拒绝
```

之后再叠加白名单策略（如 allow-frontend-to-backend）逐个放行。Egress 方向同理。这是生产上管理"东西向流量"的标准套路。

**DNS 放行的坑（出站隔离的头号事故）**：一旦启用 Egress 默认拒绝，Pod 连 kube-dns 的 53 端口也被拦，`wget http://backend` 会先卡在域名解析上——**所有服务名瞬间不可达，且报错看起来像"网络不通"而非"DNS 被拦"**。必须显式放行：

```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels: {kubernetes.io/metadata.name: kube-system}
        podSelector:
          matchLabels: {k8s-app: kube-dns}
    ports:
      - {protocol: UDP, port: 53}    # DNS 主要走 UDP
      - {protocol: TCP, port: 53}    # 大响应/TCP 回退也要放
```

本文 YAML 里这段作为可选示例注释保留，三个 Egress 策略（deny-all + allow-dns + allow-to-backend）必须一起启用，缺一个就会"莫名其妙"断网。

**kind/kindnet 不生效问题与 Calico 方案**：kind 默认的 CNI 是 kindnet，**不支持 NetworkPolicy**——`kubectl apply` 能成功（API server 只做 schema 校验），`kubectl get networkpolicy` 也能看到对象，但节点上不会有任何 iptables 规则，隔离完全不存在，脚本里 evil Pod 的 wget 照样通。`network_policy.sh` 启动时会自动检测 CNI 并给出警告。想真实体验隔离，给 kind 换 Calico（核心是**镜像要预先 load 进节点**，否则 calico-node 起不来）：

```bash
# 1) 拉取并导出镜像 (国内建议配置 docker.io/calico/* 的镜像加速)
docker pull calico/node:v3.28.0
docker pull calico/cni:v3.28.0
docker pull calico/pod2daemon-flexvol:v3.28.0
docker save calico/node calico/cni calico/pod2daemon-flexvol -o calico.tar
# 2) 加载进 kind 节点
kind load image-archive calico.tar --name <kind集群名>
# 3) 安装并等待就绪 (可顺手删除 kindnet DaemonSet)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
kubectl -n kube-system rollout status ds/calico-node
```

踩坑清单：

- **podSelector 选的是"受策略影响的 Pod"**，不是"允许访问的来源"——来源在 `ingress.from` 里写，初学者最容易搞反
- `ports.port` 是 **Pod/容器端口**；即使通过 Service 访问，策略匹配的也是最终落到后端 Pod 的 targetPort
- NetworkPolicy 是**命名空间级别**的对象，`from.podSelector` 只在**同命名空间**内选；跨命名空间必须配合 `namespaceSelector`
- K8s 原生没有"黑名单"（deny 规则），要黑名单得用 CNI 扩展策略，如 Calico 的 `GlobalNetworkPolicy`（projectcalico.org/v3，支持集群级策略与 deny 规则），或 Cilium 的 `CiliumNetworkPolicy`（基于 eBPF，支持 L3-L7 规则）

## Q&A

**Q1: 命名空间之间默认隔离吗？**
网络层默认**不隔离**——跨命名空间的 Pod 可以直接互访（除非 CNI 有额外配置）。要隔离需用 namespaceSelector 声明；反过来，跨命名空间放行时 `from` 里也必须写 namespaceSelector，因为 NetworkPolicy 对象本身只作用于自己所在的命名空间。

**Q2: NetworkPolicy 与 RBAC 是什么关系？**
完全不同层的东西：RBAC 管 **Kubernetes API 的访问控制**（谁能 kubectl get/watch/edit 什么资源，见 lab 19），主体是用户/ServiceAccount；NetworkPolicy 管 **Pod 之间的网络流量**（L3/L4，谁能连谁的哪个端口），主体是 Pod/IP。RBAC 挡不住 Pod 之间的 TCP 连接，NetworkPolicy 也挡不住某人调 API——两者是互补的安全层，不是替代。
