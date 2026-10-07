# 🎓 CKA 认证备考 32 小项目学习清单 · Todo List（30 道真题专项 + 2 次全真模考）

> 通过 32 个小项目（每项目 = 一道考场风格真题，10-60 分钟实操）覆盖 CKA 五大考纲域，拿下认证
> 环境约束：本机 kind（已就绪 5 个集群）+ killercoda 免费在线 kubeadm 环境，全程零云成本
> 串联机制：考点驱动型——每条高频考纲细目对应一个可跑真题项目，末尾 2 个 ⛓️ 全真模考把全部考点串成整场考试
> 预计周期：6 周（每天 1-2 小时）

**考试事实速览**（2026 年，报名前以 Linux Foundation FAQ 复核）：

| 项目 | 内容 |
|:---|:---|
| 考试环境版本 | Kubernetes v1.34/v1.35（随最新 minor 滚动，报名时确认） |
| 时长 / 题量 | 2 小时 / 15-20 道实操题（多套预配置集群，**每题指定 context，先切对集群**） |
| 及格线 / 费用 | 66% / $445（含一次免费重考 + 2 次 killer.sh 官方模拟环境） |
| 允许的资料 | 仅 kubernetes.io 官方文档、Kubernetes Blog、Helm/Gateway API 文档、`/usr/share` 预置内容 |
| 考场丢分点 | ① 没切到题目指定的 context；② YAML 写完忘 `kubectl apply`；③ 时间耗在难题上（先做会的，平均 7 分钟/题）；④ 手写 YAML 而不是先查官方文档抄模板 |

---

## 🎯 考纲 → 项目速查表

| 考纲域（权重） | 考纲细目 | 对应项目 |
|:---|:---|:---:|
| **域 1** 集群架构、安装与配置（25%） | kubeadm 安装集群（init/join） | 1 |
| | kubeadm 版本升级 | 2 |
| | etcd 备份与恢复 | 3 |
| | RBAC（Role/Binding/ServiceAccount） | 4 |
| | kubeconfig 与多集群上下文 | 5 |
| | 节点管理与维护（cordon/drain/taint/标签） | 6 |
| | Pod Security Admission 集群加固 | 7 |
| **域 2** 工作负载与调度（15%） | Deployment 滚动更新与回滚 | 8 |
| | 应用伸缩与资源限制对调度的影响 | 9 |
| | ConfigMap / Secret 配置管理 | 10 |
| | 健壮自愈部署（探针/restartPolicy） | 11 |
| | 定向调度（nodeName/taint/toleration/affinity） | 12 |
| **域 3** 服务与网络（20%） | Service 各类型与 expose | 13 |
| | Endpoints/EndpointSlice 与 selector 绑定 | 14 |
| | Ingress 规则与控制器 | 15 |
| | NetworkPolicy 默认拒绝与放行 | 16 |
| | CoreDNS 与服务发现 | 17 |
| | Gateway API（HTTPRoute/Gateway） | 18 |
| **域 4** 存储（10%） | PV/PVC 静态绑定与挂载 | 19 |
| | StorageClass 动态供给 | 20 |
| | PVC 排障与卷快照 | 21 |
| **域 5** 排障（30%） | 应用故障四态（CrashLoop/ImagePull/Pending/OOM） | 22 |
| | 无效 YAML spec 排错 | 23 |
| | Service 不通全链路排查 | 24 |
| | DNS 故障排查 | 25 |
| | 节点故障（kubelet/containerd → NotReady） | 26 |
| | 控制面组件故障 | 27 |
| | 静态 Pod 管理与修复 | 28 |
| | 日志、事件与监控排障 | 29 |
| | 综合限时排障（多故障注入） | 30 |
| **整场串联** | 全真模考 #1 / #2 | 31、32 |

## 🤖 AI 辅助提示词速查

| 场景 | 提示词 |
|:---|:---|
| **开始一个真题项目** | `我要备考 CKA，练「项目 [N]：[名称]」。请在 kind 集群 k8s-learn（或 killercoda）上出题并给完整题解：考场最佳实践写法（imperative 命令优先、能查 kubernetes.io 就不手写）、验收断言命令、常见丢分点。目标 [x] 分钟内完成。只输出命令与 YAML。` |
| **生成故障注入环境** | `请给我一个 bash 脚本，在 kind 集群 k8s-learn 上注入以下故障：[故障列表]，并配套一个 verify.sh 逐项断言修复结果。只输出脚本。` |
| **模考判卷** | `这是我的 CKA 模考答卷记录（kubectl 命令历史 + 最终 get 输出）：[粘贴]。请按考场评分标准逐题判分，给出每题得分、丢分原因和重练建议。` |
| **排障教练** | `我的集群出现 [现象]，以下是 describe/logs/events 输出：[粘贴]。请按 CKA 排障方法论（事件→日志→spec→组件）引导我定位，不要直接给答案。` |

## 📊 总进度

进度：░░░░░░░░░░░░░░░░░░░░ 0/32 (0%)

| 阶段 | 项目数 | 已完成 |
|:---|:---:|:---:|
| 第一阶段：集群架构、安装与配置（域 1 · 25%） | 7 | 0 |
| 第二阶段：工作负载与调度（域 2 · 15%） | 5 | 0 |
| 第三阶段：服务与网络（域 3 · 20%） | 6 | 0 |
| 第四阶段：存储（域 4 · 10%） | 3 | 0 |
| 第五阶段：排障（域 5 · 30%） | 9 | 0 |
| 第六阶段：全真模考 | 2 | 0 |
| **合计** | **32** | **0** |

---

## 🗂️ 第一阶段：集群架构、安装与配置（项目 1-7，考纲域 1 · 25%）

> **目标**：能在真实 kubeadm 集群上安装、升级、备份恢复、授权与加固——这是 kind 练不了、必须去 killercoda 的 25%

### [ ] 项目 1：kubeadm 从零安装集群

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~25 条命令 |
| **核心知识点** | `kubeadm init/join`、容器运行时前置、Pod CIDR、CNI 安装、控制面组件就绪顺序 |
| **覆盖考纲** | 域 1：「Use Kubeadm to install a basic cluster」 |
| **环境** | lima VM `cka-vm`（真机 kubeadm ✅ 已建成：v1.33.13 + flannel Ready；killercoda 备用） |
| **⏱️ 目标用时** | 20 分钟 |
| **验收标准** | `kubectl get nodes` 全部 Ready 且 CNI 就绪；`kubectl run net --image=busybox --restart=Never -- rm -v` 跨节点网络连通 |

> **📝 模拟真题**：
> `Task:` Using kubeadm, bootstrap a single control-plane cluster on node `cp1` with Pod CIDR `10.244.0.0/16`, then install a CNI plugin of your choice and join node `worker1`. (Weight: 10%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 1：kubeadm 从零安装集群」。请给 killercoda 双节点环境（Ubuntu + containerd）的完整 kubeadm init/join 步骤：前置检查、kubeadm init --pod-network-cidr、kubelet 开机自启、CNI 安装、join 命令拼接、常见报错速查。附验收命令。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/01-kubeadm-install.md](cka-drills/01-kubeadm-install.md)（**lima 真机全流程实测**：kubeadm init + flannel Ready；五大 30 分钟级踩坑——--plain、镜像离线导入、pause tag 不匹配、distroless etcd、VM 自停，2026-10-07；先闭卷自测再对照）

**🔥 首次开工探活脚本**（进 killercoda 终端先跑，结果回填文末探活表）：

