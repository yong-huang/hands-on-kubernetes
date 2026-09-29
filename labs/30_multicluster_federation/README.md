# 30 · 多集群联邦：Karmada

> 单集群的天花板很快会到：跨地域延迟、容灾隔离、爆炸半径控制、多供应商议价。本实验用 **Karmada** 实现联邦编排——一份 Deployment 声明配合 PropagationPolicy，6 个副本按 4:2 权重自动拆到 member-us 和 member-ap 两个集群，并演练失联故障转移。读完本篇，你将掌握"一个 API 管所有集群"的范式与三类策略对象。

## Background

业务长到一定规模，单集群就不够用了：用户分布在两大洲，单点部署必有一边延迟高；容灾要求两个故障域，单集群一炸全炸；不同业务要物理隔离控制爆炸半径；议价与合规要求不绑死一家云。

多集群的早期做法是"多套 kubeconfig 逐个 kubectl"：改一次副本数要跑 N 个命令，故障切换靠人盯监控，集群间的差异（镜像版本、副本规格）靠文档记忆。联邦编排把这些变成声明式策略：写一次"6 副本按 4:2 拆到两个集群"，控制面持续收敛，节点故障自动迁移份额。

## What

Karmada 的控制面跑在 host 集群，是一条聚合 API 的流水线（而非代理转发）：

```text
用户 -> karmada-apiserver(统一入口) -> controller 生成 ResourceBinding
     -> scheduler 决定每家分多少 -> execution-controller 下发成员集群
```

karmada-apiserver 与原生 API 完全兼容——kubectl 直接可用，现有 YAML 原样提交；成员集群用 `karmadactl join` 注册后**不需要安装任何组件**（push 模式）。

一句话心智模型：**一个 API 管所有集群**——可以把 Karmada 想象成"集群的调度器"；但和单集群调度器不同的是，它调度的单位是"集群"，分发、差异、故障转移都成为声明式策略。

| 策略对象 | 管什么 |
|---------|--------|
| PropagationPolicy | 分发到哪些集群、副本怎么拆（Duplicated 复制 / Divided 拆分加权） |
| OverridePolicy | 各集群的差异补丁（镜像 Tag、副本数、资源规格） |
| clusterTolerations | 成员失联多久后触发故障转移 |

## When to Use

典型场景：中美用户各连就近集群（按权重分发）；主集群故障时副本份额自动迁到备集群（clusterTolerations + 故障转移）；不同合规要求的工作负载物理隔离在不同供应商集群。

何时不用：单集群容量和延迟都满足（联邦增加一层控制面与心智负担）；需要跨集群强一致事务（联邦管编排不管数据一致性）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 多 kubeconfig 手工管 | 全靠人 | 一两个集群、变更少 |
| Karmada（本实验） | 聚合 API + 策略分发 | 多集群编排需求成规模 |
| Cluster API | 管集群的生命周期创建 | 与 Karmada 互补：CA 建、Karmada 用 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；karmadactl 已安装；两个成员集群已按 How It Works 的实测步骤建好并注册。

```bash
cd labs/30_multicluster_federation
./karmada.sh install    # 前置检查（karmadactl、控制面、成员集群）
./karmada.sh deploy     # 提交 Deployment + PropagationPolicy，观察 4:2 拆分
./karmada.sh override   # OverridePolicy：member-ap 镜像 Tag 覆成 1.26
./karmada.sh failover   # 断开 member-ap，演练份额迁回 member-us
./karmada.sh clean
```

PropagationPolicy——分发即策略（`manifests/karmada.yaml`）：

```yaml
placement:
  clusterAffinity: {clusterNames: [member-us, member-ap]}
  replicaScheduling:
    replicaSchedulingType: Divided        # 拆分, 不是复制
    weightPreference:
      staticWeightList:
        - {targetCluster: {clusterNames: [member-us]}, weight: 4}
        - {targetCluster: {clusterNames: [member-ap]}, weight: 2}
```

OverridePolicy——一份声明，各地差异：

```yaml
imageOverrider:
  - component: Tag      # 亚太把镜像 Tag 覆成旧一档版本
    operator: replace
    value: "1.26"       # 必须是真实存在的 tag, 别 override 成假 registry
```

clusterTolerations——容忍度驱动迁移：

