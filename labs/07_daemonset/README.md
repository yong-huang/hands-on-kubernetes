# 07 · DaemonSet：每个节点一个的守护进程

> 有一类负载不在意"总数"，而在意"覆盖面"——集群里每个节点都必须恰好跑一个。DaemonSet 的副本数不写死，**由节点数决定**。

## What

DaemonSet 保证**每个匹配的节点上恰好运行一个 Pod 副本**：节点加入自动创建，节点移除自动清理。一句话心智模型：**desired 由节点数决定，覆盖面由 tolerations / nodeAffinity 决定，数据面靠 hostPath 触达节点本身**——它是"以节点为刻度的 Deployment"。

与 Deployment 的逐项对比：

| 维度 | DaemonSet | Deployment |
|------|-----------|------------|
| 副本数 | 由匹配节点数决定，不可手动 scale | 手动声明 `replicas`，可 scale |
| 分布 | 每个节点**恰好一个** Pod | 任意节点，可能堆积也可能空缺 |
| 控制器 | DaemonSet controller（直接管理 Pod） | Deployment → ReplicaSet → Pod 三层 |
| 滚动更新 | 逐节点替换，maxUnavailable 可为百分比（按节点比例）；**没有 maxSurge**（每节点只能一个） | maxSurge / maxUnavailable |
| 节点扩容 | 新节点自动获得 Pod | 副本数不变，需手动扩容 |
| hostPath | 常用（读取节点文件） | 几乎不用 |
| 典型场景 | 日志、监控 Agent、CNI、kube-proxy、设备插件 | Web / API 等无状态业务 |

## Why

典型场景：日志采集（Fluent Bit / Filebeat 每节点一个 Agent）、节点监控（Node Exporter）、网络插件（CNI、kube-proxy 本质上也是每节点一份）、安全 Agent、GPU Device Plugin。这类"节点级守护进程"用 Deployment 管理会出乱子：节点扩容后新节点没有 Agent，调度器还可能把两个 Agent 堆到同一个节点上。

覆盖面就是这类负载的正确性：日志 Agent 少覆盖一个节点，那个节点的日志就永久丢失；监控 Agent 少一个，那个节点的指标就是盲区。所以"每个节点恰好一个"必须是控制器保证的不变量，而不是调度巧合。

## How

```bash
cd labs/07_daemonset
./daemonset.sh apply     # 部署两个 DaemonSet：日志采集（全节点）+ ssd-cache-agent（nodeAffinity）
./daemonset.sh dist      # -o wide 对比：节点数 vs Pod 数，每个节点名只出现一次
./daemonset.sh label     # 给节点打/摘 disktype=ssd 标签，看 Pod 即时增删
./daemonset.sh update    # 改镜像触发滚动更新（逐节点替换）
./daemonset.sh clean
```

覆盖面的两道开关（`manifests/daemonset.yaml`）。**tolerations**——让 Agent 能上控制面节点：

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane   # 精确容忍控制面污点
    effect: NoSchedule
  - operator: Exists                             # 容忍一切污点 (最强, 慎用)
    effect: NoExecute
```

**nodeAffinity**——只在 SSD 节点跑本地缓存 Agent：

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: disktype
              operator: In          # In / NotIn / Exists / Gt / Lt
              values: [ssd]
```

**hostPath**——日志采集的前提是"能看到节点上的日志文件"：

```yaml
volumes:
  - name: varlog
    hostPath:
      path: /var/log
  - name: podlog
    hostPath:
      path: /var/log/pods     # containerd (CRI) 日志目录; 老版 Docker 节点为
      type: DirectoryOrCreate # /var/lib/docker/containers/*/*-json.log
```

## Deep Dive

**调度模型**：DaemonSet 控制器（kube-controller-manager 内的 daemon pod controller）的逻辑：

1. 监听集群所有节点和 DaemonSet 的变化；
2. 对每个 DaemonSet，计算"应该有 Pod 的节点集合"——所有**匹配 selector/affinity、且可调度**的节点；
3. 节点上有 Pod 则保持，没有则创建；有两个则删多余的；
4. 节点被删除或 Pod 被驱逐时，在其他匹配节点上自动补齐。

所以 `kubectl get daemonset` 的 `DESIRED` 不是你声明的数字，而是**当前合格节点数**。集群从 3 节点扩到 5 节点，DESIRED 自动变 5，无需任何操作——这是与 Deployment 最本质的区别。nodeAffinity 的关键特性：**标签变化即时生效**——给节点打上 `disktype=ssd`，控制器立刻在该节点创建 Pod；去掉标签，Pod 被自动删除（`daemonset.sh` 的 `label` 步骤演示了这一过程）。

**为什么需要 toleration 才能上控制面节点**：控制面节点默认打有污点 `node-role.kubernetes.io/control-plane:NoSchedule`（"不许新 Pod 调度到我这"），以保护 etcd / API server 不被业务挤占。但日志、监控 Agent 需要**全覆盖**——控制面的日志同样要采集——所以要显式容忍。指定 key 只容忍特定污点；`operator: Exists` 不限 key、容忍一切匹配 effect 的污点，通常只有 kube-proxy / CNI 这种"不上就无法工作"的组件才需要。

**滚动更新**：改 Pod 模板即触发；默认 RollingUpdate 逐节点杀旧建新，maxUnavailable（默认 1）可写百分比；OnDelete 完全手动。`rollout status/undo/history` 与 Deployment 相同。注意 **DaemonSet 没有 maxSurge**——每节点只能有一个 Pod，无法"先建新再杀旧"。

踩坑清单：

- hostPath 是"逃生舱"性质的卷类型，只有节点级 Agent 这种确实需要访问节点本身的场景才该用；普通业务 Pod 用它既不安全也不可移植。
- DaemonSet 每个节点都跑，**必须设置 resources**，否则节点数一多就是全集群的资源放大。
- 节点被 cordon 后 DaemonSet **不会**往上补 Pod；drain 会驱逐 DaemonSet Pod（默认会被拦下，需 `--ignore-daemonsets`），控制器随后决定是否重建。

## Q&A

**Q1: 为什么用 DaemonSet 而不是 `replicas=节点数` 的 Deployment + 反亲和？**
反亲和方案只是"碰巧"达成一一对应：节点扩容后 Deployment 的副本数不会自己变，需要额外的控制器去改 replicas——等于自己重新发明 DaemonSet。DaemonSet 把"覆盖每个合格节点"作为控制器的不变量，节点增删、标签变化都由它自动收敛，且它能绕过部分调度约束直接在节点上建 Pod（未调度先绑定），这是 Deployment 的调度器做不到的。

**Q2: kubelet 本身就在每个节点上，为什么 kube-proxy、CNI 还要用 DaemonSet 跑？**
kubelet 管的是容器运行时和 Pod 生命周期，而 kube-proxy（转发规则）、CNI（网络插件）是要"随集群配置持续变化"的组件——镜像要升级、参数要下发。用 DaemonSet 管理它们，就复用了 K8s 的滚动更新、回滚、版本追踪体系；这也是"设备插件"（GPU Device Plugin）选择 DaemonSet 的原因：插件本身是 Pod，能被 K8s 统一编排。
