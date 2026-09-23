# 02 · Pod：Kubernetes 的最小调度单元

> Pod 是 K8s 一切对象的原子：Deployment、Service、StatefulSet 都只是"管理 Pod 的不同方式"。把这个实验吃透，后面的事都是顺水推舟。

## What

Pod 是一组共享网络命名空间和存储卷的容器，同生共死、被调度到同一个节点上——K8s 不会单独调度某个容器，调度的原子单位永远是 Pod。一句话心智模型：**pause 提供共享底座，附加容器扩展能力边界，探针赋予自愈与流量治理。**

一个 Pod 的自然子部件：

| 部件 | 角色 |
|---|---|
| pause 容器 | 用户看不见的基础设施容器，持有 Pod 的网络/IPC 命名空间 |
| initContainer | 主容器启动前串行执行的一次性初始化容器 |
| sidecar | 与主容器并行长期运行的辅助容器（日志、代理） |
| 探针（probe） | kubelet 周期性执行的健康检查，驱动重启与摘流 |

## Why

刚从 Docker 转到 K8s 的人最容易问：为什么 K8s 不直接调度容器，而要发明一个 Pod？因为现实中的应用经常是"一组功能互补的进程"——主进程 + 日志收集 + 配置下发 + 网络代理。这些进程需要共享磁盘、用 `localhost` 互相通信、生命周期绑定在一起。Linux 里早就有这种分组思想（进程组），Pod 就是把它搬进了容器世界。

不看会怎样：没有这个调度原子，"主容器和它的日志收集器必须待在同一节点、一起重启、共享 IP"这类约束就要靠用户自己拼凑，调度器也无法把它们当作一个整体来放置和迁移。

## How

```bash
cd labs/02_pod
./pod.sh              # 一条龙：apply -> describe -> logs -> exec -> label -> 探针观察 -> 清理
./pod.sh demo-ns      # 也可以指定 namespace（默认 default）
```

脚本每步都会打印观察要点。跑完后用交互命令继续把玩：

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

## Deep Dive

**pause 容器（infrastructure container）**：每个 Pod 底层都有一个用户看不见的 `pause` 容器，它最先启动，作用是**持有 Pod 的网络（和 IPC）命名空间**，其余业务容器都加入它的命名空间。因此：

- 同一个 Pod 里所有容器共享同一个 IP、同一套端口空间
- 容器之间用 `localhost` 互访（不同容器不能占用同一端口）
- 主容器崩溃重启，Pod IP 不变（是 pause 在撑着网络）

pause 平时几乎不消耗资源。它的存在解释了 `kubectl get pod` 里看到的容器和节点上 `docker ps` 看到的容器"多一个"的现象。

**sidecar vs initContainer**：两者都是"在主容器之外附加容器"，但时机完全不同——

| | initContainer | sidecar |
|---|---|---|
| 执行时机 | 主容器启动**之前** | 与主容器**同时**运行 |
| 执行方式 | 串行，逐个执行 | 并行，长期运行 |
| 成功条件 | 必须 `exit 0` 才继续 | 无退出概念，跟随 Pod 生命周期 |
| 典型用途 | 等待依赖就绪、下载模型、初始化配置 | 日志收集、网络代理（Istio envoy）、数据同步 |

manifests 里的 `nginx-sidecar-pod` 演示了经典 sidecar：nginx 写日志到共享卷，busybox `tail -f` 实时读取，二者通过 `emptyDir` 卷看到同一份文件。

**三种探针的执行语义**：探针由 kubelet 周期性执行，类型可以是 `httpGet`、`tcpSocket` 或 `exec`。

| 探针 | 失败后果 | 解决什么问题 |
|---|---|---|
| **livenessProbe** | **重启容器** | 应用卡死、死锁——进程活着但不工作 |
| **readinessProbe** | **从 Service endpoints 摘除流量**（不重启） | 应用活着但没准备好接流量（加载缓存、预热中） |
| **startupProbe** | 成功之前屏蔽上两个探针 | 慢启动应用被 liveness 误杀 |

记忆方法：liveness 治"病"，readiness 治"没长大"，startup 治"慢热"。kubelet 视角的完整生命周期：Pod 走 Pending（等调度）→ ContainerCreating（拉镜像/建容器）→ Running；容器崩溃则进入 CrashLoopBackOff 退避循环（10s→20s→40s…封顶 5min），由 kubelet 重启。Running 期间三类探针各司其职——startup 成功前屏蔽另外两个，liveness 失败触发重启，readiness 失败只把 Pod 从 Service endpoints 摘除。

踩坑清单：

- **requests 与 limits 的行为差异**：CPU 超限只是被 throttle（响应变慢），内存超限是直接 OOMKill（`RESTARTS` 增加且 `Last State: OOMKilled`）。
- **`containerPort` 只是声明**，不写也照样能通，它服务于文档和 Service 的 targetPort 提示。
- **探针参数**：`failureThreshold × periodSeconds` = 判定失败的最长容忍时间。示例里 startup 的 `30 × 2s = 60s`，给慢启动应用留了 1 分钟。

## Q&A

**Q1: CrashLoopBackOff 怎么排查？**
CrashLoopBackOff = 容器反复崩溃，kubelet 按指数退避重启。排查顺序：
1. `kubectl logs <pod> --previous` 看上一次崩溃的日志（最关键）
2. `kubectl describe pod` 看 `Last State`：`OOMKilled` → 调大 memory limits；`Error/Crash` → 应用自身问题
3. 检查 command/args 是否写错导致进程立即退出
4. 检查 liveness 探针是否配得太严（initialDelaySeconds 太短、端口/路径错误）导致"启动慢被杀"

**Q2: 什么时候该把多个容器放进一个 Pod，而不是分成两个 Pod？**
判断标准是"亲缘性"：需要共享网络（`localhost` 互访）、共享存储卷、同生共死的进程组合才进同一个 Pod（如 nginx + log-tailer）；可以独立扩缩容、独立发布的服务应该各占一个 Pod。反向例子是把 web 和数据库塞进一个 Pod——两者生命周期和扩缩需求完全不同，绑死后无法单独伸缩。
