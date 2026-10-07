# CKA 全真模考 #1 · 试卷

> **时长 120 分钟 ｜ 16 题 ｜ 满分 100（按权重计分，66 及格）｜ 允许查 kubernetes.io**
> 考场纪律：每题先确认 context（题面已给）；先易后难，每题 7-8 分钟封顶；修完一题立刻做下一题。
> 重考方式：`bash setup.sh` 重置环境 → 闭卷作答 → `bash grade.sh` 判分（自动输出得分）。
> 参考解答：见同目录 `REPORT.md`（考完再看）。

| # | 域 | 权重 | Context | 题面 |
|:--|:---|:---:|:---|:---|
| T1 | 1 | 7% | kind-k8s-learn | 在 namespace `audit` 创建 ServiceAccount `scanner`；授予其在**该命名空间内** get/list Pods 的权限（用 Role+RoleBinding，不要越权）。用 `kubectl auth can-i` 验证：list 放行、delete 拒绝。 |
| T2 | 1 | 6% | 本机 shell | 将 `/tmp/exam/staging-config` 合并进 `/tmp/exam/config`（不要动真实 `~/.kube/config`），把新 context 重命名为 `staging` 并切换为当前；验证 `kubectl --kubeconfig /tmp/exam/config get nodes` 能列出节点。 |
| T3 | 1 | 5% | kind-k8s-learn | 对 namespace `secure` 启用 Pod Security Standard `baseline`（enforce+audit+warn 三模式）。验证：创建 `privileged: true` 的 Pod 被拒绝（dry-run 即可证明）。 |
| T4 | 1 | 7% | kind-k8s-learn | 节点维护：drain `k8s-learn-worker2`（忽略 DaemonSet 管理的 Pod），打标签 `disk=ssd`，加 taint `special=true:NoSchedule`，最后 uncordon 恢复调度。 |
| T5 | 2 | 5% | kind-k8s-learn | deployment `fe`（ns `apps`）已就绪：将其镜像更新为 `nginx:1.27`，策略 `maxSurge=1, maxUnavailable=0`，等 rollout 完成；然后回滚到上一版本。 |
| T6 | 2 | 5% | kind-k8s-learn | 在 ns `apps` 创建 ConfigMap `web-cfg`（键 `index_content=hello-cka`）与 Secret `web-sec`（`user=admin` / `pass=secret123`）；创建 Pod `web`：Secret 以 env 注入，ConfigMap 以卷挂载到 `/etc/cfg`。 |
| T7 | 2 | 5% | kind-k8s-learn | 创建两个 Pod（ns `apps`，镜像 busybox，sleep 3600）：`pinned` 用 `nodeName` 直派到 `k8s-learn-worker2`；`tolerant` 用 nodeSelector `disk=ssd` 且能容忍该节点的 taint（T4 遗留状态）。两者最终都应 Running 在 worker2 上。 |
| T8 | 3 | 6% | kind-k8s-learn | deployment `api2`（ns `apps`，容器监听 8080）已就绪：暴露为 ClusterIP `api-svc`（80→8080）与 NodePort `api-np`（nodePort 固定 30080）。验证集群内可达。 |
| T9 | 3 | 7% | kind-cka-netpol | ns `np-exam` 三个 Pod（api/client/other）已就绪：编写 NetworkPolicy 使 **默认拒绝全部 ingress**，仅放行 `app=client` 访问 `app=api` 的 TCP 80。验证：client 可达，other 被拒。 |
| T10 | 3 | 7% | kind-k8s-learn | 后端 `svc-a`/`svc-b`（ns `ing`）已就绪：创建 Ingress `exam-ing`（class nginx），host `a.exam.local` 的路径 `/a`（Prefix）→ `svc-a:80`，其余全部路径 → `svc-b:80`。验证：`curl -H "Host: a.exam.local" http://<节点IP>/a` 命中 a，`/` 命中 b。 |
| T11 | 4 | 5% | kind-k8s-learn | 创建静态 PV `exam-pv`（500Mi，hostPath `/mnt/exam`，RWO，Retain）与 PVC `exam-pvc`（ns `apps`，300Mi）完成绑定；Pod `pv-user` 挂载到 `/data` 并写入文件 `it-works.txt`（内容 `cka-pass`）。 |
| T12 | 4 | 5% | kind-k8s-learn | 创建 StorageClass `exam-fast`（provisioner 与现有默认相同）并设为集群默认；创建 PVC `dyn-pvc`（ns `apps`，1Gi，**不写** storageClassName）确认动态绑定到 exam-fast。 |
| T13 | 5 | 7% | kind-k8s-learn | ns `broken` 有四个故障 Pod（镜像错/命令错/调度约束错/内存限制过低）。诊断并修复全部四个，其他字段保持不变。 |
| T14 | 5 | 6% | kind-k8s-learn | ns `store` 的 PVC `data-claim` 一直 Pending（消费 Pod `store-user` 在场）。诊断并修复使其 Bound。 |
| T15 | 5 | 8% | kind-cka-netpol | ns `pay` 中 client 访问 `cache-svc` 超时（服务与 Pod 都在，故障不止一处）。系统性诊断并修复全部问题，直到 `wget http://cache-svc` 返回 `cache-ok`。 |
| T16 | 5 | 9% | kind-k8s-learn | ⚠️ 最后做（考官现场注入）：集群新建 Pod 全部永远 Pending。找出损坏的控制面组件并恢复，验证新 Pod 可正常调度。 |

**判分**：每题通过得满权重分、不通过得 0；`grade.sh` 自动输出逐题结果、总分与百分比。
**环境预置**：T13/T14/T15 的故障由 `setup.sh` 注入；T16 由考官在考生做到最后时执行 `bash examiner-t16.sh`。
