# 10 · 亲和性与拓扑打散：让副本真正分散到节点上

> 默认调度器只看"哪个节点放得下"，不关心副本之间的拓扑分布——3 副本可能全挤在一个节点上，节点一宕机全体消失。解决思路是给调度器加"约束"：有的管**去哪个节点**，有的管**和谁在一起**，有的直接规定**各拓扑域的数量差**。读完本篇，你将掌握"过滤 vs 打分"这条调度主线，并亲眼看到 maxSkew 拒绝调度的完整过程。

## Background

把 3 个副本部署上去就算高可用了？只要某个节点资源最多、打分最高，K8s 调度器可能把 3 个副本全放上去——那个节点一宕机，服务整体消失。默认调度器的一致性目标是"放得下"，不是"分得开"：它不知道你对可用性的要求。

人工保证分散同样靠不住：手动指定 nodeName 把副本钉在不同机器，节点扩缩容后就失效了。可用性真正需要的是把拓扑意图（跨节点、跨可用区、数量均匀）声明给调度器，让它每次放置都遵守——这就是调度约束（亲和性与拓扑打散）要解决的问题。

## What

K8s 的调度约束只有两件事：**过滤（硬性）与打分（软性）**——硬性约束不满足 Pod 一直 Pending，软性偏好只影响候选排名。五类工具按作用维度分：

| 方式 | 作用维度 | 硬/软 | 典型场景 |
|------|----------|-------|----------|
| nodeSelector | 节点属性 | 只有硬性 | 简单地钉到 GPU/SSD 节点 |
| nodeAffinity | 节点属性 | 硬 + 软（weight） | 必须 SSD、优先东区机房 |
| podAffinity | Pod 之间 | 硬 + 软 | 前端和缓存同节点/同区，降低延迟 |
| podAntiAffinity | Pod 之间 | 硬 + 软 | 同应用副本跨节点/跨可用区打散 |
| topologySpreadConstraints | 拓扑域数量差 | DoNotSchedule / ScheduleAnyway | 副本数 > 节点数时的均匀打散 |

一句话心智模型：**nodeAffinity 管"去哪个节点"，pod(anti)Affinity 管"和谁在一起"，topologySpread 管"各域数量差不超过 maxSkew"**。硬性与软性只差一个后缀：

| 后缀 | 语义 | 不满足时的行为 |
|------|------|----------------|
| `requiredDuringSchedulingIgnoredDuringExecution` | 硬性约束（过滤器） | Pod 一直 **Pending**，绝不降低要求 |
| `preferredDuringSchedulingIgnoredDuringExecution` | 软性偏好（打分器） | 正常调度，只是打分时尽量避开 |

## When to Use

典型场景：3 副本 web 服务要求不同节点各一个（硬性 podAntiAffinity）；训练任务必须跑在 GPU 节点（nodeAffinity 硬性）；5 副本分散到 3 节点且尽量均匀（topologySpread + maxSkew=1）；前端和缓存就近部署降低延迟（podAffinity）。

何时不用：单副本或对可用性无要求的服务（约束只会带来 Pending 风险）；约束多到节点放不下时（硬约束叠加过多，副本将无处可去）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 默认调度 | 只看资源够不够 | 对分布无要求的场景 |
| podAntiAffinity | "每域最多 1 个" | 副本数 ≤ 节点数的强打散 |
| topologySpread | "各域数量差 ≤ maxSkew" | 副本数 > 节点数的均匀打散（新项目推荐） |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)），3 节点拓扑。

```bash
cd labs/10_affinity
./affinity.sh label          # 前置：给 worker 打 disktype/zone 标签
./affinity.sh antiaffinity   # 硬性反亲和：观察 NODE 列，副本分散到不同节点
./affinity.sh nodeaffinity   # 硬性+软性 nodeAffinity：Pod 落在 disktype=ssd 且优先 zone=east
./affinity.sh spread         # 观察 web-spread：2 个 Running + 2 个 Pending（maxSkew 拒绝）
./affinity.sh clean
```

成功判据：`antiaffinity` 后 `kubectl get pods -o wide` 的 NODE 列互不相同；`spread` 后看到 2 个 Running + 2 个 Pending（maxSkew 拒绝，见 How It Works 的拆解）——以实际运行为准。

### 演示一：硬性 podAntiAffinity 与污点容忍

核心 YAML 段（完整四个示例见 [`manifests/affinity.yaml`](manifests/affinity.yaml)）。**硬性反亲和 + 污点容忍的配合**（副本数打满节点数时二者缺一不可）：

```yaml
spec:
  template:
    spec:
      tolerations:                            # kind 的控制面带 NoSchedule 污点,
        - key: node-role.kubernetes.io/control-plane
          operator: Exists                    # 容忍它, 3 副本 × 硬反亲和才能用满 3 节点
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app                  # 反亲和通过 label 识别"自己人"
                    operator: In
                    values: ["web-required"]
              topologyKey: kubernetes.io/hostname
```

翻译成人话：**不允许和任何 `app=web-required` 的 Pod 在同一个节点上**——replicas=3 + 硬反亲和 + 容忍控制面污点 = 强制三副本分散到三个节点。


