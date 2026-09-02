# 多集群联邦管理（Karmada）

## 1. 文件结构

```
30_multicluster_federation/
├── README.md           # 本文档
├── karmada.sh          # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── karmada.yaml    # 演示用的 K8s 清单
└── images/
    ├── karmada_flow.architecture.json  # 图源（Archify Typed JSON IR）
    ├── karmada_flow.html               # 交互版架构图
    └── karmada_flow.svg                # 双主题矢量版（本文档 §5 内嵌）
```

## 2. 项目概述

单集群的天花板很快会到：跨地域延迟、容灾隔离、爆炸半径控制、多供应商议价。本项目（`karmada.yaml` + `karmada.sh`）用 **Karmada** 实现联邦编排——一份 Deployment 声明配合 PropagationPolicy，6 个副本按 4:2 权重自动拆到 member-us 和 member-ap 两个集群，并演练失联故障转移——目标是掌握"一个 API 管所有集群"的多集群范式。

---

## 3. 核心机制解析

### 1. 控制面架构：聚合 API 而非代理转发

```text
用户 -> karmada-apiserver(统一入口) -> controller 生成 ResourceBinding
     -> scheduler 决定每家分多少 -> execution-controller 下发成员集群
```

Karmada 控制面跑在 host 集群，`karmadactl join` 注册成员后，成员集群**不需要安装任何组件**（push 模式）。karmada-apiserver 与原生 API 完全兼容——kubectl 直接可用，现有 YAML 原样提交。

### 2. PropagationPolicy：分发即策略

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

`Duplicated`（每个集群全量 N 副本）适合无状态就近接入；`Divided + Weighted` 把总副本数按权重切开，适合算力成本敏感场景。改总副本数时调度器按同样权重自动再平衡——扩容不再需要逐集群操作。

### 3. OverridePolicy：一份声明，各地差异

```yaml
imageOverrider:
  - component: Tag      # 亚太把镜像 Tag 覆成旧一档版本
    operator: replace
    value: "1.26"       # 必须是真实存在的 tag, 别 override 成假 registry
```

地域间的现实差异（镜像 Tag、副本数、资源规格、时区配置）全部收敛进 OverridePolicy。应用模板保持单一事实源，差异以补丁形式声明——这正是多环境配置管理在多集群维度的延伸。

### 4. 故障转移：容忍度驱动迁移

```yaml
clusterTolerations:
  - key: cluster.karmada.io/not-ready
    operator: Exists
    tolerationSeconds: 60
```

成员集群心跳超时超过 60 秒后，其 ResourceBinding 份额被重新调度到健康集群。注意权衡：网络抖动误判会造成"脑裂双跑"，生产要结合应用层幂等/数据一致性设计，而不是无脑缩短阈值。

---

## 4. 可视化

![Karmada 流水线](images/karmada_flow.svg)

上行是控制面四级流水线：kubectl 原样提交 → karmada-apiserver（原生 API 兼容）→ 生成 ResourceBinding → scheduler 按 **staticWeight 4:2** 拆分 → execution push 下发（成员集群零侵入）。下行是两类策略对象：PropagationPolicy 定拆分权重、OverridePolicy 让 member-ap 把镜像 Tag 覆成 1.26——应用模板保持单一事实源。member-ap 带着失联标签：心跳超时 60s 后份额自动迁回 member-us。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/30_multicluster_federation/images/karmada_flow.html)（或本地打开 [`images/karmada_flow.html`](images/karmada_flow.html)）。

---

## 5. 工程延伸

- **全局服务发现**: 配合 Multi-Cluster DNS / submariner 打通跨集群 Service 网络
- **成本感知调度**: 用 Karmada 的 DynamicScheduler 按 realtime 资源价格/利用率选集群
- **渐进交付**: ArgoCD (项目 28) 管 GitOps 同步 + Karmada 管跨集群编排的组合是常见生产形态
- **Fleet 安全**: 每个 member 用独立 SA + 最小 RBAC；host 集群即最高权限资产，重点加固

## 6. 多集群环境搭建（实测记录）

脚本假设 Karmada 控制面与两个成员集群已就绪。以下为一次完整搭建的实测步骤：

```bash
# 1. 两个成员集群 (kubeconfig 落到独立文件, 供 karmadactl join 使用)
kind create cluster --name member-us --kubeconfig ~/.kube/kind-config-member-us
kind create cluster --name member-ap --kubeconfig ~/.kube/kind-config-member-ap

# 2. 在 host 集群(k8s-learn)上安装 Karmada 控制面 (需 karmadactl)
karmadactl init --kubeconfig ~/.kube/config --context kind-k8s-learn \
    --karmada-data ~/.karmada-data --karmada-pki ~/.karmada-pki
#    注意: 默认证书目录 /etc/karmada 需 sudo, 用 --karmada-data/--karmada-pki 指到用户目录;
#    若中途失败, 必须先 `kubectl delete ns karmada-system` 并清空 PKI 目录后重来,
#    半途续装会因 etcd 证书不匹配而 CrashLoop

# 3. 注册成员集群
KUBECONFIG=~/.karmada-data/karmada-apiserver.config \
  karmadactl join member-us --cluster-kubeconfig ~/.kube/kind-config-member-us --karmada-context karmada-apiserver
# (member-ap 同理)

# 4. OrbStack 注意: 容器网络宿主机可达性因环境而异
#    - 成员集群 kubeconfig 里的 127.0.0.1:PORT 端点 host 集群内的控制器够不着,
#      需把 Cluster 对象与 karmada-cluster/<name> secret 的端点改成控制面容器 IP:6443
#    - karmada-apiserver 若不可直达, 可 port-forward 后把 kubeconfig 的 server 指到 127.0.0.1
#    验证: kubectl --context karmada-apiserver get clusters  # READY=True 才算成功
```
