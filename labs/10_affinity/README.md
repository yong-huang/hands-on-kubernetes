# 10 · 亲和性与拓扑打散：让副本真正分散到节点上

> 默认调度器只看"哪个节点放得下"，不关心副本之间的拓扑分布——3 副本可能全挤在一个节点上，节点一宕机全体消失。解决思路是给调度器加"约束"：有的管**去哪个节点**，有的管**和谁在一起**，有的直接规定**各拓扑域的数量差**。

## 1. 问题：多副本 ≠ 高可用

3 副本的 Deployment 常被调度到同一个节点——只要那个节点资源最多、打分最高。解决思路是给调度器加约束，本篇用一组可运行的 YAML + 脚本把四类调度工具全部过一遍。

## 2. 快速开始

```bash
./affinity.sh label          # 给 worker 打 disktype/zone 标签（nodeAffinity 演示前置）
./affinity.sh antiaffinity   # 硬性反亲和：观察 NODE 列，副本分散到不同节点
./affinity.sh nodeaffinity   # 硬性+软性 nodeAffinity：Pod 落在 disktype=ssd 且优先 zone=east
./affinity.sh spread         # 观察 web-spread：2 个 Running + 2 个 Pending（maxSkew 拒绝）
./affinity.sh clean
```

## 3. 调度器视角：先过滤，再打分

![调度器决策流水线](images/scheduler_pipeline.svg)

所有调度约束都汇入同一条流水线：**硬性约束（required / DoNotSchedule / 不容忍的污点）在过滤阶段执行，不满足直接淘汰**；候选为空时 Pod 进入 Pending（`FailedScheduling` 事件），绝不降标。**软性偏好（preferred weight / ScheduleAnyway）在打分阶段执行**，只影响候选之间的排名，违反也照样调度。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/10_affinity/images/scheduler_pipeline.html)（或本地打开 [`images/scheduler_pipeline.html`](images/scheduler_pipeline.html)）——可缩放、聚焦，追踪"候选为空 → Pending"失败分支。

### required vs preferred

| 后缀 | 语义 | 不满足时的行为 |
|------|------|----------------|
| `requiredDuringSchedulingIgnoredDuringExecution` | 硬性约束（过滤器） | Pod 一直 **Pending**，绝不降低要求 |
| `preferredDuringSchedulingIgnoredDuringExecution` | 软性偏好（打分器） | 正常调度，只是打分时尽量避开 |

注意后缀里的 **IgnoredDuringExecution**：亲和性只在**调度那一刻**生效。Pod 跑起来之后，即使拓扑变化（比如节点标签被改），已运行的 Pod 也**不会被驱逐**——这与污点的 `NoExecute` 不同。

## 4. 四类调度工具

### nodeSelector vs nodeAffinity（管"去哪个节点"）

- **nodeSelector**：一堆 `key: value` 全部匹配才行，没有"或/非"、没有软性偏好
- **nodeAffinity**：支持 `In / NotIn / Exists / DoesNotExist / Gt / Lt`，支持多组条件，硬性（required）+ 软性（preferred + weight 1-100）两级

nodeSelector 是 nodeAffinity 的极小子集，新项目直接写 nodeAffinity。

### podAntiAffinity（管"和谁不在一起"）

"不要和匹配的 Pod 落在同一个拓扑域"：

```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
          - key: app
            operator: In
            values: ["web-required"]
      topologyKey: kubernetes.io/hostname
```

翻译成人话：**不允许和任何 `app=web-required` 的 Pod 在同一个节点上**。replicas=3 + 硬反亲和（并容忍控制面污点）= 强制三副本分散到三个节点。

**topologyKey 定义"拓扑域"的维度**：`kubernetes.io/hostname` 按节点打散，`topology.kubernetes.io/zone` 按可用区打散。同样的规则换个 key，语义从"每节点最多 1 个"变成"每可用区最多 1 个"。节点必须都有这个标签，缺标签的节点视为不满足约束。

### topologySpreadConstraints（管"数量均匀度"）

反亲和是"每域最多 1 个"，副本数超过节点数就无解了。topologySpread 更精细——只要求**各域数量差（skew）不超过 maxSkew**：

```yaml
topologySpreadConstraints:
  - maxSkew: 1                          # 任意两个拓扑域的副本数差 <= 1
    topologyKey: kubernetes.io/hostname # 按节点维度
    whenUnsatisfiable: DoNotSchedule    # 硬性（换 ScheduleAnyway 则是软性）
    labelSelector:
      matchLabels:
        app: web-spread                 # 只统计本应用自己的 Pod
```

3 节点跑 4 副本：2/1/1 合法、3/1/0 非法（skew=3）。

## 5. 本实验招牌演示：maxSkew 为什么会拒绝

![maxSkew 打散](images/maxskew_spread.svg)

`web-spread`（replicas=4）**故意不容忍 control-plane 污点**：控制面节点被计为 0 副本的域，但 Pod 进不去。两个 worker 各放 1 个（1/1/0）之后，**第 3 个副本放哪个 worker 都是 2/1/0，skew=2 > maxSkew=1**，被 `DoNotSchedule` 拒绝 → 剩余 2 个副本永远 Pending。