## How It Works

**调度器视角：先过滤，再打分**。所有调度约束汇入同一条流水线：硬性约束（required / DoNotSchedule / 不容忍的污点）在**过滤阶段**执行，不满足直接淘汰；

候选为空时 Pod 进入 Pending（`FailedScheduling` 事件），绝不降标。软性偏好（preferred weight / ScheduleAnyway）在**打分阶段**执行，只影响候选之间的排名，违反也照样调度。

排查时 `kubectl describe pod` 里看到 `FailedScheduling`（如 "node(s) didn't match pod anti-affinity rules"）就是硬约束拒绝——你在 `spread` 步骤看到的 Pending 就是这么来的。

### 演示二：nodeAffinity 硬性 + 软性叠加

先按硬性筛节点，再按软性权重排序：

```yaml
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:   # 硬性: 必须 disktype=ssd
    nodeSelectorTerms:
      - matchExpressions:
          - key: disktype
            operator: In
            values: ["ssd"]
  preferredDuringSchedulingIgnoredDuringExecution:  # 软性: 候选里优先 zone=east
    - weight: 80                              # 权重 1-100, 多条按求和排名
      preference:
        matchExpressions:
          - key: zone
            operator: In
            values: ["east"]
    - weight: 20                              # 西区作为次选
      preference:
        matchExpressions:
          - key: zone
            operator: In
            values: ["west"]
```

### 演示三：topologySpreadConstraints

反亲和是"每域最多 1 个"，副本数超过节点数就无解了；topologySpread 只要求**各域数量差（skew）不超过 maxSkew**，3 节点跑 4 副本：2/1/1 合法、3/1/0 非法：

```yaml
topologySpreadConstraints:
  - maxSkew: 1                          # 任意两个拓扑域的副本数差 <= 1
    topologyKey: kubernetes.io/hostname # 按节点维度
    whenUnsatisfiable: DoNotSchedule    # 硬性（换 ScheduleAnyway 则是软性）
    labelSelector:
      matchLabels:
        app: web-spread                 # 只统计本应用自己的 Pod
```

软性 podAntiAffinity 的写法与 nodeAffinity 软性版同构：`weight` 外层是 `podAffinityTerm`，里面的 `labelSelector + topologyKey` 与硬性版完全一致。

**IgnoredDuringExecution 的语义**：亲和性只在**调度那一刻**生效。Pod 跑起来之后，即使拓扑变化（比如节点标签被改），已运行的 Pod 也**不会被驱逐**——这与污点的 `NoExecute`（运行中也会赶人）不同。

**topologyKey 定义"拓扑域"的维度**：`kubernetes.io/hostname` 按节点打散，`topology.kubernetes.io/zone` 按可用区打散。同样的规则换个 key，语义从"每节点最多 1 个"变成"每可用区最多 1 个"。

节点必须都有这个标签，缺标签的节点视为不满足约束。

**招牌演示：maxSkew 为什么会拒绝**：`web-spread`（replicas=4）**故意不容忍 control-plane 污点**：控制面节点被计为 0 副本的域，但 Pod 进不去。

两个 worker 各放 1 个（1/1/0）之后，**第 3 个副本放哪个 worker 都是 2/1/0，skew=2 > maxSkew=1**，被 `DoNotSchedule` 拒绝 → 剩余 2 个副本永远 Pending。

一个容易误解的点：如果**所有拓扑域都可进入**，调度器总能均衡放置（任意副本数都能保持 skew≤1，如 7 副本 → 3/2/2），单纯加副本**不会**触发拒绝——拒绝只发生在"某个域进不去"时。

## Pitfalls & Q&A

踩坑清单：

- 硬约束叠加过多（反亲和 + 不容忍污点 + 节点亲和）→ 副本 Pending，看 FailedScheduling 事件定位是哪条约束拒绝的。
- 节点缺 topologyKey 标签 → 该节点被视作不满足约束，直接出局。
- 忘了污点容忍：副本永远用不满 3 节点（控制面进不去）。

**Q1: affinity 和 toleration 有什么区别？**
亲和性是 Pod 对节点的**主动选择偏好**；污点/容忍度是节点对 Pod 的**准入限制**。一个从 Pod 视角拉，一个从节点视角推，同时生效时都要满足——所以"3 副本打满 3 节点"必须同时写硬反亲和和控制面污点容忍。

**Q2: 打散后发现节点不够、副本一直 Pending 怎么办？**
硬性约束下这是设计行为而非 bug：可用性优先于运行率。解法按优先级：加节点、降副本数、改用软性约束（ScheduleAnyway / preferred）。反过来这也提醒我们：约束写得越硬，容量规划就越要留余量。

**Q3: topologySpread 和 podAntiAffinity 怎么选？**

需要"每域最多 1 个"且副本不超域数，两者皆可（antiAffinity 更老、兼容性好）；需要"均匀但允许多个"（5 副本进 3 节点 = 2/2/1）只能用 topologySpread，语义更直接还支持 `minDomains`。新项目推荐 topologySpread；

跨可用区高可用把 topologyKey 换成 `topology.kubernetes.io/zone` 即可。