```bash
whoami; kubectl get nodes -o wide 2>/dev/null | head -5
kubectl version --client=false 2>/dev/null | grep -i server
sudo -n true && echo "sudo: 免密可用" || echo "sudo: 不可用"
systemctl is-active kubelet 2>/dev/null || echo "systemd: 不可用"
curl -sI https://pkgs.k8s.io 2>/dev/null | head -1 || echo "kubeadm apt 源: 不可达"
```

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 2：kubeadm 集群版本升级

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~15 条命令 |
| **核心知识点** | `kubeadm upgrade plan/apply`、kubelet 与 kubeadm 二进制升级、drain/uncordon、`--ignore-preflight-errors` |
| **覆盖考纲** | 域 1：「Perform a version upgrade on a Kubernetes cluster using Kubeadm」 |
| **环境** | lima VM `cka-vm` ✅（v1.33.13 → **v1.34.12 真机升级已完成**，集群现役即 v1.34.12） |
| **⏱️ 目标用时** | 15 分钟（考场流程）/ 40 分钟（离线环境全坑版） |
| **⚠️ 风险** | 离线镜像必须预导 + `ctr images check` 逐个验 true；apply 前先 uncordon（健康检查 Job 要调度）；kubeadm 中途回滚会留下混合态，破局=手动冲完 |
| **验收标准** | `kubectl get nodes` 显示新版本；`kubectl get pods -n kube-system` 全部 Running；节点 uncordon 后可调度 |

> **📝 模拟真题**：
> `Task:` Upgrade the control-plane node `cp1` from its current version to the next available minor release using kubeadm. Drain `cp1` before upgrading and uncordon it afterwards. Do not upgrade the worker node. (Weight: 10%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 2：kubeadm 集群版本升级」。请给完整升级流程：kubeadm upgrade plan、drain、apt 安装新版本 kubeadm/kubelet/kubectl、kubeadm upgrade apply v1.3x.x、kubelet daemon-reload 与 restart、uncordon。说明控制面与 worker 升级差异、etcd 不会被动升级的原因。附逐条验收命令。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/02-kubeadm-upgrade.md](cka-drills/02-kubeadm-upgrade.md)（**真机 v1.33.13→v1.34.12 升级完成**：考场 20 分钟标准流程 + 离线环境六坑实录——镜像 check 验 true、apply 前 uncordon、混合态手动冲完、控制面 taint 摘除，2026-10-07；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 3：etcd 备份与恢复

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~12 条命令 |
| **核心知识点** | `etcdctl snapshot save/restore`、证书三件套（cacert/cert/key）、endpoint、静态 pod 数据目录、恢复后重建 manifest |
| **覆盖考纲** | 域 1：「Implement etcd backup and restore」 |
| **环境** | kind（etcd 是控制面容器内静态 pod）⚠️ 恢复环节开工探活；killercoda 备用 |
| **⏱️ 目标用时** | 15 分钟 |
| **⚠️ 风险** | kind 内快照保存大概率可行；恢复需挪动静态 pod manifest 与数据目录，若受限转 killercoda 的 etcd 场景练习 |
| **验收标准** | `etcdctl snapshot status` 显示合法快照；恢复演练后 `kubectl get ns` 能回到备份时点的资源状态 |

> **📝 模拟真题**：
> `Task:` Create a snapshot of the etcd instance running at `https://127.0.0.1:2379`, saving it to `/srv/backup/etcd-snapshot.db`. Then, restoring from a previously taken snapshot located at `/srv/backup/etcd-previous.db`. (Weight: 5%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 3：etcd 备份与恢复」。请给完整题解：在 kind 控制面节点上用 etcdctl snapshot save（ETCDCTL_API=3、--endpoints、--cacert/--cert/--key 指向 /etc/kubernetes/pki/etcd），snapshot status 校验；再演示 snapshot restore 到新数据目录并让 etcd 以恢复后数据重启（静态 pod manifest 操作）。附每步验收断言与考场记忆口诀。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/03-etcd-backup-restore.md](cka-drills/03-etcd-backup-restore.md)（**真机完整恢复演练**：快照→造差量→restore→回滚时点验证全过；三大坑——manifest 要改三处含 mountPath、apiserver 缓存需强制重启、诊断顺序，2026-10-07；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 4：RBAC 最小权限配置

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~15 行 YAML / 6 条命令 |
| **核心知识点** | ServiceAccount、Role/RoleBinding vs ClusterRole/ClusterRoleBinding、verbs、`kubectl auth can-i --as` 模拟鉴权 |
| **覆盖考纲** | 域 1：「Manage role based access control (RBAC)」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | `kubectl auth can-i create deployments --as=system:serviceaccount:build:cicd -n build` 输出 yes；同一 SA 在 default 命名空间输出 no |

> **📝 模拟真题**：
> `Task:` Create a new ServiceAccount named `cicd` in namespace `build`. Grant this ServiceAccount permission to create and patch Deployments in namespace `build` only. Verify the permission using `kubectl auth can-i`. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 4：RBAC 最小权限配置」。请给考场最佳实践题解：kubectl create ns/SA 的 imperative 写法、Role 限定 verbs=create,patch + resources=deployments、RoleBinding 绑定，最后用 kubectl auth can-i --as 模拟验证「本空间放行、跨空间拒绝」。附常见丢分点（apiGroup 写错、绑错命名空间）。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/04-rbac.md](cka-drills/04-rbac.md)（题解已实测，验收矩阵 6/6 通过，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 5：kubeconfig 与多集群上下文管理

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~10 条命令 |
| **核心知识点** | context/cluster/user 三元组、`kubectl config` 子命令、kubeconfig 合并、`--kubeconfig` 覆盖 |
| **覆盖考纲** | 域 1：「Manage kubeconfig across multiple clusters」 |
| **环境** | kind（本机已有 5 个 kind 集群，天然多集群素材 ✅ 实测在位） |
| **⏱️ 目标用时** | 6 分钟 |
| **验收标准** | `kubectl config get-contexts` 出现自定义命名的 context；`kubectl config current-context` 切换后 `kubectl get nodes` 指向对应集群 |

