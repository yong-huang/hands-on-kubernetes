# 26 · 高级排障：Ephemeral Container 与 kubectl debug

> 最棘手的故障现场往往是这样：容器 CrashLoopBackOff 进不去 exec，镜像又是 distroless 连 shell 都没有，`kubectl logs` 只有半行堆栈。本实验刻意构造这种"黑盒"现场（`broken_pod.yaml`），练习 `kubectl debug` 的三种姿势——目标是掌握不重启、不改镜像、不影响线上的排障手段。

## What

`kubectl debug` 提供三种互不替代的调试姿势：

| 姿势 | 命令形态 | 适用 |
|------|---------|------|
| 注入临时容器 | `kubectl debug <pod> -it --image=... --target=app` | 活着或崩溃的容器都行，与目标容器共享命名空间 |
| 克隆 Pod 调试 | `kubectl debug <pod> --copy-to=... --sleep-forever` | 原 Pod 不动，复制一份带工具箱的克隆随便折腾 |
| 节点级调试 | `kubectl debug node/<node> -it --image=ubuntu` | 视角抬到宿主机，`chroot /host` 后怀疑 CNI/kubelet 时的唯一入口 |

一句话心智模型：**临时容器是 Pod 的"急诊室"**——它是加进 `spec.ephemeralContainers` 的特殊容器，与业务容器共享 network/IPC/UTS 命名空间（所以同 IP、能抓包），看完病就随 Pod 一起消失，不是修复手段而是诊断手段。

## Why

传统排障手段在"黑盒"现场全部失效：CrashLoopBackOff 的容器活不到 exec 那一刻；distroless 镜像没有 shell，进去了也没用；重启换 debug 镜像会破坏现场（崩溃次数、启动时序都是证据）。临时容器方案的价值在于**零侵入**——不改镜像、不重启、不重建，把工具箱"从外面递进去"。

## How

```bash
cd labs/26_ephemeral_debug
./debug.sh deploy   # 部署刻意的"黑盒"故障 Pod（distroless 风格）
./debug.sh debug    # 三种姿势依次演示
./debug.sh clean
```

三种姿势（`manifests/broken_pod.yaml` 配套）：

```bash
# 姿势1: 注入临时容器 —— 活着或崩溃的容器都行
kubectl debug broken-app -it --image=busybox:1.36 --target=app -- sh
# 姿势2: 克隆副本, 原 Pod 不动
kubectl debug broken-app --copy-to=broken-app-debug \
    --image=ubuntu --sleep-forever
# 姿势3: 节点层, chroot 宿主机
kubectl debug node/<node> -it --image=ubuntu
```

工具箱镜像的选择：nicolaka/netshoot 是网络诊断瑞士军刀（tcpdump/dig/mtr/nslookup），busybox 胜在轻量，ubuntu 适合 chroot 场景。原则：**调试镜像只出现在 ephemeralContainers 里**，绝不混进生产 Pod spec。

诚实预期（环境限制，如实说明）：

- kind 默认 CNI（kindnet）**不执行 NetworkPolicy**：本实验给 net-victim 配的 deny-egress 策略在本集群不会真正断网（nslookup 仍会成功）。想看到真实拦截需换 Calico 等策略执行型 CNI（见 lab 12 的说明与切换方法）。断网抓包姿势（netshoot）本身不受影响。
- containerd 上对**已退出**的容器使用 `--target` 会 CreateContainerError——这是真实世界的坑，脚本姿势 1a 会现场演示；CrashLoop 的正确入口是 logs/describe 或姿势 2 的 `--copy-to` 克隆。

## Deep Dive

**`--target`：共享 PID 命名空间是关键**。默认各容器 PID 隔离，加了 `--target=app` 后调试容器加入目标容器的 PID ns：

```text
app 容器:   PID 1 = /broken-binary (崩溃)
debugger:   ps aux 可见 PID 1 -> /proc/1/root/ 即对方根文件系统
```

这样才能看到它的进程、读 `/proc/<pid>/root` 下的文件、甚至 gdb attach。不加 target 时你只是在一个空壳里装忙。

**临时容器的边界**：与业务容器共享 network/IPC/UTS 命名空间，但**不能声明 ports/probes/lifecycle/resources**（env 是允许的）、不能重启——K8s 把它严格限制在"诊断"语义内，防止它变成第二套工作负载。

**三种姿势的战场**：姿势 1 覆盖大多数场景（运行中容器直接查）；姿势 2 解决"探针互斥"问题——有些故障一 attach 就消失（heisenbug），复制一份克隆随便折腾；姿势 3 把视角抬到宿主机，`chroot /host` 后 systemctl/journalctl/ipvsadm 全套可用。选择顺序：先姿势 1（最快），探针敏感换姿势 2，怀疑基础设施升姿势 3。

踩坑清单：

- 姿势 1 的 `--target` 对已退出的容器在 containerd 上直接报 CreateContainerError——崩溃容器走姿势 2
- 忘写 `--target` 是最常见的"调试无效"原因：工具箱容器起来了，但 PID 隔离让你什么都看不见
- 调试镜像写进生产 Pod spec（哪怕注释掉）会跟着发布走——临时容器只在 ephemeralContainers 里

## Q&A

**Q1: 共享 PID 之后还能做什么？**
strace/gdb：对 PID 1 执行 `strace -p` 系统调用追踪，定位 hang 死点卡在哪个 syscall；gdb attach 后可以看崩溃进程的内存现场。这是"distroless 黑盒"场景里唯一能拿到函数级证据的手段。

**Q2: 不想动目标容器还有什么更底层的手段？**
eBPF 升级版：kubectl-trace / inspektor-gadget 在内核态观察，无需目标镜像配合、无需共享 PID——内核态的视角天然覆盖节点上所有容器，代价是工具链更重。

**Q3: 这些调试流程能自动化吗？**
可以。把常见 debug 流程写成脚本/Operator，故障时自动注入采集器（网络抓包、/proc 快照）再通知人——人在介入时证据已经采集完毕，特别适合复现率低的故障。

**Q4: 谁都能往生产 Pod 里注入容器吗？**
不应该。ephemeralcontainers subresource 的写权限要单独 RBAC 控制（见 lab 19）——注入的临时容器与业务容器共享网络和 PID 命名空间，等于拿到了生产容器的同等视野，权限必须收敛到排障角色。
