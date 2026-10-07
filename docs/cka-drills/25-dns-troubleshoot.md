# CKA 开工包 · 项目 25：DNS 故障排查

> 对应清单：`docs/cka.md` 项目 25 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 本题实测价值远超预期：**抓到一个真实 CoreDNS 故障 + 一个方法论级测试陷阱**。

## 📝 题面（考场原题风格）

> `Task:` Pods in namespace `apps` cannot resolve any DNS names. Diagnose the
> DNS resolution chain and fix the issue. (Weight: 5%)
>
> 目标用时：12 分钟

## 🧪 实测一：真实故障——coredns 插件 not ready（非注入，环境自然发生）

**背景**：OrbStack 挂起-恢复事故后 16 小时，所有 Pod 解析失败。

```
诊断链：
① kubectl -n kube-system get pods -l k8s-app=kube-dns   → 全部 Running（别被骗！）
② kubectl -n kube-system logs deploy/coredns | tail      → 两条关键日志：
   [WARNING] plugin/kubernetes: starting server with unsynced Kubernetes API
   [INFO] plugin/ready: Plugins not ready: "kubernetes"     ← Running ≠ 健康
③ 修复：kubectl -n kube-system rollout restart deploy/coredns
④ 验证 ready：port-forward 到 pod:8181 → curl /ready → OK
```

**教训**：容器 Running 只代表进程活着；CoreDNS 的 kubernetes 插件 informer 卡死
（API 长连接被挂起事故打死且未自愈）时对外表现就是全部解析失败。**"组件级挂死→重启负载"
是排障的合法终手段**，考场 Node NotReady/控制面题同理。

## 🧪 实测二：注入故障——kube-dns svc selector 被改坏

```
注入：kubectl -n kube-system patch svc kube-dns \
      -p '{"spec":{"selector":{"k8s-app":"kube-dns-broken"}}}'
症状：kubectl -n kube-system get ep kube-dns → <none>，全集群解析失败
排查：get ep（空）→ describe svc 看 selector → get pods --show-labels 对比 → 修回 selector
恢复：ep 重新列出 coredns podIP:53/:9153 ✅
```

## 🧪 实测三（方法论级）：busybox nslookup 不做 search 域迭代

故障全部修复后，`nslookup kubernetes.default` 仍 NXDOMAIN，但
`nslookup kubernetes.default.svc.cluster.local` 成功返回 10.96.0.1——
**CoreDNS 是好的，是测试命令的锅**：

| 查询 | 结果 | 原因 |
|:---|:---|:---|
| `nslookup kubernetes.default` | ❌ NXDOMAIN | busybox nslookup **原样发出单次查询**，不走 search 域迭代 |
| `nslookup kubernetes` | ❌ 同上 | 同上 |
| `nslookup kubernetes.default.svc.cluster.local` | ✅ 10.96.0.1 | 全 FQDN 无需迭代 |
| `wget http://kube-dns.kube-system.svc:9153/metrics` | ✅ 拉到内容 | wget 用 getaddrinfo，**有**迭代 |

**考场纪律**：验证 DNS 一律用**全 FQDN**，或用 wget/容器内应用实测；别用裸名 nslookup
的 NXDOMAIN 误判 DNS 故障（resolv.conf 的 `search`/`ndots:5` 只对 getaddrinfo 系生效）。

## ⚠️ 五大丢分点

1. **排查顺序**：`resolv.conf`（nameserver 是谁）→ FQDN 直查（隔离 search 域因素）→ `get ep -n kube-system kube-dns`（有端点吗）→ selector/标签对比 → coredns 日志 + `:8181/ready`。
2. **Running 迷惑弹**：coredns 全绿但仍不通——必须看日志的 `Plugins not ready` 和 8181 ready 端点。
3. **NP 误伤 DNS**：egress 类 NetworkPolicy 漏放 UDP/TCP 53 到 kube-system（项目 16 的坑），症状同为全解析失败——查完 coredns 查客户端的策略。
4. **svc selector 是整体替换**：patch 时写全要保留的键；tamper 类故障的修复就是把它改回与 pod label 一致。
5. **重启是终手段不是第一反应**：先走完四步链拿到证据（日志 unsynced）再 rollout restart；上来就重启=考场丢过程分。

## 🧹 重练

```bash
# 注入：patch kube-dns selector 为错误值 → 闭卷走排查链 → 修复
kubectl -n kube-system get ep kube-dns   # 每步盯这个
```
