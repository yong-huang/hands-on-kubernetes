# 02 · Pod：Kubernetes 的最小调度单元

> Pod 是 K8s 一切对象的原子：Deployment、Service、StatefulSet 都只是"管理 Pod 的不同方式"。读完本篇，你将理解 Pod 为什么存在、pause / initContainer / sidecar / 探针各自解决什么问题，并跑通一个含 4 种 Pod 示例的演示。

## Background

刚从 Docker 转到 Kubernetes 的人通常这样部署应用：一个容器跑主进程，再想办法让日志收集、配置下发的进程也在附近运行。现实中的应用经常是"一组功能互补的进程"——主进程 + 日志收集 + 配置下发 + 网络代理，这些进程需要共享磁盘、用 `localhost` 互相通信、生命周期绑定在一起。

靠人工保证这种"绑定"很快就撞墙：调度器可能把两个容器放到不同机器上；主容器重启后，日志收集器还指着旧容器。Linux 里早就有这种分组思想（进程组），Kubernetes 把它搬进了容器世界，这个调度原子就是 Pod——K8s 不会单独调度某个容器，调度的原子单位永远是 Pod。

## What

Pod 是一组共享网络命名空间和存储卷的容器，同生共死、被调度到同一个节点上（命名空间是 Linux 隔离进程视野的机制，共享命名空间即共享网络与存储视野）。一句话心智模型：**可以把 Pod 想象成一台逻辑小机器**；但和虚拟机不同的是，它通常只装"一组亲缘进程"而不是一整个操作系统。

一个 Pod 的自然子部件：

| 部件 | 角色 |
|---|---|
| pause 容器 | 用户看不见的基础设施容器，持有 Pod 的网络/IPC 命名空间 |
| initContainer | 主容器启动前串行执行的一次性初始化容器 |
| sidecar | 与主容器并行长期运行的辅助容器（日志、代理） |
| 探针（probe） | kubelet 周期性执行的健康检查，驱动重启与摘流（摘流 = 暂时不给它派流量，见 How It Works） |

## When to Use

典型场景：把"主服务 + 它的日志收集器"绑成一体部署；主容器启动前需要等依赖就绪或拉取模型文件；需要给进程配"卡死自动重启、没准备好不接流量"的健康规则。

何时不用：两个可以独立扩缩容、独立发布的服务（如 web 和数据库）不该塞进同一个 Pod——绑定后无法单独伸缩，这是新手最常见的误用。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 单容器直跑（Docker） | 无自愈、无调度 | 本机开发调试 |
| Pod | 一组亲缘容器 = 一个调度原子 | 进程间需要共享网络/存储/生命周期 |
| 多个单容器 Pod | 各自独立伸缩 | 进程间无亲缘关系 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/02_pod
./pod.sh              # 一条龙：apply -> describe -> logs -> exec -> label -> 探针观察 -> 清理
./pod.sh demo-ns      # 也可以指定 namespace（K8s 里隔离资源的分组，可理解为同一集群内的独立子环境；默认 default）
```

脚本每步都会打印观察要点。成功判据：`kubectl get pods` 中 nginx-sidecar-pod 显示 `2/2 Running`（两个容器都就绪）。跑完后用交互命令继续观察：

```bash
kubectl apply -f manifests/pod.yaml
kubectl exec -it nginx-sidecar-pod -c log-tailer -- sh   # 进 sidecar 容器
kubectl exec nginx-sidecar-pod -c log-tailer -- ls -la /var/log/nginx   # 验证共享卷
kubectl delete -f manifests/pod.yaml
```

`manifests/pod.yaml` 含 4 个 Pod 示例：单容器 / sidecar / initContainer / 探针。YAML 关键字段：

```yaml
metadata:
  labels:            # 标签是 K8s 一切"找 Pod"机制的基础
    app: nginx       # Service/Deployment 通过 selector 匹配
spec:
  containers:
    - resources:
        requests:    # 调度依据：节点剩余资源 >= requests 才会被调度上去
          cpu: 100m  # 100m = 0.1 核
        limits:      # 运行上限：内存超限 → OOMKilled；CPU 超限 → 限流不杀
          memory: 256Mi
  volumes:
    - name: shared-logs
      emptyDir: {}   # Pod 级临时卷，Pod 删除即消失，常用于容器间共享
