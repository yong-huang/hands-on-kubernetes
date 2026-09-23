# 13 · Service Mesh：Istio 与金丝雀发布

> kube-proxy 的负载均衡只会无差别轮询所有 Ready 的 Pod，你无法说"新版本只放 10% 的流量进来"。Service Mesh 用 Sidecar 接管每个 Pod 的进出流量，把灰度、重试、熔断、mTLS 这些流量治理能力从业务代码剥离到基础设施层——业务进程对此完全无感。

## What

Istio 是典型的两层架构：

```
控制面：istiod（单进程）
  - watch K8s API（Pod/Service/Endpoint + VirtualService 等自定义资源）
  - 把路由规则编译成 envoy 配置，通过 xDS 推送到每个 sidecar

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

## Why

微服务一多，流量治理需求成串冒出来：**灰度发布**——新版本先接 1%~10% 的真实流量，观察指标后再逐步放量；**流量镜像**——把生产流量复制一份打到新版本，响应丢弃，零风险验证；**重试 / 超时 / 熔断**——调用失败自动重试，下游故障快速失败；**mTLS 加密**——服务间通信自动加密，不用改一行业务代码。

在 Service Mesh 出现之前，这些能力要么塞进业务代码（SDK，如 Spring Cloud），要么靠部署多套 Service 做粗粒度切分——K8s 原生的滚动更新做不到"按比例切流"。Sidecar 模式给出了第三条路：治理能力下沉、全语言通用、业务零改动。代价也要认清：每 Pod 多一个代理（资源 + 一跳延迟）和更高的运维复杂度，小团队用 K8s 原生能力往往够了。

## How

```bash
cd labs/13_service_mesh
./istio.sh install   # 安装 istio（demo profile）+ istioctl
./istio.sh deploy    # 部署 v1/v2 + DestinationRule + VirtualService（90/10）
./istio.sh test      # 20 次请求统计 v1/v2 命中数，直观看到分流效果
./istio.sh clean
```

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

**国内网络注意（镜像预载清单）**：Istio 本体和 sidecar 都以容器镜像交付，而 kind 节点内 containerd 无法直连 docker.io，必须先在宿主机拉取再导入（参见 `../../scripts/load_images.sh` 的通用流程）：

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

## Deep Dive

**Sidecar 注入原理**：Namespace 打上 `istio-injection=enabled` 标签后，Istio 预先注册的 **MutatingWebhookConfiguration** 会对该命名空间内所有新建 Pod 做"改写"：在 Pod spec 里追加一个 `istio-proxy` 容器（envoy）和 init 容器（配置 iptables 规则）。注入只发生在 **Pod 创建时**——对已运行的 Pod 打标签不会注入，需要重建（`kubectl rollout restart`）。数据面拦截靠 iptables 把进出流量重定向到 envoy 的 15001 等端口。

验证方法：`kubectl get pods` 后每个 Pod 都是 `2/2` 容器，jsonpath 打印容器名是 `web,istio-proxy`。

**三种灰度策略，风险递减**：

| 策略 | 用户是否受影响 | 适用场景 |
|------|----------------|----------|
| **权重路由**（90/10） | 10% 用户的请求打到 v2，看到新版本 | 有信心的新版本，靠监控快速判断 |
| **header 匹配**（x-canary: true → v2） | 只有带特定头的请求进 v2，外部用户全走 v1 | 内部员工白名单先行体验 |
| **镜像**（mirror → v2） | 全部用户仍收到 v1 响应，v2 只接收流量副本、响应被丢弃 | 新版本风险高，只想验证真实负载下的行为 |

金丝雀发布的标准节奏：镜像 → header 白名单 → 1% → 10% → 50% → 100%，每一步观察错误率/延迟指标，异常则改权重秒级回切。回切的底气来自**改权重不用重启 Pod**：istiod watch 到 VirtualService 变化 → xDS 推送 → sidecar 即刻生效。

踩坑清单：

- **Service 不区分版本**：selector 只写 `app`，把 v1/v2 都收进来；分流的活交给 VirtualService。如果 Service 按 `app+version` 选择，权重路由就失效了
- **流量劫持可能干扰某些应用**：所有 TCP 流量都被 iptables 重定向到 envoy，对协议有特殊假设的程序（如需要拿到真实源 IP）需要额外配置
- 注入只对**新建** Pod 生效，存量 Pod 要 `rollout restart` 才有 sidecar

## Q&A

**Q1: Istio 和 K8s Service / Ingress 是什么关系？**
Service 依然存在，但它退化成"名字 → Pod 集合"的服务发现载体，负载均衡被 sidecar 接管（kube-proxy 被"架空"但不必删除）；Ingress 只治理南北向（边缘）流量，mesh 治理东西向（服务间）流量，二者可共存。Istio 也提供自己的 Ingress Gateway 替代 Ingress（见 lab 11）。

**Q2: 什么时候值得上 Service Mesh，什么时候不必？**
判断标准是流量治理需求的密度：服务间调用关系复杂、灰度/熔断/mTLS 需求成规模出现，mesh 的统一基础设施才值回票价；三五个服务、灰度用 K8s 原生 + Ingress canary 注解（见 lab 11）就能覆盖时，先别上——每 Pod 一个 sidecar 的资源开销和 mesh 自身的运维复杂度是实打实的税。进阶方向：结合指标观测的自动化渐进式发布（Argo Rollouts / Flagger，见 lab 28）。
