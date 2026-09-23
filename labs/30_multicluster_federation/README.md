# 30 · 多集群联邦：Karmada

> 单集群的天花板很快会到：跨地域延迟、容灾隔离、爆炸半径控制、多供应商议价。本实验用 **Karmada** 实现联邦编排——一份 Deployment 声明配合 PropagationPolicy，6 个副本按 4:2 权重自动拆到 member-us 和 member-ap 两个集群，并演练失联故障转移。

## What

Karmada 的控制面跑在 host 集群，是一条聚合 API 的流水线（而非代理转发）：

```text
用户 -> karmada-apiserver(统一入口) -> controller 生成 ResourceBinding
     -> scheduler 决定每家分多少 -> execution-controller 下发成员集群
```

karmada-apiserver 与原生 API 完全兼容——kubectl 直接可用，现有 YAML 原样提交；成员集群用 `karmadactl join` 注册后**不需要安装任何组件**（push 模式）。一句话心智模型：**一个 API 管所有集群**——分发、差异、故障转移都成为声明式策略。

| 策略对象 | 管什么 |
|---------|--------|
| PropagationPolicy | 分发到哪些集群、副本怎么拆（Duplicated 复制 / Divided 拆分加权） |
| OverridePolicy | 各集群的差异补丁（镜像 Tag、副本数、资源规格） |
| clusterTolerations | 成员失联多久后触发故障转移 |

## Why

跨地域部署要就近接入（延迟）、容灾要求故障域隔离（一个集群炸了另一个还在）、爆炸半径控制要求不同业务物理隔离、多供应商带来议价与合规灵活性——这些需求都指向"多个集群"。但逐集群 kubectl 的运维方式把复杂度全推给人：改一次副本数要跑 N 个命令，故障切换靠人盯。联邦编排把这些变成声明式策略，由控制面持续收敛。

## How

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

多集群环境搭建的实测步骤（脚本假设控制面与成员集群已就绪）：

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

## Deep Dive

**Duplicated vs Divided 的选择**：`Duplicated`（每个集群全量 N 副本）适合无状态就近接入；`Divided + Weighted` 把总副本数按权重切开，适合算力成本敏感场景。改总副本数时调度器按同样权重自动再平衡——扩容不再需要逐集群操作。

**OverridePolicy 的边界**：地域间的现实差异（镜像 Tag、副本数、资源规格、时区配置）全部收敛进 OverridePolicy，应用模板保持单一事实源——这是多环境配置管理（lab 27 的 values）在多集群维度的延伸。注意 override 的 value 必须是真实存在的 tag，别覆盖成假 registry 或假版本。

**故障转移的权衡**：成员集群心跳超时超过 60 秒后，其 ResourceBinding 份额被重新调度到健康集群。但网络抖动误判会造成"脑裂双跑"——生产要结合应用层幂等/数据一致性设计，而不是无脑缩短阈值。

踩坑清单（来自实测）：

- `karmadactl init` 默认证书目录 `/etc/karmada` 需 sudo，用 `--karmada-data`/`--karmada-pki` 指到用户目录
- 安装中途失败必须先 `kubectl delete ns karmada-system` 并清空 PKI 目录后重来——半途续装会因 etcd 证书不匹配而 CrashLoop
- OrbStack/Docker 环境下，成员集群 kubeconfig 里的 `127.0.0.1:PORT` 端点 host 集群内的控制器够不着，需把 Cluster 对象端点改成控制面容器 IP:6443——`./karmada.sh endpoints` 会探测容器 IP 并回写端点（容器 IP 重启后会变，重跑即可恢复 READY=True）；karmada-apiserver 若不可直达，可 port-forward 后把 kubeconfig 的 server 指到 127.0.0.1。验证标准：`kubectl --context karmada-apiserver get clusters` 全部 READY=True

## Q&A

**Q1: 跨集群的服务发现和网络怎么打通？**
Karmada 只管编排不管网络。配合 Multi-Cluster DNS 做全局服务发现，或用 submariner 打通跨集群 Service 网络——应用才能"在 A 集群调用 B 集群的服务"。

**Q2: 集群选择能不能更聪明？**
成本感知调度：Karmada 的 DynamicScheduler 可按实时资源价格/利用率选集群——把"哪个集群便宜、哪里有余量"变成调度器的输入，而不是运维的经验。

**Q3: Karmada 和 ArgoCD 是竞争关系吗？**
是互补组合：ArgoCD（lab 28）管 GitOps 同步（Git → host 集群的期望状态），Karmada 管跨集群编排（host 期望状态 → 各成员集群）。"ArgoCD + Karmada"是常见的生产形态——Git 仍是唯一可信源，Karmada 是它向下收敛的一环。

**Q4: 联邦的安全边界要注意什么？**
每个 member 用独立 ServiceAccount + 最小 RBAC；host 集群握着所有成员的控制权，是最高权限资产，要重点加固——它的失守等于全部集群失守。
