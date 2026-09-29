# 13 · Service Mesh：Istio 与金丝雀发布

> kube-proxy（每个节点上把 Service 虚拟 IP 转发到 Pod 的组件）的负载均衡只会无差别轮询所有 Ready 的 Pod，你无法说"新版本只放 10% 的流量进来"。Service Mesh 用 Sidecar 接管每个 Pod 的进出流量，把灰度、重试、熔断、mTLS 这些流量治理能力从业务代码剥离到基础设施层——业务进程对此完全无感。读完本篇，你将跑通 Istio 的 90/10 精确灰度，并理解控制面/数据面的分工。

## Background

微服务的流量治理需求成串出现：新版本先接 1%~10% 的真实流量观察（灰度发布）；把生产流量复制一份打到新版本、响应丢弃（流量镜像）；调用失败自动重试、下游故障快速失败（重试/超时/熔断）；服务间通信自动加密（mTLS）。

在 Service Mesh 出现之前，这些能力要么塞进业务代码（SDK，如 Spring Cloud 的熔断器），要么靠部署多套 Service 做粗粒度切分——每个语言、每个服务都要重复集成一次。

Sidecar 模式给出了第三条路：给每个 Pod 注入一个代理容器（envoy），接管该 Pod 的全部进出流量，治理逻辑统一在代理层实现。业务代码对治理一无所知，也不需要知道——这就是"无侵入"。

## What

Istio 是典型的两层架构：

```
控制面：istiod（单进程）
  - watch K8s API（Pod/Service/Endpoint + VirtualService 等自定义资源）
  - 把路由规则编译成 envoy 配置，通过 xDS（配置下发协议）推送到每个 sidecar

数据面：envoy sidecar（每个 Pod 一个）
  - 用 iptables 劫持 Pod 的全部进出流量
  - 按收到的配置做路由、负载均衡、重试、mTLS、遥测上报
```

一句话心智模型：**流量治理做成基础设施**——业务容器完全不知道 envoy 的存在（"无侵入"），istiod 挂了只影响**规则更新**，已下发的配置仍在 sidecar 本地生效，数据面不会断。

金丝雀的"名词—动词"体系由三个对象构成：

| 资源 | 职责 | 类比 |
|------|------|------|
| Service | 服务名 → Pod 集合（收敛地址） | "这本书在哪个书架" |
| DestinationRule | 定义目的地策略，核心是 **subset**（按标签筛选 Pod 子集） | "书架分成三格" |
| VirtualService | 定义路由规则（权重/匹配条件），引用 subset 分流 | "怎么按比例从各格取书" |

`subset` 依据 Pod 的 `version` 标签划分子集（`v1` subset = 所有 `version=v1` 的 Pod），VirtualService 再按 weight 在 subset 之间分流。

但和图书馆取书不同的是，书架（Service）自己不会按比例取书——分流规则必须由 VirtualService 显式声明，且它只认 subset 与权重，不感知 Pod 的其他差异。

## When to Use

典型场景：新版本只放 10% 真实流量、指标正常再逐步放量（金丝雀发布）；内部员工先用新版本（header 匹配白名单）；新版本风险高，先镜像流量验证（响应丢弃零风险）；几十个微服务要统一上 mTLS。

何时不用：三五个服务的简单系统（K8s 原生 + Ingress canary 注解够用，mesh 的每 Pod 代理资源开销和运维复杂度是实打实的税）；强性能敏感且无治理需求的内部服务。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| Ingress canary 注解 | 只管入口切流 | 简单灰度（lab 11） |
| Service Mesh（Istio） | 全链路治理 + mTLS | 服务多、治理需求密 |
| Argo Rollouts / Flagger | 发布流程自动化 | 在 mesh 或 ingress 之上做自动渐进发布（lab 28） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；国内网络需预载 Istio 镜像（见 Pitfalls & Q&A 的 Q3）。

```bash
cd labs/13_service_mesh
./istio.sh install   # 安装 istio（demo profile）+ istioctl
./istio.sh deploy    # 部署 v1/v2 + DestinationRule + VirtualService（90/10）
./istio.sh test      # 20 次请求统计 v1/v2 命中数，直观看到分流效果
./istio.sh clean
```

成功判据与诚实预期：`test` 步骤 20 次请求的 v1/v2 命中数大致呈 9:1——但 20 次是小样本，围绕 18/2 波动、偶发 20/0 或 15/5 属正常；要验证精确比例请加大请求次数或多跑几轮（实际输出以运行为准）。

关键字段（`manifests/service_mesh.yaml`）：

```yaml
# Namespace: 一行标签开启自动注入
metadata:
  labels:
    istio-injection: enabled        # webhook 据此改写新建的 Pod

# Deployment: version 标签是 subset 划分的依据
metadata:
  labels:
    app: canary-web                 # Service 选择器认领
    version: v1                     # DestinationRule subset 按此匹配

# DestinationRule: 把服务切成子集
subsets:
  - name: v1
    labels: { version: v1 }         # 匹配 version=v1 的 Pod
  - name: v2
    labels: { version: v2 }

# VirtualService: 权重分流（金丝雀核心）
http:
  - route:
      - destination: { host: canary-web, subset: v1 }
        weight: 90                  # 90% -> 稳定版
      - destination: { host: canary-web, subset: v2 }
        weight: 10                  # 10% -> 金丝雀版
```

