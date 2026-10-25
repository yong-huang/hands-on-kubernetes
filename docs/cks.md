# 🛡️ CKS 认证备考 32 小项目学习清单 · Todo List（kind 靶场全跑通）

> 通过 32 个小项目覆盖 CKS v1.34 六大考纲域：每项目 = 在本机 kind 靶场上做出一个可验证的安全能力（一套加密配置、一组能拦住坏镜像的准入策略、一条能抓到入侵的检测规则），不是刷题
> 环境约束：26 项纯本机 kind 可跑；2 项本机可跑但首次开工需探活（kube-bench、Falco 内核）；4 项因内核/宿主限制走 killercoda 免费环境（AppArmor、gVisor、kubeadm 升级、宿主加固——不可行原因已实测，写在对应项目）
> 串联机制：考点驱动型——每条考纲细目对应一个"做出来"的小项目，全部项目长在同一个靶场集群上，末尾 🏁 红蓝对抗把检测/拦截/审计/取证串成一次完整攻防
> 预计周期：8 周（每天 1-1.5 小时）；考纲依据：[CNCF CKS Curriculum v1.34](https://github.com/cncf/curriculum)（2026-10 下载核验）

**考试事实速览**（报名前以 Linux Foundation FAQ 复核）：

| 项目 | 内容 |
|:---|:---|
| 形式 | 2 小时全实操（15-20 题，多套预配置集群，每题指定 context，先切对集群） |
| 及格 / 费用 | 66% / $445（含一次免费重考 + killer.sh 官方模拟环境） |
| 前置 | 必须先持有有效 CKA（本仓库 [cka.md](cka.md) 即为此准备） |
| 考场环境 | Ubuntu + kubeadm 集群——AppArmor、宿主操作类题目只能在真机做，清单里对应项目已标注 |
| 考纲特点 | v1.34 不再点名具体工具（OPA/Gatekeeper 已移出、Falco 也不点名），考的是能力；本清单选的都是在该能力上最主流的工具 |

## 🎯 考纲域 → 项目速查表

| 考纲域（权重） | 考纲细目（v1.34 原文节选） | 对应项目 |
|:---|:---|:---:|
| **域 1** Cluster Setup（15%） | NetworkPolicies 限制集群级访问；CIS benchmark 审查组件安全配置；Ingress TLS；保护节点 metadata；校验平台二进制 | 2, 3, 4, 5, 15 |
| **域 2** Cluster Hardening（15%） | RBAC 最小暴露；ServiceAccount 谨慎使用；限制 API 访问；升级消除漏洞 | 6, 7, 8, 9 |
| **域 3** System Hardening（10%） | 收敛宿主攻击面；最小权限身份；内核加固工具（AppArmor、seccomp） | 10, 11, 12, 13 |
| **域 4** Minimize Microservice Vulnerabilities（20%） | Pod Security Standards；管理 secrets；隔离技术（多租户、沙箱容器）；Pod-to-Pod 加密 | 14, 16, 17, 18 |
| **域 5** Supply Chain Security（20%） | 镜像瘦身；供应链（SBOM、CI/CD、制品仓库）；签名与验签；静态分析（Kubesec、KubeLinter） | 19, 20, 21, 22, 23, 24, 25 |
| **域 6** Monitoring, Logging and Runtime Security（20%） | 行为分析检测恶意活动；调查攻击阶段；运行时不可变；审计日志监控访问 | 26, 27, 28, 29, 30, 31 |

靶场载体：专用 kind 集群 `cks`（项目 1 搭建）+ 受保护靶子应用 `podinfo`——32 个项目的产物全部长在这套环境上，🗑️ 各项目自带 clean，互不污染。

## 🤖 AI 辅助提示词速查

| 场景 | 提示词 |
|:---|:---|
| **开始一个新项目** | `我要在 kind 靶场集群 cks 上做 CKS 项目「[名称]」，目标是 [产物]。请给完整步骤/配置：[要点]，附验收命令。只输出命令、配置与注释。` |
| **排障** | `[组件] 出现 [现象]，报错/日志：[粘贴]。请分析根因并给最小修复。` |
| **考法反问** | `针对 CKS 考纲「[原文条目]」，考场会怎么出题？给我 3 种任务变形和秒答步骤。` |

## 📊 总进度

进度：░░░░░░░░░░░░░░░░░░░░ 0/32 (0%)

| 阶段 | 项目数 | 已完成 |
|:---|:---:|:---:|
| 一：靶场与集群基线（Cluster Setup） | 5 | 0 |
| 二：访问与身份硬化（Cluster Hardening） | 4 | 0 |
| 三：内核与宿主（System Hardening） | 4 | 0 |
| 四：工作负载暴露面（Microservice Vulnerabilities） | 5 | 0 |
| 五：供应链（Supply Chain Security） | 7 | 0 |
| 六：检测、审计与响应（Monitoring/Logging/Runtime） | 6 | 0 |
| 终极：红蓝对抗 | 1 | 0 |
| **合计** | **32** | **0** |

---

## 🗂️ 第一阶段：靶场与集群基线（项目 1-5）

> **目标**：有一套自己的安全靶场，并掌握"控制面配置审查与收口"的三件高频考事：etcd 加密、CIS 体检、二进制校验

### [ ] 项目 1：⛳ 搭建 CKS 安全靶场集群

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行配置 + 命令 |
| **核心知识点** | kind 多节点集群、kubeadmConfigPatches 预留 apiserver 安全参数、extraMounts 挂载宿主目录、靶子应用部署、镜像预载 |
| **覆盖考纲** | 六域综合基座（后续 31 个项目全部长在这套环境上） |
| **环境** | 本机 kind ✅ |
| **验收标准** | `kubectl get nodes` 见 1 控制面 + 2 工作节点全 Ready；`kubectl -n target get pods` 里 podinfo 就绪且 `kubectl port-forward` 能访问其首页；删除靶场一条命令零残留 |

**🤖 开始提示词**：
> `我要做 CKS 项目「搭建安全靶场集群」。请给完整 kind 配置与脚本：3 节点集群名为 cks、apiserver 预留 audit-policy 与 encryption-config 的挂载位（先不启用）、宿主目录 ./cks-lab 挂进控制面、部署 podinfo 到 target namespace 作靶子、预载后续项目需要的镜像清单。附验收命令与一键 clean。只输出命令、配置与注释。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 2：给 etcd 上静态加密

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行配置 + 命令 |
| **核心知识点** | EncryptionConfiguration、aescbc/secretbox、identity 旧值兼容、kubeadm patch 重启控制面、etcdctl 验证 |
| **覆盖考纲** | Cluster Setup：「Use CIS benchmark to review the security configuration of Kubernetes components (etcd…)」；Microservice：「Manage kubernetes secrets」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1 |
| **验收标准** | 开启加密前 `etcdctl get` 看到 Secret 明文，开启后新建 Secret 在 etcd 里为 `k8s:enc:aescbc:` 前缀密文；关掉加密插件后旧 Secret 仍可读（identity 兜底生效） |

**🤖 开始提示词**：
> `我要做 CKS 项目「etcd 静态加密」。请给完整步骤：EncryptionConfiguration（aescbc + identity 兜底）写入靶场宿主挂载目录、kind kubeadmConfigPatches 的 apiServer extraArgs 引用、重建集群、用 nicoHA 等 etcdctl 容器进 etcd 验证明文/密文对比、以及关闭加密后的兼容行为验证。附验收命令。只输出命令与配置。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 3：用 kube-bench 给集群做 CIS 体检

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行 YAML + 命令 |
| **核心知识点** | CIS Kubernetes Benchmark、kube-bench Job 化运行、fail/warn 分级解读、按项修复 |
| **覆盖考纲** | Cluster Setup：「Use CIS benchmark to review the security configuration of Kubernetes components (etcd, kubelet, kubedns, kubeapi)」 |
| **环境** | 本机 kind ⚠️ 开工探活（kind 节点内跑 kube-bench 的 Job 模板社区可用但非官方保证；fallback：`--targets master` 逐项跑或去 killercoda） |
| **前置** | 项目 1 |
| **⚠️ 风险** | kind 节点是容器，部分宿主级检查项必然 FAIL——学"读报告、区分真问题与环境差异"正是本项目目标 |
| **验收标准** | kube-bench 跑完产出 JSON/文本报告；挑 2 项可修复 FAIL（如 anonymous-auth、readOnlyPorts 类）在靶场修掉后复测该项变 PASS，形成前后对比记录 |

**🤖 开始提示词**：
> `我要做 CKS 项目「kube-bench CIS 体检」。请给：适配 kind 的 kube-bench Job YAML、跑 master 与 node 两类 target 的命令、结果 JSON 的 jq 统计命令（按 fail/warn/info 计数）、以及针对 kind 场景 2 个可真实修复项的具体修法。附验收命令。只输出命令、配置与注释。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 4：Ingress TLS 收口

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行配置 + 命令 |
| **核心知识点** | 自签 CA、openssl 一条龙、tls Secret、Ingress TLS 段、force-ssl-redirect |
| **覆盖考纲** | Cluster Setup：「Properly set up Ingress objects with TLS」 |
| **环境** | 本机 kind ✅（依赖 labs/11 的 ingress-nginx 前置，或靶场内重装） |
| **前置** | 项目 1；基础：[labs/11](../labs/11_ingress/README.md)、[labs/34](../labs/34_cert_manager/README.md) |
| **验收标准** | `curl -k https://域名` 返回 200 且证书链显示自签 CA；`curl -I http://域名` 返回 301 跳 HTTPS；私钥不出现在任何清单文件里（grep 断言） |

**🤖 开始提示词**：
> `我要做 CKS 项目「Ingress TLS 收口」。请给完整步骤：openssl 自签 CA + 服务端证书（SAN 含 podinfo.local）、kubectl create secret tls、带 tls 段与 force-ssl-redirect 注解的 Ingress、curl -k 验证证书链与 301 断言。附验收命令与 clean。只输出命令与配置。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 5：平台二进制校验流水

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行脚本 |
| **核心知识点** | release 制品 sha256sum 校验、cosign verify 公开签名、镜像 digest 固定 |
| **覆盖考纲** | Cluster Setup：「Verify platform binaries before deploying」 |
| **环境** | 本机 ✅（⚠️ 国内网络下载 dl.k8s.io 慢时用阿里云镜像源，脚本里写好两个源切换） |
| **验收标准** | 校验脚本对一份 kubectl/kube-apiserver 制品跑通：sha256 全部 PASS；篡改 1 字节后脚本 FAIL（防篡改断言）；cosign 对 kubernetes 官方镜像验签输出 Verified OK |

**🤖 开始提示词**：
> `我要做 CKS 项目「平台二进制校验流水」。请写一个 verify_binaries.sh：从 dl.k8s.io（备用阿里云源）下载指定版本 kubectl 与 kube-apiserver 及其 .sha256、校验、再对 registry.k8s.io 官方镜像做 cosign verify、最后做"篡改一字节必须 FAIL"的自测。只输出脚本与注释。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第二阶段：访问与身份硬化（项目 6-9）

> **目标**：把"人和程序怎么进集群"全面最小化——SA 默认 token、RBAC 边界、匿名访问、版本漏洞

### [ ] 项目 6：ServiceAccount Token 全场收敛

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行脚本 + 清单 |
| **核心知识点** | automountServiceAccountToken、Projected Token TTL、default SA 滥用、全场审计脚本 |
| **覆盖考纲** | Cluster Hardening：「Exercise caution in using service accounts e.g. disable defaults, minimize permissions on newly created ones」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1 |
| **验收标准** | 审计脚本列出全场仍自动挂 token 的 Pod（初始含 podinfo）；给 podinfo 关掉 automount 后 Pod 内 `cat /var/run/secrets/.../token` 报不存在；脚本复跑该 Pod 消失于名单 |

**🤖 开始提示词**：
> `我要做 CKS 项目「SA Token 全场收敛」。请给：一个 kubectl+jq 的全场 token 挂载审计脚本（输出 namespace/pod/挂载状态）、把靶子 podinfo 与 demo Deployment 改为 automount=false 的 patch、关闭前后 Pod 内 token 文件存在性对照命令。附验收断言。只输出脚本与配置。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 7：给部署机器人造一把最小权限的钥匙

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行 YAML |
| **核心知识点** | Role/RoleBinding 最小集、resourceNames 收窄、kubectl auth can-i 矩阵自测、SA 模拟（--as） |
| **覆盖考纲** | Cluster Hardening：「Use Role Based Access Controls to minimize exposure」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 6；基础：[labs/19](../labs/19_rbac/README.md)（这里练 CKS 考法：限定到 resourceNames 与子资源） |
| **验收标准** | deployer SA 能重启 target namespace 的 podinfo（pods/log 读 + deployment restart），但 `can-i --as` 断言：读 Secret 为 no、跨 namespace 任何操作为 no、删 namespace 为 no |

**🤖 开始提示词**：
> `我要做 CKS 项目「部署机器人最小权限」。请给完整 RBAC 清单：名为 deployer 的 SA + Role（仅 target ns 的 deployment get/list/patch 与 pods get/list/log）+ RoleBinding；并用 --as 跑一组 can-i 断言（该能的 yes、Secret 与跨 ns 全 no）。附验收命令。只输出清单与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 8：关上 API Server 的匿名门

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行配置 + 命令 |
| **核心知识点** | anonymous-auth、authorization-mode=Node,RBAC、system:anonymous 验证、apiserver 安全参数族 |
| **覆盖考纲** | Cluster Hardening：「Restrict access to Kubernetes API」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1（用到 kind kubeadmConfigPatches） |
| **验收标准** | 带 `?` 无凭据请求 healthz 在关闭匿名前 200、关闭后 401/403；`kubectl --as=system:anonymous get pods` 被拒；apiserver 参数里 authorization-mode 不含 AlwaysAllow（grep 断言） |

**🤖 开始提示词**：
> `我要做 CKS 项目「关上 API Server 匿名门」。请给：kind kubeadmConfigPatches 设置 anonymous-auth=false 与 authorization-mode=Node,RBAC 的完整 patch、重建后验证匿名请求 401/403 的 curl 与 kubectl --as=system:anonymous 命令、以及查看生效参数的方法。附验收断言。只输出配置与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 9：小版本升级消除 CVE（选做攻坚）

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~20 条命令 |
| **核心知识点** | kubeadm upgrade plan/apply、etcd 备份前置、cordon/drain、工作负载无感验证 |
| **覆盖考纲** | Cluster Hardening：「Upgrade Kubernetes to avoid vulnerabilities」 |
| **环境** | killercoda ⚠️（kind 不支持就地升级节点版本——节点是整体替换的镜像；考场是真 kubeadm 机） |
| **前置** | 建议先做/复做 [cka-drills/02](cka-drills/02-kubeadm-upgrade.md)（本项是其安全语境版：以"消除 CVE"为目标） |
| **⚠️ 风险** | 选做攻坚；靶场集群无法完成，需要 killercoda/lima 真机 |
| **验收标准** | killercoda 双节点集群 minor 从旧升到新：`kubectl get nodes` 版本号符合预期且全 Ready；升级期间 podinfo Service 持续可访问（循环 curl 断言） |

**🤖 开始提示词**：
> `我在 killercoda kubeadm 环境做 CKS 项目「小版本升级消除 CVE」。请给完整升级 runbook：etcd 备份、kubeadm upgrade plan/apply、逐节点 cordon/drain/upgrade、升级期间业务可用性探测脚本、失败回退思路。附验收命令。只输出命令与注释。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第三阶段：内核与宿主（项目 10-13）

> **目标**：越出集群边界，在内核层给容器画行为边界——seccomp、capabilities、AppArmor、宿主面

### [ ] 项目 10：seccomp 从 RuntimeDefault 到自定义 profile

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行配置 |
| **核心知识点** | seccompProfile 三档、localhost profile 存放路径（节点 /var/lib/kubelet/seccomp/）、syscall 拦截验证、审计模式调试 |
| **覆盖考纲** | System Hardening：「Appropriately use kernel hardening tools such as AppArmor, seccomp」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1 |
| **验收标准** | RuntimeDefault 下 Pod 内 `sh -c 'echo hi > /tmp/x'` 成功而自定义 profile 禁 clone 后同命令 FAIL 且事件里能看到被拒 syscall（SCMP_ACT_ERRNO 生效）；切换三档的行为差异记录在案 |

**🤖 开始提示词**：
> `我要做 CKS 项目「seccomp 三档对比与自定义」。请给：节点侧 localhost profile（禁 clone/写 /etc）的 JSON 与放进 kind 节点的命令、三种 seccompProfile 的对照 Deployment、触发 EPERM 并从事件确认拦截的验证步骤。附验收断言。只输出配置与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 11：拔掉容器的多余能力

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | capabilities drop ALL / 最小 add、allowPrivilegeEscalation、privileged 危害对照、runAsNonRoot |
| **覆盖考纲** | System Hardening：「Appropriately use kernel hardening tools…」；Microservice：「Use appropriate pod security standards」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1；基础：[labs/20](../labs/20_pod_security/README.md) |
| **验收标准** | drop ALL 后 Pod 内 `chown` / `mknod` / 抓包（CAP_NET_RAW）全部 Operation not permitted；特权版对照 Pod 能成功（危害实证）；加固版 podinfo 业务仍 200 |

**🤖 开始提示词**：
> `我要做 CKS 项目「拔掉容器多余能力」。请给：三份对照 Deployment（privileged / 默认 / drop ALL + 最小 add）、每个能力点的容器内验证命令（chown/mknod/ping）、以及加固后业务可用性断言。附验收命令。只输出清单与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 12：AppArmor 给容器画行为边界

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 profile + 清单 |
| **核心知识点** | apparmor_parser 加载、enforce/complain、container.apparmor.security.beta.k8s.io 注解、违规拦截 |
| **覆盖考纲** | System Hardening：「Appropriately use kernel hardening tools such as AppArmor, seccomp」 |
| **环境** | killercoda ⚠️（本机已实测不可行：macOS 容器 VM 内核未启用 AppArmor LSM，kind 节点共享该内核；考场是 Ubuntu，必须真机练） |
| **验收标准** | killercoda 节点加载自定义 profile（禁写 /etc 与执行新二进制）后：带注解 Pod 违规操作被 denied（dmesg 可见），无注解对照 Pod 同操作成功；`cat /sys/module/apparmor/...` 断言 enforce 状态 |

**🤖 开始提示词**：
> `我在 killercoda 的 Ubuntu kubeadm 节点做 CKS 项目「AppArmor 行为边界」。请给：一份禁写 /etc、禁执行新二进制的 AppArmor profile、apparmor_parser 加载命令、带 container.apparmor 注解的 Pod 与无注解对照 Pod、违规触发与 dmesg 取证命令。附验收断言。只输出配置与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 13：宿主机最小攻击面

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 条命令 |
| **核心知识点** | systemd 服务最小化、sshd 加固（禁 root/密码登录）、用户与文件权限最小化、监听端口盘点 |
| **覆盖考纲** | System Hardening：「Minimize host OS footprint (reduce attack surface)」「Using least-privilege identity and access management」 |
| **环境** | killercoda ⚠️（宿主操作；本机 macOS 无对应环境） |
| **验收标准** | 加固后 `ss -tlnp` 无多余监听；`ssh -o PasswordAuthentication=yes` 被拒；非特权业务用户跑服务且其 home 下关键文件权限 600（find 断言）；产出可复跑的加固自查脚本 |

**🤖 开始提示词**：
> `我在 killercoda Ubuntu 节点做 CKS 项目「宿主机最小攻击面」。请给：服务与端口盘点命令、sshd 逐项加固（禁 root/密码登录/最小算法）、业务专用低权用户创建与文件权限收敛、以及一份可复跑的 harden-check.sh 自查脚本（输出 PASS/FAIL）。只输出命令与脚本。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第四阶段：工作负载暴露面（项目 14-18）

> **目标**：从 Pod 安全标准到网络与传输加密，把"跑在集群里的东西"全面设防

### [ ] 项目 14：PSS/PSA 三级收紧实战

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行配置 |
| **核心知识点** | PSS 三等级包含关系、PSA enforce/audit/warn 组合、dry-run 验证器、逐 ns 迁移 |
| **覆盖考纲** | Microservice：「Use appropriate pod security standards」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1；基础：[labs/20](../labs/20_pod_security/README.md)（本项练考法：多 ns 差异化 enforce + 校验脚本） |
| **验收标准** | target ns 设 enforce=restricted 后：特权 Pod 被 403 拒绝（错误信息含 violate PodSecurity）；audit/warn ns 里同样的 Pod 能跑但有警告事件；一个 podinfo 加固到 restricted 通过（dry-run 断言脚本） |

**🤖 开始提示词**：
> `我要做 CKS 项目「PSS/PSA 三级收紧」。请给：三个不同 PSA 配置的 namespace（enforce=restricted / audit+warn=baseline / 无限制）、特权与受限两份对照 Deployment、以及一个 dry-run 批量校验脚本（对给定清单输出能否在目标 ns 落地）。附验收断言。只输出配置与脚本。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 15：全 namespace 默认拒绝网络

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~70 行 YAML |
| **核心知识点** | default-deny 进出、按 label 白名单、DNS（UDP 53）豁免、云 metadata IP 169.254.169.254 拦截 |
| **覆盖考纲** | Cluster Setup：「Use Network security policies to restrict cluster level access」「Protect node metadata and endpoints」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1；基础：[labs/12](../labs/12_network_policy/README.md)（本项练考法：默认拒绝+白名单矩阵） |
| **验收标准** | 连通矩阵脚本全绿：default-deny 后 podinfo↔其他 ns 全断、放行后指定客户端可访问 9898、DNS 解析仍通、到 169.254.169.254 的访问被拒（拿不到 metadata 模拟响应） |

**🤖 开始提示词**：
> `我要做 CKS 项目「全 ns 默认拒绝网络」。请给：default-deny 进出策略、按 label 的最小白名单（含 DNS 豁免与 169.254.169.254/32 拒绝）、一个 busybox 连通矩阵测试脚本（成功/失败逐项断言）。附验收命令。只输出清单与脚本。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 16：Secret 的正确用法与加密落盘联动

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行配置 |
| **核心知识点** | 卷挂载 vs env 注入的安全差异、immutable Secret、Secret 轮换观察、与 etcd 加密联动验证 |
| **覆盖考纲** | Microservice：「Manage kubernetes secrets」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 2、6；基础：[labs/05](../labs/05_cm_secret/README.md)、[labs/22](../labs/22_secrets_vault/README.md) |
| **验收标准** | immutable Secret 修改被 API 403 拒绝；卷挂载方式下轮换（删建同名）后容器内新值生效而 env 方式不生效（对照记录）；etcd 侧该 Secret 为密文（复用项目 2 断言） |

**🤖 开始提示词**：
> `我要做 CKS 项目「Secret 正确用法」。请给：同一 Secret 的卷挂载版与 env 版两份 podinfo 部署、immutable 创建与修改被拒演示、轮换后两种注入方式生效差异的验证命令、etcd 密文复核。附验收断言。只输出配置与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 17：沙箱运行时 gVisor

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 条命令 |
| **核心知识点** | RuntimeClass、runsc、沙箱与普通容器隔离差异、Kata 对比 |
| **覆盖考纲** | Microservice：「Understand and implement isolation techniques (multi-tenancy, sandboxed containers, etc.)」 |
| **环境** | killercoda ⚠️（gVisor 需要在节点容器运行时层装 runsc——本机容器套容器的 kind 做不了；Linux 宿主的 kind 可以，方法写进提示词备查） |
| **验收标准** | killercoda 节点装 runsc 并注册 sandbox RuntimeClass；指定 RuntimeClass 的 Pod 内 `dmesg`/`uname` 呈现 gVisor 特征（如 uname 出现 gVisor 字样），普通 Pod 对照无；尝试直连宿主 /proc 的行为两侧表现不同（对照记录） |

**🤖 开始提示词**：
> `我在 Linux 节点做 CKS 项目「gVisor 沙箱」。请给：节点安装 runsc 并配置 containerd runtime、注册 sandbox RuntimeClass、沙箱 Pod 与普通 Pod 的特征对照验证命令（uname/dmesg/挂载视图）、以及"若节点是容器（kind）为什么装不了"的简注。附验收断言。只输出命令与配置。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 18：Pod-to-Pod mTLS 加密

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | Istio strict mTLS、PeerAuthentication、侧车证书轮换观察、明文请求被拒对照 |
| **覆盖考纲** | Microservice：「Implement Pod-to-Pod encryption (Cilium, Istio)」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1；基础：[labs/13](../labs/13_service_mesh/README.md)（本项练考法：strict 模式与明文拒绝验证） |
| **验收标准** | strict 模式下未挂 sidecar 的客户端访问 podinfo 被拒（connection reset/403 断言），带 sidecar 客户端 200；tcpdump 抓 podinfo 流量看不到明文 HTTP（密文断言） |

**🤖 开始提示词**：
> `我要做 CKS 项目「Pod-to-Pod mTLS」。请给：istioctl 部署（profile=default 精简参数）、podinfo 注入 sidecar、PeerAuthentication strict、未注入客户端被拒与注入客户端 200 的对照验证、以及容器内 tcpdump 密文断言。附验收命令。只输出命令与配置。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第五阶段：供应链（项目 19-25）

> **目标**：从镜像瘦身到签名、SBOM、静态分析与准入策略——守住"东西是怎么进集群的"

### [ ] 项目 19：把胖镜像瘦成 distroless

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行 Dockerfile |
| **核心知识点** | 多阶段构建、distroless/base-nossl、非 root USER、体积与 CVE 双对比 |
| **覆盖考纲** | Supply Chain：「Minimize base image footprint」 |
| **环境** | 本机 ✅（docker buildx，arm64 原生） |
| **验收标准** | 同一 podinfo 类小应用：python:3.12 基底 vs distroless 镜像体积对比记录（预期差 10 倍级）；trivy 扫描 Critical/High 数量显著下降并留前后报告；瘦身后容器正常运行且以非 root 身份（id 断言） |

**🤖 开始提示词**：
> `我要做 CKS 项目「镜像瘦身」。请给：同一小应用（一个 FastAPI 或 Go 服务）的胖版与 distroless 多阶段 Dockerfile、构建命令、体积与 trivy 扫描的前后对比脚本、容器内非 root 断言。附验收命令。只输出 Dockerfile 与脚本。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 20：给镜像生成 SBOM 并检索高危组件

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行脚本 |
| **核心知识点** | syft SPDX/CycloneDX、SBOM 结构、jq 检索组件清单、SBOM 与扫描器互补关系 |
| **覆盖考纲** | Supply Chain：「Understand your supply chain (e.g. SBOM, CI/CD, artifact repositories)」 |
| **环境** | 本机 ✅（syft 已装） |
| **前置** | 项目 19 的镜像 |
| **验收标准** | 对项目 19 两个镜像各产出一份 SPDX JSON；脚本从 SBOM 中精确检出一个已知组件（如 musl/libssl）并打印版本；镜像删掉本地 tag 后 SBOM 仍能回答"里面有什么"（SBOM 独立价值断言） |

**🤖 开始提示词**：
> `我要做 CKS 项目「SBOM 生成与检索」。请写 sbom_audit.sh：syft 生成 SPDX JSON、jq 提取组件总数与前 10 大包、按关键字检索指定组件并输出版本；再演示"删除本地镜像后 SBOM 仍可查"。附验收断言。只输出脚本。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 21：Trivy 扫描门禁

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 行脚本 |
| **核心知识点** | trivy image --severity/--exit-code、门禁脚本化、报告留存、准入联动回顾 |
| **覆盖考纲** | Supply Chain：「Secure your supply chain (permitted registries, sign and validate artifacts, etc.)」 |
| **环境** | 本机 ✅（trivy 已装；基础：[labs/21](../labs/21_image_security/README.md)） |
| **前置** | 项目 19 |
| **验收标准** | scan_gate.sh：对瘦身影像 exit 0、对故意用 old 基底的胖影像 exit 1（Critical>0 即拒）；两次运行各留 JSON 报告；`--ignorefile` 精准豁免一个指定 CVE 后门禁转绿（豁免可审计） |

**🤖 开始提示词**：
> `我要做 CKS 项目「Trivy 扫描门禁」。请写 scan_gate.sh：参数收镜像名，Critical/High>0 时 exit 1、否则 0，报告按时间戳存目录；演示对好坏两镜像的不同退出码；再加 .trivyignore 精准豁免单个 CVE 的对照。附验收断言。只输出脚本。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 22：Cosign 签名、验签与防篡改

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 条命令 |
| **核心知识点** | cosign key 生成、sign/verify、签名与镜像 digest 绑定、本地 registry 离线闭环 |
| **覆盖考纲** | Supply Chain：「Secure your supply chain (permitted registries, sign and validate artifacts, etc.)」 |
| **环境** | 本机 ✅（cosign 已装；用本地 registry:2 容器做私有仓，全程离线） |
| **前置** | 项目 19；基础：[labs/21](../labs/21_image_security/README.md) |
| **验收标准** | 本地 registry 里 push→sign→verify 全通；篡改 tag 指向后 verify FAIL（摘要不匹配断言）；无签名的新镜像 verify 直接失败——三种结果各有命令级证据 |

**🤖 开始提示词**：
> `我要做 CKS 项目「Cosign 签名闭环」。请给：本地 registry:2 起仓并 push 镜像、cosign key 生成与 sign/verify 全流程、指向篡改与无签名两种失败场景的验证命令。附验收断言。只输出命令与注释。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 23：清单静态分析双件套

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行清单 + 脚本 |
| **核心知识点** | Kubesec 评分与风险点解读、kube-linter 规则集、修清单直到零违规 |
| **覆盖考纲** | Supply Chain：「Perform static analysis of user workloads and container images (e.g. Kubesec, KubeLinter)」 |
| **环境** | 本机 ✅（两工具为单二进制/docker 镜像，安装见环境配置） |
| **验收标准** | 同一份"坏清单"（latest 标签、无资源限制、root 运行）：kubesec 打出低分并逐条列出扣分点；kube-linter 报 ≥5 类违规；修复后 kubesec 分数提升且 kube-linter 零违规（前后报告留存） |

**🤖 开始提示词**：
> `我要做 CKS 项目「静态分析双件套」。请给：一份刻意包含 ≥5 类常见问题的坏 Deployment、kubesec scan 与 kube-lint 运行命令、逐条修复对照表（问题→修法），以及修后零违规的复检命令。附验收断言。只输出清单与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 24：OPA Gatekeeper 上线与官方库约束

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | Gatekeeper 架构（webhook + audit）、ConstraintTemplate/Constraint 两层、官方 gpi 库启用、拒登与审计报告 |
| **覆盖考纲** | 考纲未点名该工具（v1.34 已移出）——对应能力为「Use appropriate pod security standards」的准入实现与业界主流策略引擎，实务高频 |
| **环境** | 本机 kind ✅（helm 安装，镜像 arm64 ✅） |
| **前置** | 项目 1 |
| **⚠️ 风险** | 与 labs/21 的 Kyverno 定位相同（策略引擎二选一对比学），本清单选 Gatekeeper 因其 Rego 生态（项目 25 的 Rego 是 CKS 之外的长期能力） |
| **验收标准** | Gatekeeper 就绪后：禁 latest 约束下 `latest` 镜像 Pod 被 403 拒绝且错误信息含约束名；固定 tag 版通过；`kubectl get k8srequiredlabels` 等审计资源可见违规记录 |

**🤖 开始提示词**：
> `我要做 CKS 项目「Gatekeeper 上线」。请给：helm 安装 Gatekeeper（等 webhook 就绪的检查命令）、启用官方库中禁 latest 与必须带 labels 两条约束的完整 CT/Constraint 清单、违例 403 与合规通过的对照验证、审计违规查询。附验收断言。只输出命令与清单。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 25：自写 Rego 准入策略与单测

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~120 行 Rego + 测试 |
| **核心知识点** | Rego 语法（input.review、violation 规则）、ConstraintTemplate 内嵌、ginkgo/gunit 单测、opa test 本地快跑、match 只打目标命名空间 |
| **覆盖考纲** | 同项目 24（策略即代码能力深化） |
| **环境** | 本机 ✅（opa CLI + Go 已装，`go run` 跑 gatekeeper 测试套件） |
| **前置** | 项目 24 |
| **验收标准** | 自写 3 条策略（白名单 registry、必须配 resources.limits、必须 readOnlyRootFilesystem）单测全绿（`go test ./...` 断言）；部署违例清单逐条 403 且错误信息指向对应 constraint；合规清单通过 |

**🤖 开始提示词**：
> `我要做 CKS 项目「自写 Rego 策略与单测」。请给：3 条 ConstraintTemplate + Constraint（registry 白名单、必配 limits、readOnlyRootFilesystem）、每条配 ginkgo 单测（含违例与豁免用例）、本地 opa test/go test 跑法、以及 TargetKind 限定 target namespace 的 match 写法。附验收断言。只输出 Rego、测试与命令。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 第六阶段：检测、审计与响应（项目 26-31）

> **目标**：集群的"摄像头与保安"——审计日志、Falco 检测、告警联动、不可变运行时、取证闭环

### [ ] 项目 26：审计日志上线与取证检索

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~60 行配置 + 脚本 |
| **核心知识点** | audit policy（apiVersion audit.k8s.io/v1）、等级 None/Metadata/RequestResponse、kind apiserver extraArgs+extraMounts、jq 检索审计事件 |
| **覆盖考纲** | Monitoring/Logging/Runtime：「Use Kubernetes audit logs to monitor access」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 1 |
| **验收标准** | 审计策略上线后：执行"用项目 7 的 deployer 删一个 deployment"的模拟入侵，audit 文件里能 jq 精确检索出该条记录（user/verb/resource/响应码俱全）；high-volume 端点（get pods list）按策略只记 Metadata 级（体量对照） |

**🤖 开始提示词**：
> `我要做 CKS 项目「审计日志上线」。请给：audit policy YAML（删 deployment 记 RequestResponse、常规读记 Metadata、nonResourceURLs 降噪）、kind kubeadmConfigPatches 挂载与 --audit-log-path 等参数、重建后做一次模拟删除并用 jq 从审计文件检索该事件（含 user 与 response code）的完整命令。附验收断言。只输出配置与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 27：Falco 上岗抓第一只虫

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行配置 + 命令 |
| **核心知识点** | Falco 架构（syscall 事件→规则引擎）、helm 部署、modern_ebpf 驱动、规则命中输出解读 |
| **覆盖考纲** | Monitoring/Logging/Runtime：「Perform behavioral analytics to detect malicious activities」「Detect threats within physical infrastructure, apps, networks, data, users and workloads」（v1.34 未点名工具；Falco 为该域事实标准） |
| **环境** | 本机 kind ⚠️ 开工探活（容器 VM 内核 7.2.12 满足 modern_ebpf ≥5.8，预期可行；首次开工验证 falco Pod Ready 且能产事件，fallback 去 killercoda） |
| **前置** | 项目 1 |
| **验收标准** | falco DaemonSet 全节点 Running；在靶子 Pod 里 exec 一个 shell，falco 日志秒级输出 `Terminal shell in container` 事件（priority、container 名俱全）；自测脚本把该场景一键复现 |

**🤖 开始提示词**：
> `我要做 CKS 项目「Falco 上岗」。请给：helm 安装 falco（modern_ebpf 模式、容忍 kind 控制面 taint 的 values）、确认事件输出的两种方式（logs 与 grpc）、以及在靶子 Pod 里触发 Terminal shell in container 规则并抓到事件的完整命令。附验收断言与探活检查点。只输出命令与配置。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 28：自写 Falco 规则三条

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~80 行 YAML 规则 |
| **核心知识点** | 规则三要素（condition/output/priority）、macro 复用、list 参数化、exceptions、rules.d 挂载热加载 |
| **覆盖考纲** | Monitoring/Logging/Runtime：「Detect threats…」行为规则编写能力（考场常考改规则） |
| **环境** | 本机 kind ✅（前置：项目 27 正常产事件） |
| **前置** | 项目 27 |
| **验收标准** | 自定义 3 条规则逐条真实触发并截获事件：①读 ServiceAccount token 文件 ②写 /etc/ 下文件 ③连外网 4444 端口（模拟挖矿池，用 list 参数化 IP）；每条都验证"合规动作不告警、违规动作必告警"双向断言 |

**🤖 开始提示词**：
> `我要做 CKS 项目「自写 Falco 规则」。请给：rules.d 自定义规则文件（读 SA token、写 /etc、连指定 IP:4444 三条，用 macro 与 list 参数化、附 exceptions 示例）、挂载进 falco 的 values 改法、每条规则的触发与反向（合规不告警）验证命令。附验收断言。只输出规则与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 29：告警管道 falcosidekick

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~40 行配置 |
| **核心知识点** | falcosidekick 部署与对接、falcosidekick-ui、webhook 自定义接收、最小告警优先级过滤 |
| **覆盖考纲** | Monitoring/Logging/Runtime：「Investigate and identify phases of attack and bad actors within the environment」（检测后的响应通道） |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 28 |
| **验收标准** | falco 事件经 sidekick 到达 UI 并可见（含项目 28 的自写规则事件）；一个本地 webhook 接收容器（busybox http）收到结构化 JSON 告警；priority 过滤生效（Warning 以下不外发，断言收不到） |

**🤖 开始提示词**：
> `我要做 CKS 项目「falcosidekick 告警管道」。请给：falco values 里对接 sidekick+UI 的配置、一个接收 webhook 的本地调试容器、按 priority 过滤外发的设置与验证（Warning 以上才到达）。附验收断言。只输出配置与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 30：把靶子硬化到不可变

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~50 行 YAML |
| **核心知识点** | readOnlyRootFilesystem + emptyDir 豁免、non-root 全家桶、运行时防篡改组合、业务无伤验证 |
| **覆盖考纲** | Monitoring/Logging/Runtime：「Ensure immutability of containers at runtime」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 11、14 |
| **验收标准** | 加固版 podinfo：容器内尝试写根路径与 /etc 全 FAIL、临时目录经 emptyDir 可写且业务正常；镜像内无 shell 也无法被 exec 注入（distroless 断言）；业务探测 200（无伤断言）；与默认版对照记录 |

**🤖 开始提示词**：
> `我要做 CKS 项目「运行时不可变」。请给：podinfo 的不可变加固清单（readOnlyRootFilesystem、emptyDir 写入点、runAsNonRoot、无 shell 镜像）、写根路径与写临时目录的正反验证命令、业务无伤探测。附验收断言。只输出清单与命令。`

**完成日期**：________
**踩坑记录**：________

---

### [ ] 项目 31：入侵取证与时间线还原

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~30 条命令 + 1 份报告 |
| **核心知识点** | 多源证据交叉（falco 事件、audit 日志、Pod 现场 ephemeral debug）、攻击时间线五阶段、事件报告模板 |
| **覆盖考纲** | Monitoring/Logging/Runtime：「Investigate and identify phases of attack and bad actors within the environment」 |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 26、27、28；基础：[labs/26](../labs/26_ephemeral_debug/README.md) |
| **验收标准** | 按"剧本"演练一次入侵（exec 进容器 → 读 SA token → 外连 4444）后，从三个证据源各取至少 1 条记录并按时间排序成时间线；产出的 incident-report.md 覆盖五阶段（初始访问/执行/持久化/渗出/痕迹）且每条结论有证据引用 |

**🤖 开始提示词**：
> `我要做 CKS 项目「入侵取证」。请给：一次模拟入侵的剧本命令（分阶段）、从 falco 输出/audit 日志/Pod 现场（kubectl debug）提取证据的命令、按时间戳合并成时间线的 jq/脚本、以及 incident-report.md 的骨架模板。附验收断言。只输出命令与模板。`

**完成日期**：________
**踩坑记录**：________

---

## 🗂️ 终极串联

### [ ] 项目 32：🏁 红蓝对抗全链路演练

| 项目信息 | 详情 |
|:---|:---|
| **行数** | ~100 行剧本脚本 |
| **核心知识点** | 攻防全链路（供应链准入→运行时检测→审计溯源→加固闭环）、演练剧本化、失败注入 |
| **覆盖考纲** | 六域综合（一次演练串起：坏镜像被 Gatekeeper 拦（域 5）→ 绕过者被 Falco 抓（域 6）→ 审计日志定位操作者（域 1/6）→ 修复并回归（域 4）） |
| **环境** | 本机 kind ✅ |
| **前置** | 项目 24、26、27、28（至少） |
| **验收标准** | 剧本三幕全自动跑通：红队用未签名+latest 镜像部署被 403 拒（第一幕断言）；改用合规但含后门行为的镜像上线后 Falco 秒级告警、audit 日志定位到"操作者"（第二幕断言）；加固准入与规则后复跑全绿（第三幕断言）；产出演练复盘记录 |

**🤖 开始提示词**：
> `我要做 CKS 项目「红蓝对抗全链路」。请给 war_game.sh 剧本：三幕（拦截/检测溯源/加固回归）、每幕前置检查与成败断言、失败即停、结尾输出演练复盘摘要（各防线命中统计）。只输出脚本与注释。`

**完成日期**：________
**踩坑记录**：________

---

## 📅 周计划

| 周次 | 内容 | 项目数 |
|:---|:---|:---:|
| **第 1 周** | 项目 1-5（靶场与集群基线） | 5 |
| **第 2 周** | 项目 6-9（访问与身份硬化） | 4 |
| **第 3 周** | 项目 10-13（内核与宿主） | 4 |
| **第 4 周** | 项目 14-18（工作负载暴露面） | 5 |
| **第 5 周** | 项目 19-23（供应链：镜像/签名/静态分析） | 5 |
| **第 6 周** | 项目 24-25（Gatekeeper 与 Rego 深练） | 2 |
| **第 7 周** | 项目 26-31（检测、审计与响应） | 6 |
| **第 8 周** | 项目 32 红蓝对抗 + killer.sh 模考 + 查漏 | 1 |

## 🏆 里程碑

- [ ] **完成项目 1-5** → 有一套安全靶场，能对控制面做 CIS 级体检与收口
- [ ] **完成项目 6-9** → 身份与访问最小化改造能力（SA/RBAC/API/升级）
- [ ] **完成项目 10-13** → 内核层容器约束能力（seccomp/capabilities/AppArmor/宿主面）
- [ ] **完成项目 14-18** → 工作负载纵深防御能力（PSS/网络/Secret/沙箱/mTLS）
- [ ] **完成项目 19-25** → 供应链守门能力（瘦身/SBOM/扫描/签名/静态分析/准入策略自写）
- [ ] **完成项目 26-31** → 检测与响应能力（审计/Falco 规则/告警/不可变/取证）
- [ ] **全部完成** → 一次完整攻防演练跑通，具备 CKS 实操能力，进 killer.sh 模考

## 📝 每日日志

| 日期 | 项目 | 耗时 | 收获 | 踩坑 |
|:---|:---|:---:|:---|:---|
| | | | | |

## 🔧 环境配置

```bash
# 0. 已就绪（2026-10-28 实测）：
#    docker(OrbStack, 容器 VM 内核 7.2.12) / kind / kubectl / helm
#    trivy ✅ cosign ✅ syft ✅ jq ✅ yq ✅ / go 1.26
#    实测结论：容器 VM 内核未启用 AppArmor（AppArmor 项目走 killercoda）；seccomp 可用 ✅

# 1. 需安装（按阶段用到再装）：
brew install kube-linter opa                      # 项目 23/25
brew install kubesec 2>/dev/null || true          # 项目 23：kubesec 可能无 brew formula，用容器跑：
#   docker run --rm -it securitywithoutborders/kubesec scan /dev/stdin < deploy.yaml
docker pull registry:2                            # 项目 22：本地私有仓库（离线签名闭环）
docker pull ghcr.io/stefanprodan/podinfo          # 靶子应用（多架构镜像）
# 项目 3 kube-bench / 项目 27 falco：均为集群内部署（Job/DaemonSet），无需本机安装

# 2. 每项目开工前：
kind get clusters | grep -q '^cks$' || echo "先做项目 1 建靶场"
kubectl config current-context                    # 确认在 cks 集群上，别打到别的集群
```

## ⚠️ 与已有清单的关系

| 已有资产 | 关系 |
|:---|:---|
| [cka.md](cka.md) | 前置认证线：CKS 报考必须先有有效 CKA；两份清单同为可跑小项目形态（CKA 管理与调度、CKS 安全），环境互相复用（k8s-learn、killercoda、lima VM） |
| [cka-drills/](cka-drills/) | 环境复用：killercoda kubeadm 环境的用法（项目 9/12/13/17）；项目 9 与 drills/02 同源不同目标（安全语境的升级） |
| labs/11 + 34（Ingress/cert-manager） | 项目 4 的基础：TLS 收口只练考法，不重复讲 Ingress 概念 |
| labs/12（NetworkPolicy） | 项目 15 的基础：默认拒绝考法强化 |
| labs/13（Service Mesh） | 项目 18 的基础：strict mTLS 考法强化 |
| labs/19（RBAC） | 项目 7 的基础：考法是 resourceNames 级收窄 |
| labs/20（Pod Security） | 项目 11/14 的基础：考法是 enforce 矩阵与 dry-run 校验 |
| labs/21（镜像安全） | 项目 21/22 的基础；labs/21 用的是 Kyverno，本清单用 Gatekeeper——两个策略引擎各练一个，对比认知 |
| labs/22（Vault） | 项目 16 提及动态凭证方向，本清单不深入（那是 labs/22 的主题） |
| labs/26（Ephemeral Debug） | 项目 31 的基础：取证现场进入手段 |

## 🧪 环境能力实测与探活表

| 能力 | 计划 | 实测结论（2026-10-28） |
|:---|:---|:---|
| seccomp | 项目 10 本机 kind | ✅ 容器 VM 内核支持（docker info 含 seccomp） |
| AppArmor | 项目 12 | ❌ 本机不可行——容器 VM（OrbStack，内核 7.2.12）未启用 AppArmor LSM，`/sys/module/apparmor/parameters/enabled` 不存在；kind 节点共享该内核 → 走 killercoda |
| Falco modern_ebpf | 项目 27 本机 kind | ⚠️ 待开工探活——内核 7.2.12 ≥ 5.8 预期可行，首次开工验证 |
| kube-bench in kind | 项目 3 本机 kind | ⚠️ 待开工探活——社区有适配 kind 的 Job 模板，非官方保证，有 killercoda fallback |
| gVisor | 项目 17 | ❌ 本机不可行（runsc 需装进节点容器运行时层，容器套容器做不了）→ 走 killercoda / Linux 宿主 kind |
| kubeadm 就地升级 | 项目 9 | ❌ kind 不支持节点版本就地升级 → 走 killercoda |
| 镜像构建/本地仓库 | 项目 19/22 本机 | ✅ docker buildx + registry:2（arm64 镜像存在） |

## 📚 来源

- [CNCF CKS Curriculum v1.34（官方考纲 PDF）](https://github.com/cncf/curriculum)
- [Falco 官方文档](https://falco.org/docs/)
- [OPA Gatekeeper 官方文档](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [kube-bench（Aqua Security）](https://github.com/aquasecurity/kube-bench)
- [killercoda（免费在线 Ubuntu/kubeadm 环境）](https://killercoda.com/)