> **📝 模拟真题**：
> `Task:` Merge the kubeconfig located at `/root/staging-config` into your default kubeconfig. Rename the new context to `staging` and switch to it. Confirm you can list nodes of the staging cluster. (Weight: 3%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 5：kubeconfig 多集群上下文管理」。请用本机现有 kind 集群（kind-k8s-learn、kind-ai-infra 等）出题并给题解：用 KUBECONFIG 环境变量合并两份 kubeconfig、kubectl config rename-context、use-context、set-context 改默认 namespace，并演示 --kubeconfig 临时指定。附验收命令与考场细节（每题先看是否指定 context）。只输出命令。`

**📦 开工包**：[docs/cka-drills/05-kubeconfig.md](cka-drills/05-kubeconfig.md)（/tmp 沙箱实测通过，真实 kubeconfig 零改动，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 6：节点维护——cordon、drain 与 taint

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~10 条命令 |
| **核心知识点** | cordon/uncordon、drain 与 DaemonSet 容忍、`--ignore-daemonsets`、节点标签与 taint 语义（NoSchedule/PreferNoSchedule/NoExecute） |
| **覆盖考纲** | 域 1：节点管理维护（kubeadm 集群节点操作）；域 2：taints and tolerations |
| **环境** | kind k8s-learn（3 节点，drain→taint→uncordon 全流程实测可行 ✅）；killercoda 备用 |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | `kubectl get nodes` worker 显示 `SchedulingDisabled`；worker 上除 DaemonSet 外 Pod 数为 0；taint 生效使无容忍 Pod 无法调度 |

> **📝 模拟真题**：
> `Task:` Prepare node `worker1` for maintenance: drain it ignoring DaemonSet-managed pods, then add label `disk=ssd` and taint `maintenance=true:NoSchedule`. After maintenance, uncordon the node. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 6：节点维护 cordon/drain/taint」。请给完整题解与讲解：drain 的内部动作（cordon+evict）、为什么必须 --ignore-daemonsets、taint effect 三种语义区别、Pod tolerations 配对写法。在 killercoda 双节点上实操，附验收断言（SchedulingDisabled、worker 上无业务 pod、taint 拒绝调度）。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/06-node-maintenance.md](cka-drills/06-node-maintenance.md)（kind 3 节点实测全流程通过，含 cordon vs taint 陷阱实录，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 7：Pod Security Admission 命名空间加固

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~8 行 label / 4 条命令 |
| **核心知识点** | Pod Security Standards（privileged/baseline/restricted）、namespace labels 三模式（enforce/audit/warn）、拒绝现象解读 |
| **覆盖考纲** | 域 1：集群加固（Pod Security Admission，kubeadm 集群默认开启） |
| **环境** | kind（k8s-learn，v1.25+ 内置 PSA） |
| **⏱️ 目标用时** | 6 分钟 |
| **前置** | 本仓库 labs/20_pod_security（复习用，真题版不依赖） |
| **验收标准** | 给 `apps` 命名空间打 enforce=baseline 标签后，创建 `privileged: true` 的 Pod 被 apiserver 拒绝并给出 PSA 原因文案；非特权 Pod 正常创建 |

> **📝 模拟真题**：
> `Task:` Enforce the Pod Security Standard `baseline` on namespace `apps` (enforce mode, warn and audit also enabled). Verify that a pod with `privileged: true` is rejected. (Weight: 3%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 7：PSA 命名空间加固」。请给题解：kubectl label ns apps pod-security.kubernetes.io/enforce=baseline（+audit/warn），构造一个 privileged busybox Pod 验证被拒、一个普通 Pod 验证放行；解释 enforce/audit/warn 三模式差异与报错信息里怎么读出违规字段。附验收断言。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/07-psa.md](cka-drills/07-psa.md)（三模式实测，Forbidden 原文与 warn 四条违规已存档，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第二阶段：工作负载与调度（项目 8-12，考纲域 2 · 15%）

> **目标**：部署、伸缩、配置注入、自愈与定向调度全部肌肉记忆化，任何一题 8 分钟内闭卷完成

### [ ] 项目 8：Deployment 滚动更新与回滚

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~20 行 YAML / 8 条命令 |
| **核心知识点** | `kubectl rollout`、maxSurge/maxUnavailable、revision 历史、`rollout undo --to-revision`、`rollout status --timeout` |
| **覆盖考纲** | 域 2：「Understand deployments and how to perform rolling update and roll backs」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | `kubectl rollout status deploy/api` 完成且镜像为新版本；`rollout undo --to-revision=1` 后镜像回退；`rollout history` 至少 2 个 revision |

> **📝 模拟真题**：
> `Task:` Update deployment `api` in namespace `apps` to image `nginx:1.27` with `maxSurge=1, maxUnavailable=0`. Wait for the rollout to finish. Then roll back to the previous revision. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 8：滚动更新与回滚」。请给题解：set image + patch strategy（RollingUpdate 参数两种改法：kubectl patch 与 kubectl edit）、rollout status --timeout 用法、undo --to-revision，并讲清 maxSurge/maxUnavailable 在更新速率上的表现差异。附验收断言。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/08-rolling-update.md](cka-drills/08-rolling-update.md)（实测踩坑：容器名≠Deployment 名导致升级静默失败，通配符 `*=` 修正，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 9：应用伸缩与资源限制对调度的影响

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~15 行 YAML / 5 条命令 |
| **核心知识点** | `kubectl scale`、requests/limits 与节点可分配、FailedScheduling 事件解读（Insufficient cpu）、LimitRange 观念 |
| **覆盖考纲** | 域 2：「Know how to scale applications」「Understand how resource limits can affect Pod scheduling」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | `kubectl scale` 后 `kubectl get deploy web` 达到 5/5；构造 requests=4 CPU 的 Pod 处于 Pending，且 `kubectl describe pod` 事件含 `Insufficient cpu` |

> **📝 模拟真题**：
> `Task:` Scale deployment `web` in namespace `apps` to 5 replicas. Then create a pod `heavy` with a CPU request of `4` — it should stay Pending. Explain why by inspecting its scheduling events. (Weight: 3%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 9：伸缩与资源调度」。请给题解：kubectl scale、用 kubectl get nodes -o wide / kubectl describe node 看 Allocatable 与 Allocated resources、构造 Insufficient cpu 的 Pending 案例并用 describe 读事件定位。附验收断言与考场读事件的关键词清单。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/09-scale-resources.md](cka-drills/09-scale-resources.md)（本机 18 核节点用 64 CPU 复现 Insufficient cpu；含 force-delete 参数互斥坑，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 10：ConfigMap 与 Secret 配置注入

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~35 行 YAML / 8 条命令 |
| **核心知识点** | `kubectl create configmap/secret`（literal/file/dry-run）、env 注入 vs volume 挂载、`stringData` vs `data`、TLS Secret、immutable |
| **覆盖考纲** | 域 2：「Use ConfigMaps and Secrets to manage application configuration」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | Pod 内 `env` 读到注入变量；挂载路径出现 ConfigMap 文件内容；Secret 以 base64 存储且 Pod 内挂载为明文文件；TLS Secret 可被 Ingress 引用 |

> **📝 模拟真题**：
> `Task:` Create a ConfigMap `app-config` containing key `APP_MODE=prod`, and a Secret `db-cred` with keys `user=admin, pass=secret123`. Inject the ConfigMap as a volume at `/etc/conf` and the Secret as env vars into a new pod `app` in namespace `apps`. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 10：ConfigMap/Secret 注入」。请给题解：create configmap --from-literal、create secret generic 与 tls 型、Pod spec 里 envFrom/env valueFrom 与 volumes 的四种注入写法、验证命令（kubectl exec env + cat 文件）。附常见丢分点（secretKeyRef 写成 configMapKeyRef、mountPath 忘记）。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/10-config-injection.md](cka-drills/10-config-injection.md)（envFrom/volume 双路径实测取证，base64≠加密等 5 个知识考点，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 11：探针配置与自愈验证

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行 YAML / 6 条命令 |
| **核心知识点** | liveness/readiness/startupProbe 三者职责、initialDelay/period/failureThreshold 调参、重启计数观测 |
| **覆盖考纲** | 域 2：「Understand the primitives used to create robust, self-healing application deployments」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | Pod READY 1/1 且探针字段生效；人为让 /healthz 返回 500 后，`kubectl get pod` 重启次数增加且容器被 liveness 杀掉重建 |

> **📝 模拟真题**：
> `Task:` Add a liveness probe (HTTP GET `/healthz`, port 80, initialDelay 10, period 5) and a readiness probe (HTTP GET `/ready`, port 80) to deployment `api`. Verify that killing the health endpoint causes the container to restart. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 11：探针与自愈」。请给题解：三种探针的职责差异与 yaml 片段、如何用 nginx + 自定义 /healthz 脚本演示 liveness 失败触发重启（RESTARTS 计数上涨）、readiness 失败时 Endpoints 摘除现象。附验收断言与调参丢分点（initialDelay 过短导致误杀）。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/11-probes.md](cka-drills/11-probes.md)（busybox httpd 可控探针实测：404×3 → Killing → RESTARTS 1 → 自愈，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 12：定向调度——nodeName、taint/toleration 与 affinity

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML / 6 条命令 |
| **核心知识点** | `nodeName` 直派、nodeSelector、nodeAffinity（required/preferred）、podAntiAffinity、taint/toleration 组合 |
| **覆盖考纲** | 域 2：「Node selectors, affinity, anti-affinity, taints and tolerations」 |
| **环境** | kind（k8s-learn 多节点） |
| **⏱️ 目标用时** | 12 分钟 |
| **验收标准** | 三种方式各产出一个 Pod 且 `kubectl get pod -o wide` 显示落在指定节点；带 NoSchedule taint 的节点只运行带容忍的 Pod |

> **📝 模拟真题**：
> `Task:` Schedule a pod `fixed` onto node `worker2` directly via `nodeName`. Create another pod `flexible` that lands on any node labeled `disk=ssd`, preferring `zone=east`. Give `worker2` taint `special=true:NoSchedule` and ensure only `fixed` can tolerate it. (Weight: 5%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 12：定向调度」。请给题解：nodeName 与 nodeSelector/nodeAffinity 的区别（绕过调度器 vs 走调度器）、requiredDuringSchedulingIgnoredDuringExecution 模板、taint+toleration 配对（operator: Equal/Exists）、验证落点的 kubectl 命令。附三种场景完整 YAML 与验收断言。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/12-scheduling.md](cka-drills/12-scheduling.md)（三路落点实测全过 + YAML 1.1「Norway 问题」踩坑实录，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第三阶段：服务与网络（项目 13-18，考纲域 3 · 20%）

> **目标**：从 Service 到 Ingress 到 NetworkPolicy 到 Gateway API，把「流量如何进出集群」变成条件反射

### [ ] 项目 13：Service 各类型与 kubectl expose

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~25 行 YAML / 8 条命令 |
| **核心知识点** | ClusterIP/NodePort/Headless/ExternalName、`kubectl expose`、port vs targetPort vs nodePort |
| **覆盖考纲** | 域 3：「Provide and troubleshoot access to applications via services」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | ClusterIP 在集群内 curl 通；NodePort 从宿主机 `curl nodeIP:30080` 通；Headless Service 解析出 Pod IP 列表 |

> **📝 模拟真题**：
> `Task:` Expose deployment `backend` (port 8080) as a ClusterIP Service `backend-svc` on port 80. Expose deployment `web` as a NodePort Service `web-svc` on nodePort 30080. Verify both from inside and outside the cluster. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 13：Service 与 expose」。请给题解：kubectl expose 两条命令（ClusterIP 与 NodePort --port/--target-port/--node-port）、集群内验证（busybox wget）与宿主机验证（nodeIP:nodePort）、Headless（clusterIP: None）解析行为。附 port/targetPort/nodePort 三者关系图解与验收断言。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/13-services.md](cka-drills/13-services.md)（ClusterIP/NodePort/Headless 三型双路验证全过，含 OrbStack 网段直连备注，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 14：Endpoints 排查与 selector 修复

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~5 条命令 / 1 处修复 |
| **核心知识点** | Endpoints/EndpointSlice 生成条件、label selector 匹配、`kubectl get ep` 排障第一现场 |
| **覆盖考纲** | 域 3：「Endpoints and EndpointSlices; selector-to-pod binding」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 6 分钟 |
| **验收标准** | 修复前 `kubectl get ep api` 显示 `<none>`；修复后显示 Pod IP，且 `kubectl exec` 验证 Service 可访问 |

> **📝 模拟真题**：
> `Task:` Deployment `api` is running 3 ready pods, but Service `api` has no endpoints and is unreachable. Find the root cause and fix it. Do not modify the deployment. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 14：Endpoints 排障」。请生成一个故障环境（Service selector 与 Pod label 不匹配的完整 YAML）并给题解：排障路径 kubectl get ep → describe svc 看 selector → get pod --show-labels 对比 → 修 selector。附为什么「不改 deployment」意味着改 Service 的思考过程与验收断言。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/14-endpoints.md](cka-drills/14-endpoints.md)（selector 失配排障实测 + v1.33 EndpointSlice 新考情，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 15：Ingress 路由规则配置

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~25 行 YAML / 6 条命令 |
| **核心知识点** | Ingress host/path 路由、pathType（Prefix/Exact/ImplementationSpecific）、defaultBackend、ingressClassName |
| **覆盖考纲** | 域 3：「Use Ingress rules to expose applications」 |
| **环境** | kind（k8s-learn，ingress-nginx 已预装 ✅ hostPort 80/443 模式，labs/11 缓存清单可复用） |
| **⏱️ 目标用时** | 10 分钟 |
| **前置** | labs/11_ingress 的缓存清单（controller 已预装则无需） |
| **验收标准** | `curl -H "Host: app.example.com" http://127.0.0.1/` 走默认后端；同 Host 的 `/api` 路径返回 api 服务响应；`kubectl describe ingress` 规则正确 |

> **📝 模拟真题**：
> `Task:` Create an Ingress `app-ingress` in namespace `apps` for host `app.example.com`: path `/api` (Prefix) routes to service `api` on port 80, all other paths route to service `web` on port 80. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 15：Ingress 路由」。请给题解：两个 path 规则 + defaultBackend 的完整 Ingress YAML（ingressClassName: nginx、pathType: Prefix）、/api 与 / 的优先级原理、curl -H Host 验证。附考场上忘装控制器时的现象识别（External IP 一直 pending）。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/15-ingress.md](cka-drills/15-ingress.md)（四路验收全过 + 「三层 404 判别法」+ rewrite-target 实测，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 16：NetworkPolicy 默认拒绝与精准放行

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~45 行 YAML / 8 条命令 |
| **核心知识点** | ingress/egress 双向默认拒绝、podSelector/policyTypes、namespaceSelector、端口级放行、DNS 例外（UDP 53） |
| **覆盖考纲** | 域 3：「Demonstrate basic understanding of NetworkPolicies」 |
| **环境** | 独立 kind 集群 `cka-netpol`（Calico 执行策略 ✅ 已搭好并保留；重建命令见开工包） |
| **⏱️ 目标用时** | 15 分钟 |
| **前置** | docs/cka-drills/16-networkpolicy.md 末尾的靶场重建命令（当前无需） |
| **⚠️ 风险** | GitHub raw 被墙（CRD 走 gh-proxy 镜像）；新版 Calico chart 需 `--set whisker.enabled=false`；`kind load` 在 containerd 2.x 有 digest bug，用 `docker save \| ctr import` |
| **验收标准** | 默认拒绝后未放行 Pod `wget -T 2` 超时；放行 Pod 返回 200；放行规则之外的其他命名空间 Pod 不可达 |

