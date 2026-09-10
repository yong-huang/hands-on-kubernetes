# 09 · HPA：自动扩缩容的原理与实战

> 线上流量从来不是恒定的。HPA 把"扩缩容"交给控制器：持续观测 Pod 的 CPU/内存指标，与目标值比对后自动增减副本，让"实际利用率"向"目标利用率"持续收敛——声明式目标值 + 控制循环在伸缩场景的又一次应用。

## 1. 为什么手动 scale 不行

按峰值配置副本数，低谷时资源白费；按均值配置，峰值一来就过载。手动 `kubectl scale` 有三个问题：**人反应慢**（发现过载到敲完命令已过几分钟）、**无法 7x24 值守**（凌晨的流量毛刺没人管）、**不知道扩到几个**（拍脑袋定数字）。

## 2. 快速开始

```bash
./hpa.sh install   # 安装 metrics-server（HPA 指标来源，多数集群默认没有）
./hpa.sh apply     # 部署 CPU 密集型应用 + HPA（autoscaling/v2，目标 CPU 50%）
./hpa.sh load      # 制造 CPU 负载，观察 TARGETS 冲高、副本 1→N
./hpa.sh watch     # 撤掉负载，观察 5 分钟稳定窗口后的慢缩容
./hpa.sh clean
```

## 3. 控制环：指标从哪来，指令到哪去

![HPA 控制环](images/hpa_control_loop.svg)

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/09_hpa/images/hpa_control_loop.html)（未开启 Pages 时可克隆仓库后本地打开 [`images/hpa_control_loop.html`](images/hpa_control_loop.html)）——支持缩放、节点聚焦、连线路径追踪、深浅主题切换。

上图是一条闭环：**压测负载 → Pods 用量升高 → kubelet (cAdvisor) 采集 → metrics-server 聚合为 Metrics API → HPA 控制器按公式算出期望副本 → 改 Deployment 的 `scale.replicas` → 增删 Pod → 新用量再反馈回指标层**。

HPA 每 15 秒 reconcile 一次，核心公式：

```
desiredReplicas = ceil( currentReplicas × currentMetricValue / desiredMetricValue )
```

例：目标 CPU 利用率 50%，当前 2 副本平均利用率 90% → `ceil(2 × 90 / 50) = 4`，扩到 4 个。要点：

- **利用率是所有就绪 Pod 的平均值**，不是单 Pod 最大值
- 多条 metrics（CPU、内存、自定义）各自算一个 desired，**取最大值**（宁多扩）
- 扩容有 `tolerance`（默认 ±10%）：结果在带内不动，防指标微抖引起 flapping
- 缩容时分子按"缩完还剩几个 Pod"重新校验，保证缩完不立刻超载

### 指标链路与前置条件

`Resource` 类型的 CPU/内存指标由 **metrics-server** 提供（大多数集群默认不装，装完 `kubectl top` 才能用）；业务指标（QPS、队列长度）需要 **Prometheus Adapter** 或 KEDA 注册为 `custom.metrics.k8s.io`。

**必须设置 `resources.requests`**：CPU 利用率 = 实际用量 / `requests.cpu`——requests 是百分比计算的分母。没有它，TARGETS 列一直显示 `<unknown>`，HPA 永远不会动作。

## 4. behavior：为什么扩容快、缩容慢

`autoscaling/v2` 的 `behavior` 字段：

| 配置 | 默认 | 本例 | 目的 |
|------|------|------|------|
| scaleUp.stabilizationWindowSeconds | 0s | 0s | 扩容要快，立即执行 |
| scaleUp.policies | 15s 内 +100% 或 +4 Pod | 同左 | 限制单次幅度，防止指标异常炸到 maxReplicas |
| scaleDown.stabilizationWindowSeconds | 300s | 300s | **缩容前需连续 5 分钟低负载** |
| scaleDown.policies | 15s 内 -25% 或 -1 Pod | 同左 | 缩容步子要小 |