```yaml
clusterTolerations:
  - key: cluster.karmada.io/not-ready
    operator: Exists
    tolerationSeconds: 60
```

## How It Works

**Duplicated vs Divided 的选择**：`Duplicated`（每个集群全量 N 副本）适合无状态就近接入；`Divided + Weighted` 把总副本数按权重切开，适合算力成本敏感场景。

改总副本数时调度器按同样权重自动再平衡——你在 `deploy` 步骤看到的 4:2 拆分，扩容后依然按这个比例重排。扩容不再需要逐集群操作。

**OverridePolicy 的边界**：地域间的现实差异（镜像 Tag、副本数、资源规格、时区配置）全部收敛进 OverridePolicy，应用模板保持单一事实源——这是多环境配置管理（lab 27 的 values）在多集群维度的延伸。

注意 override 的 value 必须是真实存在的 tag，别覆盖成假 registry 或假版本。

**故障转移的权衡**：成员集群心跳超时超过 60 秒后，其 ResourceBinding 份额被重新调度到健康集群。但网络抖动误判会造成"脑裂双跑"（两边同时认为自己是主、同时服务）——生产要结合应用层幂等/数据一致性设计，而不是无脑缩短阈值。

你在 `failover` 步骤看到的份额迁移，就是这条容忍度驱动的路径。

**多集群环境搭建的实测步骤**（脚本假设控制面与成员集群已就绪）：

```bash
# 1. 两个成员集群 (kubeconfig 落到独立文件, 供 karmadactl join 使用)
#    用仓库根的 kind-cluster.sh 建集群, 自动注入 containerd 镜像源避免节点拉镜像超时
../../scripts/kind-cluster.sh member-us 1 1
../../scripts/kind-cluster.sh member-ap 1 1

# 2. 在 host 集群(k8s-learn)上安装 Karmada 控制面 (需 karmadactl)
karmadactl init --kubeconfig ~/.kube/config --context kind-k8s-learn \
    --karmada-data ~/.karmada-data --karmada-pki ~/.karmada-pki

# 3. 注册成员集群
KUBECONFIG=~/.karmada-data/karmada-apiserver.config \
  karmadactl join member-us --cluster-kubeconfig ~/.kube/kind-config-member-us --karmada-context karmada-apiserver
# (member-ap 同理)
```

## Pitfalls & Q&A

踩坑清单（来自实测）：

- `karmadactl init` 默认证书目录 `/etc/karmada` 需 sudo，用 `--karmada-data`/`--karmada-pki` 指到用户目录。
- 安装中途失败必须先 `kubectl delete ns karmada-system` 并清空 PKI 目录后重来——半途续装会因 etcd 证书不匹配而 CrashLoop。
- OrbStack/Docker 环境下，成员集群 kubeconfig 里的 `127.0.0.1:PORT` 端点 host 集群内的控制器够不着：把 Cluster 对象端点改成控制面容器 IP:6443，`./karmada.sh endpoints` 会探测容器 IP 并回写（容器 IP 重启后会变，重跑即可恢复）。
- karmada-apiserver 若不可直达：port-forward 后把 kubeconfig 的 server 指到 127.0.0.1。
- 验证标准：`kubectl --context karmada-apiserver get clusters` 全部 READY=True。

**Q1: 跨集群的服务发现和网络怎么打通？**
Karmada 只管编排不管网络。配合 Multi-Cluster DNS 做全局服务发现，或用 submariner 打通跨集群 Service 网络——应用才能"在 A 集群调用 B 集群的服务"。

**Q2: 集群选择能不能更聪明？**
成本感知调度：Karmada 的 DynamicScheduler 可按实时资源价格/利用率选集群——把"哪个集群便宜、哪里有余量"变成调度器的输入，而不是运维的经验。

**Q3: Karmada 和 ArgoCD 是竞争关系吗？**

是互补组合：ArgoCD（lab 28）管 GitOps 同步（Git → host 集群的期望状态），Karmada 管跨集群编排（host 期望状态 → 各成员集群）。"ArgoCD + Karmada"是常见的生产形态——Git 仍是唯一可信源，Karmada 是它向下收敛的一环。

**Q4: 联邦的安全边界要注意什么？**
每个 member 用独立 ServiceAccount + 最小 RBAC；host 集群握着所有成员的控制权，是最高权限资产，要重点加固——它的失守等于全部集群失守。
