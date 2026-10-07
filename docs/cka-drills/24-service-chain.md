# CKA 开工包 · 项目 24：Service 不通全链路排查

> 对应清单：`docs/cka.md` 项目 24 ｜ 环境：独立集群 `cka-netpol`（Calico 真执行 NP）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。双故障注入，全程四步链路留痕。

## 📝 题面（考场原题风格）

> `Task:` From pod `client` in namespace `apps`, `curl cache-svc` times out.
> The service and pods exist. Systematically diagnose and fix all issues
> (there is more than one). (Weight: 7%)
>
> 目标用时：15 分钟

## 🧪 实测：双故障四步链（2026-10-06，cka-netpol + Calico）

故障注入：`cache` 容器监听 **8080**，svc `cache-svc` 的 targetPort 写成 **9090**（故障①）；
NetworkPolicy 只放行 `role=trusted` 来源（故障②，client 无此标签）。

```
[症状] client wget cache-svc → download timed out
第1步 get ep        → ep: 10.244.62.72:9090     ← 端点存在，但端口可疑！
第2步 describe 对比  → svc TargetPort: 9090/TCP vs 容器 Port: 8080/TCP → 故障①实锤
     修① patch svc targetPort=8080 → 复测：仍 timeout
第3步 get netpol    → allow-only-trusted 要求 podSelector role=trusted，client 没有 → 故障②
     修② kubectl label pod client role=trusted
第4步 复测           → cache-ok ✅
```

**⚠️ 实测关键现象**：故障①的「connection refused」被故障②的 NP **掩盖成了 timeout**——
包到不了容器（策略在节点层丢弃），根本轮不到端口拒绝。**timeout 优先怀疑 NP/drop，
refused 才是端口层**；但四步链必须走完，因为两个故障是叠加的。

## 「每步正常输出长什么样」对照表

| 步骤 | 命令 | 健康输出 | 异常信号 |
|:---|:---|:---|:---|
| ① 端点 | `kubectl get ep <svc>` | `podIP:targetPort` 列表 | `<none>`（selector 失配，见项目 14）或**端口对不上容器**（本题） |
| ② 端口 | `describe svc` + `describe pod` | TargetPort == 容器 Port | 数字不一致 |
| ③ 策略 | `kubectl get netpol -o yaml` | 有一条例外放行你 | 白名单没包含 client 的标签/命名空间 |
| ④ 终验 | `exec client -- wget -T 3` | 200/内容 | timeout=被丢包；refused=端口不通 |

## ⚠️ 五大丢分点

1. **故障叠加时只修一个**：题面明说 "more than one"——修完一个必须复测再找下一个，每步留命令痕迹（评分看过程）。
2. **timeout vs refused 误诊**：见上，症状与故障层次不是一一对应，四步链是去歧义手段不是走过场。
3. **改 NP 前先看现有策略**：`get netpol` 白名单若按标签放行，最小修复是给 client 贴标签（本题解法）；擅自 patch NP 删策略可能违反题目"otherwise unchanged"。
4. **ep 端口≠svc port**：ep 显示的是 targetPort 侧（podIP:9090），跟 svc 的 port:80 无关——别看错对照对象。
5. **无 NP 能力的 CNI 上练是假绿**：kind 默认 kindnet 策略不生效，本题必须在 cka-netpol（Calico）上练。

## 🧹 重练

```bash
kubectl config use-context kind-cka-netpol
kubectl -n apps delete pod/cache pod/client svc/cache-svc netpol/allow-only-trusted --now
# 重新注入：expose --target-port=9090 + NP 白名单 role=trusted，闭卷走四步
```