缩容慢是刻意设计：刚缩掉的 Pod 说没就没，流量回升时重新调度、拉镜像、预热要几十秒；而"多留几个 Pod 几分钟"成本很低。这就是经典的**扩容快、缩容慢**的非对称折中。

## 5. YAML 关键字段

```yaml
spec:
  scaleTargetRef:               # 扩缩容目标（Deployment 或 StatefulSet）
    kind: Deployment
    name: cpu-stress-app
  minReplicas: 1                # 副本下限
  maxReplicas: 10               # 硬顶，防止指标异常导致失控扩容
  metrics:
    - type: Resource            # Pod 资源指标（metrics-server 提供）
      resource:
        name: cpu
        target:
          type: Utilization     # 利用率 %；也支持 AverageValue（绝对值）
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # 缩容稳定窗口 5 分钟
```

易踩的坑：

- Pod 未设 `resources.requests` → TARGETS 显示 `<unknown>`，HPA 不工作
- kind/minikube 里 metrics-server 需加 `--kubelet-insecure-tls`（kubelet 证书无 CA 签名）
- 同时配 CPU 和内存指标时，**内存目标设高些（如 60%）**：内存不随请求结束回落，易误触发
- 手动 `kubectl scale` 会被 HPA 在下个周期覆盖（HPA 才是期望副本数的属主）

## 6. 文件结构

```
09_hpa/
├── README.md                          # 本文档
├── hpa.sh                             # install / apply / load / watch / clean
├── manifests/
│   ├── hpa.yaml                       # Deployment + HPA（autoscaling/v2）
│   └── metrics-server.yaml            # metrics-server 安装清单（本地缓存）
└── images/
    ├── hpa_control_loop.architecture.json  # 图源（Typed JSON IR）
    ├── hpa_control_loop.html               # 交互版架构图（浏览器打开，可缩放/聚焦/追踪连线）
    └── hpa_control_loop.svg                # 双主题矢量版（本文档 §3 内嵌，跟随系统深浅色）
```

> 三类产物同源：`hpa_control_loop.architecture.json` 是图源（Typed JSON IR），`.html` 是交付的交互成品，`.svg` 是从交互版 Export 菜单导出的双主题矢量图（跟随系统深浅色，任意缩放不糊）。

## 7. 面试要点

1. **扩容算法**：`desired = ceil(currentReplicas × currentValue / targetValue)`；利用率按就绪 Pod 平均、以 requests 为分母；多指标取最大 desired；±10% tolerance 内不动作；默认 15s 一个控制周期。
2. **为什么缩容慢**：300s 稳定窗口 + -25%/15s 步长限制。缩容错误代价高——流量回升要重新调度、拉镜像、预热（分钟级）；扩容错误只是暂时多占资源，所以非对称设计是刻意的。
3. **HPA / VPA / Cluster Autoscaler**：三者正交。HPA 调副本数（水平）；VPA 调单 Pod 的 requests/limits（垂直，重启生效，与 HPA 同用会冲突）；Cluster Autoscaler 调节点数。常见组合：HPA + Cluster Autoscaler。
4. **自定义指标**：Resource 只有 CPU/内存。业务指标用 Prometheus Adapter 把查询注册为 `custom.metrics.k8s.io`（Pods 类型按 Pod 平均）或 `external.metrics.k8s.io`；KEDA 可以直接以任意 Prometheus 查询/Lag 为信号源驱动扩缩。

## 8. 总结

HPA = 指标 + 公式 + 控制环。主线：**metrics-server 供数 → 控制器按 `ceil(当前副本 × 当前利用率/目标利用率)` 算期望副本 → 改 Deployment 的 replicas**。两个必踩点：Pod 不设 requests 则百分比无意义；`behavior` 的稳定窗口解释了"为什么缩容那么慢"。配合 `hpa.sh` 压测扩容、撤压观察缩容的完整演示，直观看到控制循环收敛的全过程。