> **📝 模拟真题**：
> `Task:` In namespace `netpol`, first deny all ingress and egress traffic. Then allow: (a) pods with label `role=frontend` to reach pods `role=backend` on TCP 80; (b) backend pods to perform DNS lookups (UDP/TCP 53 to kube-system). Verify with wget from allowed and denied pods. (Weight: 7%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 16：NetworkPolicy」。请给题解：default-deny（空 podSelector + policyTypes 全开）、两条放行策略（podSelector+port、namespaceSelector+端口 53 双协议）共 3 个 YAML，讲解「策略叠加取并集」语义，busybox wget -T 2 正反验证命令。附 NP 考题五大丢分点。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/16-networkpolicy.md](cka-drills/16-networkpolicy.md)（cka-netpol 靶场已保留可随时重练；含「bad address vs timeout 两种死法」判别法与靶场完整重建命令，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 17：CoreDNS 服务发现与域名解析

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~15 行 YAML / 6 条命令 |
| **核心知识点** | Headless Service A 记录、FQDN 格式 `<svc>.<ns>.svc.cluster.local`、`nslookup`/`dig` 验证、`resolv.conf` 的 search 域 |
| **覆盖考纲** | 域 3：「CoreDNS: DNS name construction and basic troubleshooting」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | busybox Pod 内 `nslookup` 短名与 FQDN 均解析成功；Headless Service 解析返回全部 Pod IP |

> **📝 模拟真题**：
> `Task:` Create a Headless Service `db-hl` for pods labeled `app=db`. From a temporary busybox pod, resolve both the short name and the full FQDN of the service and of individual pods. Save the DNS record output to `/root/dns-report.txt`. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 17：CoreDNS 服务发现」。请给题解：Headless Service 创建、busybox nslookup 验证短名/FQDN/pod 域名（pod-ip-横线形式）、容器内 /etc/resolv.conf 的 nameserver 与 search 域解读。附考场 DNS 速记表（谁解析成什么）。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/17-coredns.md](cka-drills/17-coredns.md)（四种解析实测全过 + ndots:5 踩坑实录，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 18：Gateway API HTTPRoute 实战

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML / 8 条命令 |
| **核心知识点** | GatewayClass/Gateway/HTTPRoute 三层对象、attachment 机制、hostname+path 匹配、与 Ingress 的职责分离 |
| **覆盖考纲** | 域 3：「Gateway API: HTTPRoute, GatewayClass, Gateway objects」（v1.35 考纲新增项） |
| **环境** | kind（k8s-learn，需安装 Gateway API CRD + 实现，labs/33 已有全部材料） |
| **⏱️ 目标用时** | 12 分钟 |
| **前置** | labs/33_gateway_api（新集群安装用；k8s-learn 已预装 EG ✅） |
| **⚠️ 风险** | 考纲新域，考题形式尚未稳定；kind 下 LB pending 导致 Gateway Programmed=False 属环境现象，验证走代理 svc 的 nodePort 且只能打代理所在节点 |
| **验收标准** | `kubectl get gateway` 显示 Programmed/Ready；`curl -H "Host: api.example.com"` 经 Gateway 地址命中 HTTPRoute 指定后端 |