一个容易误解的点：如果**所有拓扑域都可进入**，调度器总能均衡放置（任意副本数都能保持 skew≤1，如 7 副本 → 3/2/2），单纯加副本**不会**触发拒绝。拒绝只发生在"某个域进不去"时。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/10_affinity/images/maxskew_spread.html)（或本地打开 [`images/maxskew_spread.html`](images/maxskew_spread.html)）。

### 工具对比

| 方式 | 作用维度 | 硬/软 | 典型场景 |
|------|----------|-------|----------|
| nodeSelector | 节点属性 | 只有硬性 | 简单地钉到 GPU/SSD 节点 |
| nodeAffinity | 节点属性 | 硬 + 软（weight） | 必须 SSD、优先东区机房 |
| podAffinity | Pod 之间 | 硬 + 软 | 前端和缓存同节点/同区，降低延迟 |
| podAntiAffinity | Pod 之间 | 硬 + 软 | 同应用副本跨节点/跨可用区打散 |
| topologySpreadConstraints | 拓扑域数量差 | DoNotSchedule / ScheduleAnyway | 副本数 > 节点数时的均匀打散 |

## 6. YAML 关键字段

§4 已贴出 podAntiAffinity 与 topologySpreadConstraints 的核心段，这里补齐另外两块。**硬性反亲和 + 污点容忍的配合**（副本数打满节点数时二者缺一不可）：

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

**nodeAffinity 硬性 + 软性叠加**（先按硬性筛节点，再按软性权重排序）：

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

软性 podAntiAffinity 的写法与之同构：`weight` 外层是 `podAffinityTerm`，里面的 `labelSelector + topologyKey` 与硬性版完全一致。

四个可运行示例（含软性反亲和完整写法）见 [`manifests/affinity.yaml`](manifests/affinity.yaml)；`kubectl describe pod` 里看到 `FailedScheduling`（如 "node(s) didn't match pod anti-affinity rules"）就是硬约束拒绝。

## 7. 文件结构

```
10_affinity/
├── README.md                            # 本文档
├── affinity.sh                          # label / antiaffinity / nodeaffinity / spread / clean
├── manifests/
│   └── affinity.yaml                    # 硬性/软性 antiAffinity、nodeAffinity、topologySpread
└── images/
    ├── scheduler_pipeline.workflow.json   # 图源（Archify Typed JSON IR）
    ├── scheduler_pipeline.html            # 交互版：调度决策流水线
    ├── scheduler_pipeline.svg             # 双主题矢量版（本文档 §3 内嵌，跟随系统深浅色）
    ├── maxskew_spread.architecture.json   # 图源（Archify Typed JSON IR）
    ├── maxskew_spread.html                # 交互版：maxSkew 打散
    └── maxskew_spread.svg                 # 双主题矢量版（本文档 §5 内嵌，跟随系统深浅色）
```

> 三类产物同源：`*.workflow.json` / `*.architecture.json` 是图源（Archify Typed JSON IR，`node bin/archify.mjs deliver <type> <json> <html>` 可复现），`.html` 是交付的交互成品，`.svg` 是从交互版 Export 菜单导出的双主题矢量图（跟随系统深浅色，任意缩放不糊）。

## 8. 面试要点

1. **如何保证副本跨节点分布**：① 硬性 podAntiAffinity（每节点最多 1 个，副本超节点数会 Pending）；② topologySpreadConstraints（maxSkew=1 + DoNotSchedule，均匀且支持副本数大于节点数）；③ 软性版本尽量打散但不阻塞。跨可用区高可用一般用 `topologyKey: topology.kubernetes.io/zone`。
2. **affinity 和 toleration 的区别**：亲和性是 Pod 对节点的**主动选择偏好**；污点/容忍度是节点对 Pod 的**准入限制**。一个从 Pod 视角拉，一个从节点视角推，同时生效时都要满足。
3. **打散后节点不够怎么办**：硬性约束下多余副本一直 Pending（FailedScheduling 事件）。这不是 bug 而是设计：可用性优先于运行率。解法：加节点、降副本、改软性。
4. **topologySpread vs podAntiAffinity 怎么选**：需要"每域最多 1 个"且副本不超域数，两者皆可（antiAffinity 更老、兼容性好）；需要"均匀但允许多个"（5 副本进 3 节点 = 2/2/1）只能用 topologySpread，语义更直接还支持 `minDomains`。新项目推荐后者。

## 9. 总结

调度约束只有两件事：**过滤（硬性）与打分（软性）**。nodeAffinity 管节点维度，pod(anti)Affinity 管 Pod 维度，topologySpreadConstraints 管数量均匀度；`required`/`DoNotSchedule` 不满足就 Pending，`preferred`/`ScheduleAnyway` 尽力而为。记住 `IgnoredDuringExecution`——规则只在调度瞬间生效，之后拓扑怎么变都不动已运行的 Pod。配合 `affinity.sh` 的 web-spread 演示（1/1/0 之后第 3 副本放哪都是 skew=2），能直观看到"约束太硬、域进不去"时调度器的行为。