```

常用 kubectl 命令表：

| 命令 | 作用 |
|---|---|
| `kubectl apply -f manifests/pod.yaml` | 创建/更新资源 |
| `kubectl get pods -o wide` | 查看状态（含 IP、所在节点） |
| `kubectl get pods --show-labels` / `-l app=nginx` | 查看 / 按标签筛选 |
| `kubectl label pod nginx-pod env=demo --overwrite` | 打标签（`--overwrite` 覆盖） |
| `kubectl describe pod <name>` | 详情 + Events，排查第一站 |
| `kubectl logs <pod> [-c 容器名] [-f]` | 看日志；多容器 Pod 必须指定 `-c` |
| `kubectl exec -it <pod> -- sh` | 进入容器 |
| `kubectl logs <pod> --previous` | 上一次崩溃的日志（CrashLoop 排查关键） |
| `kubectl delete -f manifests/pod.yaml` | 按清单清理 |

## How It Works

**pause 容器（infrastructure container）**：每个 Pod 底层都有一个用户看不见的 `pause` 容器，它最先启动，作用是**持有 Pod 的网络（和 IPC）命名空间**，其余业务容器都加入它的命名空间。因此：

- 同一个 Pod 里所有容器共享同一个 IP、同一套端口空间
- 容器之间用 `localhost` 互访（不同容器不能占用同一端口）
- 主容器崩溃重启，Pod IP 不变（是 pause 在撑着网络）

pause 平时几乎不消耗资源。它的存在解释了 `kubectl get pod` 里看到的容器数和节点上 `docker ps` 看到的容器数"差一个"的现象——多出来的就是 pause。

**sidecar vs initContainer**：两者都是"在主容器之外附加容器"，但时机完全不同——

| | initContainer | sidecar |
|---|---|---|
| 执行时机 | 主容器启动**之前** | 与主容器**同时**运行 |
| 执行方式 | 串行，逐个执行 | 并行，长期运行 |
| 成功条件 | 必须 `exit 0` 才继续 | 无退出概念，跟随 Pod 生命周期 |
| 典型用途 | 等待依赖就绪、下载模型、初始化配置 | 日志收集、网络代理（Istio envoy）、数据同步 |

manifests 里的 `nginx-sidecar-pod` 演示了经典 sidecar：nginx 写日志到共享卷，busybox `tail -f` 实时读取——你在 Quick Start 里验证的共享卷，就是这两个容器看到的同一份 `emptyDir`。

**三种探针的执行语义**：探针由 kubelet（节点上按 Pod 清单真正启停容器的组件）周期性执行，类型可以是 `httpGet`、`tcpSocket` 或 `exec`。

| 探针 | 失败后果 | 解决什么问题 |
|---|---|---|
| **livenessProbe** | **重启容器** | 应用卡死、死锁——进程活着但不工作 |
| **readinessProbe** | **从 Service endpoints 摘除流量**（不重启） | 应用活着但没准备好接流量（加载缓存、预热中） |
| **startupProbe** | 成功之前屏蔽上两个探针 | 慢启动应用被 liveness 误杀 |

记忆方法：liveness 治"病"，readiness 治"没长大"，startup 治"慢热"。kubelet 视角的完整生命周期：Pod 走 Pending（等调度）→ ContainerCreating（拉镜像/建容器）→ Running；

容器崩溃则进入 CrashLoopBackOff 退避循环（10s→20s→40s…封顶 5min），由 kubelet 重启。

Running 期间三类探针各司其职——startup 成功前屏蔽另外两个，liveness 失败触发重启，readiness 失败只把 Pod 从 Service endpoints 摘除。

## Pitfalls & Q&A

踩坑清单：

- **requests 与 limits 的行为差异**：CPU 超限只是被 throttle（响应变慢），内存超限是直接 OOMKill（`RESTARTS` 增加且 `Last State: OOMKilled`）。
- **`containerPort` 只是声明**，不写也照样能通，它服务于文档和 Service 的 targetPort 提示。
- **探针参数**：`failureThreshold × periodSeconds` = 判定失败的最长容忍时间。示例里 startup 的 `30 × 2s = 60s`，给慢启动应用留了 1 分钟。

**Q1: CrashLoopBackOff 怎么排查？**
CrashLoopBackOff = 容器反复崩溃，kubelet 按指数退避重启。排查顺序：
1. `kubectl logs <pod> --previous` 看上一次崩溃的日志（最关键）
2. `kubectl describe pod` 看 `Last State`：`OOMKilled` → 调大 memory limits；`Error/Crash` → 应用自身问题
3. 检查 command/args 是否写错导致进程立即退出
4. 检查 liveness 探针是否配得太严（initialDelaySeconds 太短、端口/路径错误）导致"启动慢被杀"

**Q2: 什么时候该把多个容器放进一个 Pod，而不是分成两个 Pod？**

判断标准是"亲缘性"：需要共享网络（`localhost` 互访）、共享存储卷、同生共死的进程组合才进同一个 Pod（如 nginx + log-tailer）；可以独立扩缩容、独立发布的服务应该各占一个 Pod。反向例子是把 web 和数据库塞进一个 Pod——两者生命周期和扩缩需求完全不同，绑死后无法单独伸缩。