> **📝 模拟真题**：
> `Task:` Using Gateway API, create a Gateway `prod-gw` (class from the installed GatewayClass) listening on port 80, and an HTTPRoute `api-route` for host `api.example.com` routing path `/v1` to service `api-v1` on port 8080. Verify with curl through the Gateway address. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 18：Gateway API」。请基于 labs/33 已装好的 Envoy Gateway 栈出题并给题解：Gateway + HTTPRoute 完整 YAML、route 如何 attach 到 gateway（parentRefs）、curl 验证链路、与 Ingress 对象模型的差异一句话。附验收断言。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/18-gateway-api.md](cka-drills/18-gateway-api.md)（实测 4 个考场级知识点：EG 代理位置、kind 下 AddressNotAssigned、externalTrafficPolicy Local 丢包、xDS 传播延迟，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第四阶段：存储（项目 19-21，考纲域 4 · 10%）

> **目标**：PV/PVC/SC 三件套的绑定与供给规则烂熟于心，10% 的分一分不丢

### [ ] 项目 19：静态 PV/PVC 绑定与 Pod 挂载

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML / 6 条命令 |
| **核心知识点** | PV capacity/accessModes/volumeMode/reclaimPolicy、PVC 绑定条件（容量+模式+storageClassName）、hostPath 卷、数据持久性验证 |
| **覆盖考纲** | 域 4：「Understand persistent volume claims primitive」「Configure a pod to use a PersistentVolumeClaim」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | `kubectl get pvc` 状态 Bound 且引用指定 PV；Pod 挂载写入文件后删除 Pod 重建，文件仍存在；reclaimPolicy=Retain 下删 PVC 后 PV 变 Released |

> **📝 模拟真题**：
> `Task:` Create a PV `app-data` (1Gi, hostPath `/mnt/data`, ReadWriteOnce, reclaimPolicy Retain) and a PVC `app-claim` (500Mi) that binds to it. Mount the claim at `/usr/share/nginx/html` in a new nginx pod. Verify data survives pod deletion. (Weight: 5%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 19：静态 PV/PVC」。请给题解：PV/PVC/Deployment 三段 YAML、绑定匹配规则（容量、accessModes、storageClassName 留空才绑静态 PV）、hostPath 在 kind 节点内的位置、删 Pod 重建验证持久性。附 accessModes 三种含义与 RWO 不等于单 Pod 的辨析。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/19-pv-pvc.md](cka-drills/19-pv-pvc.md)（Bound→持久性→Released 全链实测 + hostPath 节点陷阱设计，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 20：StorageClass 动态供给

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~20 行 YAML / 5 条命令 |
| **核心知识点** | StorageClass provisioner/reclaimPolicy/volumeBindingMode、default SC 注解、动态供给触发条件（PVC 引用 SC 名） |
| **覆盖考纲** | 域 4：「Understand how storage class and persistent volume claims affect dynamic provisioning」 |
| **环境** | kind（k8s-learn，自带 local-path SC ✅ 实测在位） |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | 新建 SC `fast` 并设为默认后，不带 storageClassName 的 PVC 自动 Bound 且 `kubectl get pvc` 显示 `STORAGECLASS=fast`；Pod 写入数据落到动态供给目录 |

> **📝 模拟真题**：
> `Task:` Create a new StorageClass `fast` using the same provisioner as the existing default class, and make it the cluster default. Then create PVC `fast-claim` (1Gi) without specifying a storageClassName and confirm it binds dynamically. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 20：StorageClass 动态供给」。请给题解：先 kubectl get sc 看 kind 自带 local-path 的 provisioner，再写新 SC + annotation storageclass.kubernetes.io/is-default-class="true"，PVC 不写 storageClassName 触发默认供给，验证 Bound 链路与自动创建的 PV。附 WaitForFirstConsumer 模式的意义。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/20-storageclass.md](cka-drills/20-storageclass.md)（换默认"一摘一戴"实测 + Immediate/WaitForFirstConsumer 差异，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 21：PVC 排障与卷快照恢复

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行 YAML / 8 条命令 |
| **核心知识点** | PVC Pending 三大原因（无 SC/容量/模式不匹配）、VolumeSnapshotClass/snapshot、从快照新建 PVC（dataSource） |
| **覆盖考纲** | 域 4：「Binding states and troubleshooting unbound PVCs」+ CSI snapshot（边缘考点） |
| **环境** | kind（k8s-learn；快照需 snapshot-controller，labs/17 已有全套材料） |
| **⏱️ 目标用时** | 12 分钟 |
| **前置** | labs/17_csi_snapshot（CRD 与 controller 安装脚本） |
| **⚠️ 风险** | 排障段必练（已实测）；快照段 ❌ 本机离线不可行（GitHub 被墙 + local-path 无 CSI 快照后端），fallback：killercoda 场景或文档级掌握，见开工包 |
| **验收标准** | 故意写错 SC 名的 PVC 能通过 `describe` 说出原因并修复为 Bound；快照 ReadyToUse=true，恢复出的新 PVC 挂载后数据与快照一致 |

> **📝 模拟真题**：
> `Task:` PVC `data-claim` in namespace `store` is stuck Pending — diagnose and fix it so it binds. Then take a snapshot `data-snap` of the bound PVC and restore it into a new PVC `data-restored`; verify the restored volume contains the original data. (Weight: 5%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 21：PVC 排障与快照」。请分两段给题解：① 构造一个 Pending PVC（storageClassName 拼错），describe 定位并修复；② 基于 labs/17 的 snapshot-controller，创建 VolumeSnapshot 并用 dataSource: apiGroup snapshot.storage.k8s.io 恢复为新 PVC，exec 验证数据。附验收断言。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/21-pvc-troubleshoot.md](cka-drills/21-pvc-troubleshoot.md)（排障段实测全过：PVC spec immutable 顶级考点 + WaitForFirstConsumer 二级 Pending；快照段 ❌ 离线不可行，fallback 见文内，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第五阶段：排障（项目 22-30，考纲域 5 · 30%）

> **目标**：建立「现象 → 事件 → 日志 → spec → 组件」的排障反射弧，30% 的分值从这里拿，每题限时完成

### [ ] 项目 22：Pod 四大故障状态速修

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行 YAML（故障注入）/ 12 条命令 |
| **核心知识点** | ImagePullBackOff（镜像名/tag 错）、CrashLoopBackOff（启动命令错）、Pending（调度约束）、OOMKilled（limit 过低）四态的秒级判别 |
| **覆盖考纲** | 域 5：「Application failures: CrashLoopBackOff, ImagePullBackOff, OOMKilled, Pending pods」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 15 分钟 |
| **验收标准** | 注入脚本运行后 `kubectl get pod -n broken` 出现四种非 Running 状态各至少 1 个；修复后全部 Running/Ready，`verify.sh` 输出 4/4 |

