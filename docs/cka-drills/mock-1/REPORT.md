# CKA 全真模考 #1 · 首轮成绩单（2026-10-07）

## 📊 结果

| 项目 | 结果 |
|:---|:---|
| 通过题数 | **16/16** |
| 得分 | **100/100（100%）🏆** |
| ⚠️ 成绩口径 | **出题人自验卷**——27 份开工包全部在手 + 题目即出自这些开工包，此分只证明工具链闭环可用，不代表考试水平。考生首轮目标：≥66 分 |

## 🧾 逐题参考解答（考完再看）

| # | 参考解法（一句话） |
|:--|:---|
| T1 | `create ns/sa` + `create role --verb=get,list --resource=pods` + `create rolebinding --serviceaccount=audit:scanner`；`auth can-i` 双验证 |
| T2 | `KUBECONFIG=a:b kubectl config view --flatten > tmp && mv` → `rename-context → use-context`（--flatten 必加） |
| T3 | 三个 `pod-security.kubernetes.io/*=baseline` 标签；privileged Pod `--dry-run=server` 触发 admission 得 Forbidden 证据 |
| T4 | `drain --ignore-daemonsets --delete-emptydir-data`（**有裸 Pod 时必须 --force**，本轮即被 T13 的裸 Pod 挡住）→ label → taint → uncordon |
| T5 | `patch strategy` → `set image '*=nginx:1.27'` → `rollout status` → `undo --to-revision=1`（容器名≠deploy 名，通配符最稳） |
| T6 | `create configmap/secret` + Pod：`envFrom.secretRef` + `configMap` 卷挂 `/etc/cfg` |
| T7 | `nodeName` 直派（绕过调度器与 taint）与 `nodeSelector+toleration`（走调度器）双 Pod 都落 worker2 |
| T8 | `expose --port=80 --target-port=8080` ×2，NodePort 用 patch 钉 30080 |
| T9 | 空 `podSelector:{}` + `policyTypes:[Ingress]` 全拒 + 白名单 `from.podSelector app=client` + `port 80` |
| T10 | `ingressClassName: nginx` + `defaultBackend: svc-b` + `/a Prefix → svc-a` + **rewrite-target: /**（busybox 后端对 /a 会 404，项目 15 教训直接命中） |
| T11 | PV `storageClassName:""` + PVC `volumeName` 静态指派 + hostPath PV 加 nodeAffinity 钉节点（持久性保障） |
| T12 | SC 带 `is-default-class` 注解 + 摘旧默认 + PVC 不写 SC 名；**WaitForFirstConsumer 要有真消费者 Pod 才绑** |
| T13 | image 可 patch；command/nodeSelector/resources immutable → 删了重建（项目 22 四态表） |
| T14 | PVC spec immutable → 删了重建（不写 SC 名走默认）；消费 Pod 在场即触发绑定 |
| T15 | `get ep` 发现 targetPort 9090≠容器 8080（修①）；timeout≠refused → 查 NP 端口 9999（修②）；四步链全程留痕 |
| T16 | Pending+无调度事件+无 PodScheduled → `kube-system` 里 scheduler pod 数 0 → manifest 归位即自愈 |

## 🔧 考官工具链三轮打磨（setup/grade 的 bug 即教学素材）

1. **setup 幂等性三连坑**：ns 未就绪就 apply（NotFound）→ 显式 `create --dry-run=client | apply`；对象已存在 create 报错 → delete 后 create 或 apply；**delete 混写 `pvc a b pod/c` 直接 parse error 中断脚本**（同一坑第 4 次踩！全斜杠形式）。
2. **grade 误判三连**：分数累加写死 +2（应为权重）；uncordon 后 `spec.unschedulable` **字段消失而非 false**（jsonpath 空值要按成功处理）；判分 exec `deploy/web` 但考生建的是裸 Pod——**判分器只该断言题目要求的结果，不该绑定考生的实现方式**。
3. **T2 素材段整个漏写**：setup 跑「成功」但 /tmp/exam 不存在——清单里"每题素材由 setup 生成"的承诺要逐条兑现，跑完 setup 应 `ls` 验收。

## 🎯 考生重考指南

```bash
bash docs/cka-drills/mock-1/setup.sh      # 重置全部素材与故障
# 120 分钟闭卷：docs/cka-drills/mock-1/EXAM.md（先看规则段）
bash docs/cka-drills/mock-1/examiner-t16.sh   # 做到最后一题时执行
bash docs/cka-drills/mock-1/grade.sh      # 判分：≥66 PASS
# 复盘：对照本 REPORT 的参考解法，错题回炉对应开工包
```

**首轮建议目标**：域 5 四题（T13-T16，共 30 分）先稳住——它们 100% 来自 22-30 开工包的原型；域 1/2 的 create 型题拼手速；T9/T10 拼判别法（DNS 迭代、404 三层）。