最小闭环只有三步：Namespace 打注入标签、Deployment 打 version 标签、VirtualService 写权重——就能实现 K8s 原生做不到的 90/10 精确灰度。镜像和 header 路由的写法以注释形式留在 YAML 里，改几行即可切换策略。


## How It Works

**Sidecar 注入原理**：Namespace 打上 `istio-injection=enabled` 标签后，

Istio 预先注册的 **MutatingWebhookConfiguration**（准入改写钩子）会对该命名空间内所有新建 Pod 做"改写"：在 Pod spec 里追加一个 `istio-proxy` 容器（envoy）和 init 容器（配置 iptables 规则）。

注入只发生在 **Pod 创建时**——对已运行的 Pod 打标签不会注入，需要重建（`kubectl rollout restart`）。数据面拦截靠 iptables 把进出流量重定向到 envoy 的 15001 等端口。

验证方法：`kubectl get pods` 后每个 Pod 都是 `2/2` 容器，jsonpath 打印容器名是 `web,istio-proxy`。

**三种灰度策略，风险递减**：

| 策略 | 用户是否受影响 | 适用场景 |
|------|----------------|----------|
| **权重路由**（90/10） | 10% 用户的请求打到 v2，看到新版本 | 有信心的新版本，靠监控快速判断 |
| **header 匹配**（x-canary: true → v2） | 只有带特定头的请求进 v2，外部用户全走 v1 | 内部员工白名单先行体验 |
| **镜像**（mirror → v2） | 全部用户仍收到 v1 响应，v2 只接收流量副本、响应被丢弃 | 新版本风险高，只想验证真实负载下的行为 |

金丝雀发布的标准节奏：镜像 → header 白名单 → 1% → 10% → 50% → 100%，每一步观察错误率/延迟指标，异常则改权重秒级回切。

回切的底气来自**改权重不用重启 Pod**：istiod watch 到 VirtualService 变化 → xDS 推送 → sidecar 即刻生效——你在 `test` 步骤改完权重再跑一次，命中比例立刻变化。

## Pitfalls & Q&A

踩坑清单：

- **Service 不区分版本**：selector 只写 `app`，把 v1/v2 都收进来；分流的活交给 VirtualService。如果 Service 按 `app+version` 选择，权重路由就失效了。
- **流量劫持可能干扰某些应用**：所有 TCP 流量都被 iptables 重定向到 envoy，对协议有特殊假设的程序（如需要拿到真实源 IP）需要额外配置。
- 注入只对**新建** Pod 生效，存量 Pod 要 `rollout restart` 才有 sidecar。

**Q3: 国内网络拉不动 Istio 镜像怎么办？**
Istio 本体和 sidecar 都以容器镜像交付，而 kind 节点内 containerd 无法直连 docker.io，必须先在宿主机拉取再导入（参见 `../../scripts/load_images.sh` 的通用流程）：

```bash
ISTIO_VERSION=1.23.0
# 1. 宿主机从镜像源拉取（daocloud 加速）
docker pull docker.m.daocloud.io/istio/pilot:${ISTIO_VERSION}
docker pull docker.m.daocloud.io/istio/proxyv2:${ISTIO_VERSION}
# 2. 重打标签为 docker.io 原名（istiod 的 Pod spec 引用的是原名）
docker tag  docker.m.daocloud.io/istio/pilot:${ISTIO_VERSION}   docker.io/istio/pilot:${ISTIO_VERSION}
docker tag  docker.m.daocloud.io/istio/proxyv2:${ISTIO_VERSION} docker.io/istio/proxyv2:${ISTIO_VERSION}
# 3. 导入所有 kind 节点（sidecar 镜像每个节点都要有！）
../../scripts/load_images.sh istio/pilot:${ISTIO_VERSION} istio/proxyv2:${ISTIO_VERSION}
```

- `pilot` = istiod 控制面镜像（demo profile 下 1 个副本）
- `proxyv2` = envoy sidecar 镜像（**每个业务节点**都需要，因为 Pod 调度到哪、sidecar 就在哪拉镜像）
- `istioctl` 本体从 github release 下载，国内直连易超时——macOS 用 `brew install istioctl` 成功率更高；脚本里两条途径都做了，若都失败，**清单与文档仍可作为学习材料**，换个网络环境再实操

**Q1: Istio 和 K8s Service / Ingress 是什么关系？**

Service 依然存在，但它退化成"名字 → Pod 集合"的服务发现载体，负载均衡被 sidecar 接管（kube-proxy 被"架空"但不必删除）；Ingress 只治理南北向（边缘）流量，mesh 治理东西向（服务间）流量，二者可共存。

Istio 也提供自己的 Ingress Gateway 替代 Ingress（见 lab 11）。

**Q2: 什么时候值得上 Service Mesh，什么时候不必？**

判断标准是流量治理需求的密度：服务间调用关系复杂、灰度/熔断/mTLS 需求成规模出现，mesh 的统一基础设施才值回票价；服务少、灰度用 Ingress canary 就能覆盖时，先别上——每 Pod 一个 sidecar 的资源开销和 mesh 自身的运维复杂度是实打实的税。

进阶方向：结合指标观测的自动化渐进式发布（Argo Rollouts / Flagger，见 lab 28）。