> **📝 模拟真题**：
> `Task:` Fix all broken pods in namespace `broken`. Each pod fails for a different reason: wrong image, invalid command, unschedulable constraint, and a too-low memory limit. Leave the workloads otherwise unchanged. (Weight: 8%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 22：Pod 四态排障」。请给我一个故障注入 YAML 集（image 拼错 / command 不存在 / nodeSelector 指向不存在标签 / memory limit 4Mi 必 OOM）加一个 verify.sh（逐 pod 断言 Running），再给四态的排障决策树：describe 看哪个字段、logs --previous 什么时候用、OOMKilled 的 exit code 137。只输出 YAML、脚本与命令。`

**📦 开工包**：[docs/cka-drills/22-pod-fault-states.md](cka-drills/22-pod-fault-states.md)（四态注入→修复→判分 4/4 闭环，注入 YAML 与 verify 脚本沉淀在 `cka-drills/scripts/`；核心考点：Pod 只有 image 可热改，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 23：无效 Pod spec 排错

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行 YAML / 5 条命令 |
| **核心知识点** | 字段名拼错、类型错（string vs int）、必填字段缺失、`kubectl apply --dry-run=server` 与 apiserver 校验报错解读 |
| **覆盖考纲** | 域 5：「Spotting misconfigured YAML already applied to the cluster」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 8 分钟 |
| **验收标准** | 原始 YAML `kubectl apply` 报 3 处校验错误，逐个修复后 apply 成功且 Pod Running；全程不删除重建其他对象 |

> **📝 模拟真题**：
> `Task:` The manifest at `/root/bad-pod.yaml` fails to apply with multiple validation errors. Fix all errors so the pod applies and runs. Do not rewrite the manifest from scratch. (Weight: 4%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 23：无效 spec 排错」。请生成一个含 3 处校验错误的 Pod YAML（如 image 字段写 images、containerPort 写字符串、缺 metadata.name），并给排障流程：dry-run=server 快速全量校验、逐条报错定位、最小改动修复。附考场技巧：报错信息里 field path 怎么读。只输出 YAML 与命令。`

**📦 开工包**：[docs/cka-drills/23-invalid-spec.md](cka-drills/23-invalid-spec.md)（三层报错优先级实测：缺 name 遮一切→类型转换→未知字段，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 24：Service 不通全链路排查

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 YAML（注入 2 故障）/ 12 条命令 |
| **核心知识点** | 四步链路：endpoints 有无 → targetPort 对不对 → NetworkPolicy 拦不拦 → kube-proxy/iptables 规则在不在 |
| **覆盖考纲** | 域 5：「Networking failures: routing issues, NetworkPolicy blocking traffic」 |
| **环境** | kind（k8s-learn，需 labs/12 的支持 NP 的 CNI） |
| **⏱️ 目标用时** | 15 分钟 |
| **前置** | 项目 14、16、labs/12 |
| **验收标准** | 注入两处故障（targetPort 写错 + NP 漏放行 DNS 之外某端口）后修复，测试 Pod `wget -T 2` 恢复 200，排查过程每步有命令留痕 |

> **📝 模拟真题**：
> `Task:` From pod `client` in namespace `apps`, `curl cache-svc` times out. The service and pods exist. Systematically diagnose and fix all issues (there is more than one). (Weight: 7%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 24：Service 全链路排障」。请生成故障环境（Service targetPort 与容器端口不一致 + 一条 NetworkPolicy 误伤）并给四步排查法完整命令：get ep → describe svc/deploy 对照 targetPort → get netpol 查放行 → exec 进容器 curl/wget 验证。附每一步「正常输出长什么样」的对照表。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/24-service-chain.md](cka-drills/24-service-chain.md)（cka-netpol 双故障四步链闭环 + 「timeout=被丢包、refused=端口不通」判别 + 逐步健康输出对照表，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 25：DNS 故障排查

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~20 行 YAML / 10 条命令 |
| **核心知识点** | CoreDNS Pod 状态、`/etc/resolv.conf` 三要素、kube-dns Service、NP 误伤 UDP 53、coredns ConfigMap |
| **覆盖考纲** | 域 5：「DNS failures」 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 12 分钟 |
| **验收标准** | 注入故障（CoreDNS Pod 被改坏 labels 导致 Service 无 endpoint）后 busybox 解析失败；修复后 `nslookup kubernetes.default` 成功且输出有 A 记录 |

> **📝 模拟真题**：
> `Task:` Pods in namespace `apps` cannot resolve any DNS names. Diagnose the DNS resolution chain and fix the issue. (Weight: 5%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 25：DNS 排障」。请生成故障（kube-dns svc 的 selector 被 tamper）并给 DNS 排障五连命令：resolv.conf 检查 → get ep -n kube-system → coredns pod 状态与日志 → 直接 dig @CLUSTER-IP 验证 → 修复 selector。附「先排除 resolv.conf 再查 coredns」的顺序逻辑。只输出 YAML、脚本与命令。`

**📦 开工包**：[docs/cka-drills/25-dns-troubleshoot.md](cka-drills/25-dns-troubleshoot.md)（实测抓到真实故障：coredns 插件 unsynced 16h 需重启；方法论级发现：busybox nslookup 不做 search 迭代，验证 DNS 必须全 FQDN，2026-10-06；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 26：Node NotReady 与 kubelet 排障

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~10 条命令 |
| **核心知识点** | kubelet systemd 单元、`journalctl -u kubelet`、containerd 状态、Node Lease 与 NotReady 判定、`systemctl enable --now` |
| **覆盖考纲** | 域 5：「Node failures: kubelet not running, node NotReady status」 |
| **环境** | lima VM `cka-vm` ✅（真 systemd，kubelet systemd 单元实操完成；killercoda 备用） |
| **⏱️ 目标用时** | 10 分钟 |
| **⚠️ 风险** | 无——全流程 90 秒闭环，最适合考前热手 |
| **验收标准** | `kubectl get node node01` 从 NotReady 恢复 Ready；`systemctl is-active kubelet` 输出 active；能说出 NotReady 的判定机制（node lease 心跳超时） |

> **📝 模拟真题**：
> `Task:` Node `node01` is in NotReady state. Investigate and fix the underlying issue so the node becomes Ready again. (Weight: 10%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 26：Node NotReady」。请给 killercoda 环境的完整排障剧本：先 kubectl describe node 看 conditions，再 ssh/node shell 里 systemctl status kubelet、journalctl -u kubelet -n 50 找根因（swap 未关/cni 配置丢/containerd 挂）、修复并恢复 Ready。附 NotReady 心跳机制讲解与验收断言。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/26-node-notready.md](cka-drills/26-node-notready.md)（真 systemd 实测：stop → NotReady → 诊断决策树 → start → Ready 全程 90 秒；含 NotReady 五分叉决策树，2026-10-07；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 27：控制面组件故障定位与恢复

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~8 条命令 |
| **核心知识点** | 调度器/controller-manager 挂掉的现象特征（Pending 不动 / 副本不补）、静态 pod manifest 恢复法、`kubectl get pods -n kube-system` 健康面 |
| **覆盖考纲** | 域 5：「Control plane failures: unhealthy apiserver, scheduler, controller-manager」 |
| **环境** | kind（k8s-learn，控制面组件即静态 pod，可安全注入与恢复 ✅ 结构在位） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | 移走 kube-scheduler manifest 后新 Pod 停在 Pending（事件无调度器分配）；恢复 manifest 后 90 秒内 Pod 被调度，`kubectl get pods -n kube-system` 中 scheduler Running |

> **📝 模拟真题**：
> `Task:` In the cluster, newly created pods remain Pending forever. Identify which control-plane component is broken and restore it without restarting the whole cluster. (Weight: 8%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 27：控制面故障」。请给题解：现象对照表（scheduler 挂=永远 Pending、controller-manager 挂=副本数不收敛/绑定不创建、etcd 挂=apiserver 读写失败），kind 上用 docker exec 移走 /etc/kubernetes/manifests/kube-scheduler.yaml 注入故障并恢复的完整命令，静态 pod 自愈原理。附验收断言。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/27-controlplane.md](cka-drills/27-controlplane.md)（scheduler/cm 双注入恢复实测；**方法论级陷阱：controller 挂掉后 status 冻结，get deploy 的 READY 是假象**，2026-10-07；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 28：静态 Pod 管理与修复

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~20 行 YAML / 8 条命令 |
| **核心知识点** | `/etc/kubernetes/manifests` 目录监听机制、kubelet `staticPodPath`、静态 Pod 命名后缀（-cp1）、坏 manifest 的表现 |
| **覆盖考纲** | 域 1/5 交叉：静态 Pod 与 kubelet 管理（kubeadm 集群核心机制） |
| **环境** | kind（k8s-learn，`docker exec` 进控制面节点操作 manifests 目录） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | 放入合法的 `my-nginx.yaml` 后 60 秒内 `kubectl get pod` 出现 `my-nginx-k8s-learn-control-plane`；放入坏 YAML 后 kubelet 日志出现 manifest 解析错误，移除即恢复 |

> **📝 模拟真题**：
> `Task:` A broken static pod manifest has been placed in the static pod directory of node `cp1`, and kubelet logs are filling with errors. Fix the situation, then create a new static pod `my-nginx` (nginx image) directly via the manifests directory — not via the API. (Weight: 6%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 28：静态 Pod」。请给题解：docker exec 进 kind 控制面节点查看 /etc/kubernetes/manifests、放一个坏 YAML 观察 kubelet journalctl 报错、写正确的 my-nginx.yaml 静态 pod（字段与普通 Pod 完全一致）、kubectl 验证命名后缀规则。附静态 pod 与 API 创建 Pod 的本质差异。只输出命令与 YAML。`

**📦 开工包**：[docs/cka-drills/28-static-pod.md](cka-drills/28-static-pod.md)（文件即生命周期实测：放入秒级出现、删除零残留、坏 YAML 无声，2026-10-07；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 29：日志、事件与资源监控排障

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~10 条命令 |
| **核心知识点** | `kubectl logs --previous`（崩溃前日志）、events 排序（--sort-by）、`kubectl top`（metrics-server）、退出码语义（137=OOM/1=应用错） |
| **覆盖考纲** | 域 5：「Log collection: kubectl logs, kubectl describe, journalctl, crictl」「Event inspection」 |
| **环境** | kind（k8s-learn；metrics-server 用 helm 安装 ✅ 工具在位） |
| **⏱️ 目标用时** | 10 分钟 |
| **验收标准** | `kubectl logs <pod> --previous` 取到崩溃前日志；`/root/report.md` 写明该 Pod 重启原因（OOMKilled，exit 137）；`kubectl top pod` 有数据输出 |

> **📝 模拟真题**：
> `Task:` Pod `flaky` in namespace `apps` has restarted 3 times. Determine the cause of the restarts using logs and events, and write your conclusion to `/root/report.md`. Also identify the pod consuming the most CPU in the cluster. (Weight: 5%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 29：日志与事件排障」。请给题解：helm 装 metrics-server（kind 环境参数 --set args 加 kubelet-insecure-tsi）、构造一个 OOMKilled 的 Pod、logs --previous 与 describe 的 exit code 证据链、kubectl top pod -A --sort-by=cpu 找最耗 CPU 的 Pod。附验收断言与考场退出码速记（137/143/1）。只输出命令与注释。`

**📦 开工包**：[docs/cka-drills/29-logs-events.md](cka-drills/29-logs-events.md)（OOM 四件套证据链实测 + 三个细节：--previous 需 Always 策略、可为空、metrics-server 预装勿重装，2026-10-07；先闭卷自测再对照）

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 30：🏋️ 综合故障注入限时排障

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~100 行脚本（注入+验证）/ 60 分钟限时 |
| **核心知识点** | 五类故障混合（镜像错、selector 错、探针错、SC 名错、NP 误伤）的并行定位、时间分配策略、先易后难 |
| **覆盖考纲** | 域 5 全部细目综合演练 |
| **环境** | kind（k8s-learn） |
| **⏱️ 目标用时** | 60 分钟（考场排障题合计约 45 分钟，此题加压） |
| **前置** | 项目 22-29 全部完成 |
| **⚠️ 风险** | 在 cka-netpol 靶场注入（Calico 已实测执行策略，busybox 镜像已灌入节点）；脚本已沉淀开箱即用 |
| **验收标准** | 运行 `chaos-inject.sh` 后 60 分钟内 `verify.sh` 从 0/5 修复至 5/5；复盘写出每题实际耗时与卡点 |

> **📝 模拟真题**：
> `Task:` Five faults have been injected into the cluster across namespaces `shop` and `pay`. Find and fix all of them within 60 minutes. A fault is fixed only when its verification check passes. (Weight: 15%)

**🤖 开始提示词**：
> `我要备考 CKA 练「项目 30：综合限时排障」。请给我两个脚本：chaos-inject.sh 在 kind 集群 k8s-learn 注入 5 个故障（ns shop：镜像 tag 拼错、svc selector 错、探针路径 404、pvc 引用不存在的 SC；ns pay：netpol 漏放行 8080），verify.sh 逐项断言修复并输出 n/5；再给一份 60 分钟时间分配策略（每个故障 12 分钟封顶）。只输出脚本与策略。`

**📦 开工包**：[docs/cka-drills/30-chaos-drill.md](cka-drills/30-chaos-drill.md) + **脚本已沉淀**：[chaos-30.sh](cka-drills/scripts/chaos-30.sh)（一键注入）与 [verify-30.sh](cka-drills/scripts/verify-30.sh)（判分，实测 0/5 → 5/5 全闭环，2026-10-07）；含五故障图谱与考场时间策略

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第六阶段：全真模考（项目 31-32）

> **目标**：2 小时、15-17 题、66 分及格线——把前面 30 个考点在时间压力下串成一次完整考试体验

### [ ] 项目 31：⛓️ 全真模考 #1（120 分钟）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | 16 道题 / 120 分钟 / 一张评分表 |
| **核心知识点** | 时间管理（平均 7 分钟/题）、context 切换纪律、imperative 优先、查 kubernetes.io 的节奏、先易后难标记法 |
| **覆盖考纲** | 五域按权重出题：域 1×4 题（25%）+ 域 2×2 题（15%）+ 域 3×3 题（20%）+ 域 4×2 题（10%）+ 域 5×5 题（30%） |
| **环境** | kind（k8s-learn）+ killercoda（kubeadm 题单独计时）⚠️ 题面生成前探活 |
| **⏱️ 目标用时** | 120 分钟整场 + 60 分钟复盘 |
| **前置** | 项目 1-30 完成 |
| **验收标准** | tmux 计时 120 分钟内完成 16 题；对照评分表自判总分 ≥66%；每道丢分题在踩坑记录写一行根因 |

> **📝 模拟真题**：
> 题面来源二选一：① 已购考票则用官方 killer.sh 的第 1 套模拟（与考场同界面）；② 用上方「模考判卷」提示词让 AI 按 32 清单考点生成等价题库（16 题带权重）。

**🤖 开始提示词**：
> `我要备考 CKA，进行「全真模考 #1」。请按 CKA 考纲权重（域1 25%、域2 15%、域3 20%、域4 10%、域5 30%）生成 16 道实操题题库：每题给英文题干（仿考场风格，标注权重与目标 context）、评分细则（按步骤给分）、以及难度梯度（前 5 题热身、第 8/13 题设难题卡点）。同时给一张可打印的评分表模板。不要给答案，答案在我交卷后单独索要。`

**📦 模考套件（已建成并首轮实测）**：[docs/cka-drills/mock-1/](cka-drills/mock-1/EXAM.md)——试卷（16 题带权重）+ `setup.sh`（一键重置环境与故障）+ `grade.sh`（自动判分）+ `examiner-t16.sh`（考官注入）+ [REPORT.md](cka-drills/mock-1/REPORT.md)（首轮成绩单：出题人自验 16/16，含逐题参考解法与考生重考指南）。**你考：setup → 闭卷 120 分钟 → examiner-t16 → grade，≥66 PASS。**

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 32：⛓️ 全真模考 #2（120 分钟 + 错题闭环）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | 16 道全新题 / 120 分钟 / 一份错题复盘文档 |
| **核心知识点** | 模考 #1 丢分项的定向重练、二轮时间策略修正、考场日 checklist（context 纪律 / 保存 manifest / 检查 namespace） |
| **覆盖考纲** | 五域权重同模考 #1，但题目全部换新（针对 #1 丢分考点加倍出题） |
| **环境** | kind（k8s-learn）+ killercoda |
| **⏱️ 目标用时** | 120 分钟整场 + 90 分钟错题闭环 |
| **前置** | 项目 31 + 全部丢分题重练 |
| **验收标准** | 总分 ≥80%（冲稳）；模考 #1 的每个丢分根因在本次模考中对应题型得分；错题复盘文档覆盖全部丢分题并归档到本文档踩坑记录 |

> **📝 模拟真题**：
> killer.sh 第 2 套官方模拟，或 AI 生成的第二套等价题库（明确要求：包含模考 #1 的丢分考点变体题）。

**🤖 开始提示词**：
> `我要备考 CKA，进行「全真模考 #2」。我的模考 #1 丢分考点是：[粘贴丢分列表]。请生成第二套 16 题题库：其中 6 题是丢分考点的变体（换对象名换参数，不换考点），其余按考纲权重正常分布；评分表同 #1。交卷后请对比两模考的 per-domain 得分变化并给考前一周冲刺建议。`

**完成日期**：________
**踩坑记录**：________

---

## 📅 周计划

| 周次 | 内容 | 项目数 |
|:---|:---|:---:|
| **第 1 周** | 项目 1-7（域 1 集群架构与配置；先探活 killercoda，跑通 1/2/3） | 7 |
| **第 2 周** | 项目 8-12（域 2 工作负载与调度） | 5 |
| **第 3 周** | 项目 13-18（域 3 服务与网络；NetworkPolicy 与 Gateway 是难点，多留周末） | 6 |
| **第 4 周** | 项目 19-21（域 4 存储）+ 项目 22-23（域 5 开篇） | 5 |
| **第 5 周** | 项目 24-30（域 5 排障主体 + 综合限时演练） | 7 |
| **第 6 周** | 项目 31-32（两次全真模考 + 错题闭环）→ 考试 | 2 |

## 🏆 里程碑

- [ ] **完成项目 1-7** → 「kubeadm 运维手」：能在真机上装、升、备份、授权一个集群
- [ ] **完成项目 8-12** → 「工作负载调度手」：部署/伸缩/探针/定向调度 8 分钟内闭卷完成
- [ ] **完成项目 13-18** → 「流量管理员」：Service→Ingress→NetworkPolicy→Gateway 全链路可控
- [ ] **完成项目 19-21** → 「存储操盘手」：PV/PVC/SC 绑定与供给规则零失分
- [ ] **完成项目 22-30** → 「排障快手」：五类故障 12 分钟内定位修复
- [ ] **完成项目 31-32** → 模考双过线（66% → 80%）→ 🎯 预约 CKA 考试

## 📝 每日日志

| 日期 | 项目 | 耗时 | 收获 | 踩坑 |
|:---|:---|:---:|:---|:---|
| | | | | |

## 🔧 环境配置

```bash
# 0. 已就绪（本次实测 2026-10-06）：
#    kubectl、docker 29.4.0（daemon 运行中）、kind（5 个集群在位：k8s-learn/ai-infra/kind/member-ap/member-us）、
#    helm、tmux、jq、yq —— 域 2/3/4 大部分项目本机直接开练

# 1. 需准备：
#    a) killercoda 免费账号 https://killercoda.com（域 1 的 kubeadm 题与域 5 的 systemd 题必需）
#    b) kind 集群内组件（按项目前置安装，勿提前全装）：
helm install metrics-server metrics-server/metrics-server \
  -n kube-system --set args={--kubelet-insecure-tls}   # 项目 29
bash labs/11_ingress/ingress.sh                        # 项目 15（ingress-nginx；k8s-learn 已预装可跳过）
# 项目 16/24/30 用独立靶场集群 cka-netpol（已搭好保留；删了就按开工包 16 重建）：
kubectl config use-context kind-cka-netpol && kubectl -n netpol-demo get netpol
bash labs/33_gateway_api/gateway.sh                    # 项目 18（Gateway API CRD + 实现）
bash labs/17_csi_snapshot/snapshot.sh                  # 项目 21（snapshot-controller）
#    c) 真机 kubeadm 靶场（已建成，替代 killercoda）：
#       lima VM cka-vm：limactl start cka-vm 后 limactl shell cka-vm
#       （kubeadm v1.33.13 + flannel Ready；项目 1/2/3/26 全在此练；闲置会自停，limactl start 秒级恢复）

# 2. 每项目开工前：
kubectl config use-context kind-k8s-learn && kubectl get nodes   # 确认在正确集群
```

## ⚠️ 与已有清单的关系

| 已有清单 | 关系 |
|:---|:---|
| `docs/kubernetes.md`（34/34 已完成，知识体系型） | 互补：kubernetes.md 是「学全 K8s」的能力图谱，本清单是「考过 CKA」的真题训练场。重叠项目直接以真题方式再练一遍（如 RBAC、NetworkPolicy、PV/PVC），不重复讲概念；需要概念回炉时跳回对应 labs 复习，本清单不承载教学 |
| `docs/kubernetes_operator.md` | 无交集（Operator/CRD 开发不在 CKA 考纲，仅 CRD 概念认知），跳过 |
| `docs/microservices.md` | 无交集，跳过 |
| `labs/00-34` 实验目录 | 是本清单的「弹药库」：凡前置列了 labs 的项目，用 labs 脚本装环境、用真题任务练手感 |

## ⚠️ 环境能力实测与探活表

| 能力/环境 | 计划 | 实测结论 |
|:---|:---|:---|
| kind 集群（k8s-learn 等 5 个） | 域 2/3/4/5 日常题 | ✅ 实测：k8s-learn 为 **3 节点集群（v1.36.1）**，项目 6/12 的 drain/taint 也可本机练（2026-10-06） |
| docker daemon / helm / tmux | 本机工具链 | ✅ 实测可用 |
| kind 内 etcdctl snapshot save | 项目 3 备份环节 | ⚠️ 开工探活（证书路径与端点需现场确认） |
| NetworkPolicy 真实执行环境 | 项目 16/24/30 | ✅ 实测：独立集群 `cka-netpol`（Calico）已搭好并保留，default-deny 正反验证全过（2026-10-06）；重建命令见开工包 16 |
| kind 内静态 pod 注入/恢复 | 项目 27/28 | ✅ 实测可行（docker exec mv/rm manifests 目录，scheduler/cm/静态 pod 全链验证，2026-10-07） |
| kind 内 metrics-server | 项目 29 | ✅ k8s-learn 预装（重装会报 APIService 所有权错，先 top 再说） |
| killercoda kubeadm 双节点环境 | 项目 1/2/6/26/31/32 | ⚠️ 站点可达（2026-10-06 WebFetch 确认，页面为 JS 渲染需登录）；版本/sudo/apt 源可连性进终端跑项目 1 的探活脚本确认 |
| killercoda 上真实 kubeadm 升级 | 项目 2 | ✅ fallback 已落地且更好：lima VM `cka-vm`（kubeadm v1.33.13）可真升 v1.34（pkgs.k8s.io 实测可达） |
| kind 内 systemd/journalctl（kubelet 排障） | 项目 26 | ✅ fallback 已落地：cka-vm 有真 systemd（kubelet 单元 + journalctl 全可用） |
| GitHub raw 直连 | 拉取 CRD/清单 | ❌ 实测不通（2026-10-06）；走 `gh-proxy.com` 镜像前缀可用 ✅ |
| registry.k8s.io 宿主机拉取 | ingress-nginx 等镜像 | ⚠️ 慢通（controller 4 分钟、certgen 首拉断流重试成功）；节点内直拉不通，必须 kind load |
| quay.io / docs.tigera.io / kubernetes.github.io | Calico Helm、官方 chart | ✅ 实测可达 |
| metrics-server / snapshot-controller | 按项目前置安装 | ⚠️ 待装（labs 已提供脚本） |

## 📚 来源

- [CKA Exam Domains & Weightings 2026](https://ckaexam.com/blog/cka-exam-domains-guide)（考纲权重、考试事实）
- [CKA Syllabus — techiescamp](https://github.com/techiescamp/cka-certification-guide/blob/main/SYLLABUS.md)（考纲细目）
- [Kubernetes 官方文档（考场唯一允许的文档站，练习时就用它）](https://kubernetes.io/docs/home/)
- [killercoda — 免费在线 K8s 场景](https://killercoda.com/playgrounds)
- 本仓库配套实验：`labs/11`（Ingress）、`labs/12`（NetworkPolicy/CNI）、`labs/17`（CSI Snapshot）、`labs/20`（Pod Security）、`labs/33`（Gateway API）
