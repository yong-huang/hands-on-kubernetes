# CKA 开工包 · 项目 17：CoreDNS 服务发现与域名解析

> 对应清单：`docs/cka.md` 项目 17 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Create a Headless Service `db-hl` for pods labeled `app=db`.
> From a temporary busybox pod, resolve both the short name and the full FQDN
> of the service and of individual pods. Save the DNS record output to
> `/root/dns-report.txt`. (Weight: 4%)
>
> 目标用时：8 分钟

## ✅ 考场最优解（实测全过）

```bash
kubectl -n apps run db-0 --image=busybox:1.36 --labels=app=db --command -- sleep 3600
kubectl -n apps run db-1 --image=busybox:1.36 --labels=app=db --command -- sleep 3600
kubectl -n apps expose pod db-0 --name=db-hl --port=5432 --cluster-ip=None   # headless 关键

kubectl -n apps run dns-test --image=busybox:1.36 --restart=Never --command -- sleep 300
# 四种解析（输出重定向到报告文件即完成题目要求）
kubectl -n apps exec dns-test -- sh -c '
  nslookup db-hl > /root/dns-report.txt;                        # 短名
  nslookup db-hl.apps.svc.cluster.local >> /root/dns-report.txt # svc FQDN
  nslookup 10-244-2-27.apps.pod.cluster.local >> /root/dns-report.txt'  # pod FQDN
```

## 🧪 实测记录（2026-10-06）

**resolv.conf 三要素**（DNS 排障第一现场）：

```
search apps.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

**四种解析实测**：

| 查询 | 形式 | 结果 |
|:---|:---|:---|
| svc 短名 | `db-hl` | ✅ search 域补全成 FQDN，返回 **2 个 Pod A 记录**（headless 特征） |
| svc FQDN | `db-hl.apps.svc.cluster.local` | ✅ 同上，`<svc>.<ns>.svc.cluster.local` |
| pod FQDN | `10-244-2-27.apps.pod.cluster.local` | ✅ **IP 点改横线** + `<ns>.pod.cluster.local` |
| 普通 svc | （对照） | 只返回 Service 的 ClusterIP 一条记录 |

**⚠️ 实测踩坑**：pod 域名只写 `10-244-2-27`（不带后缀）会 NXDOMAIN——`ndots:5` 会先补 search 域试成 svc 形式，而 pod 记录在 `pod.cluster.local` 下。FQDN 必须写全。

## ⚠️ 五大丢分点

1. **Headless 写法**：`clusterIP: None`（字符串）；`kubectl expose --cluster-ip=None` 一步到位，比 YAML 少出错。
2. **ndots:5 语义**：少于 5 个点的名字先走 search 域——解释了「短名为什么能通」「残缺 FQDN 为什么不通」两个现象，概念题常考。
3. **FQDN 格式记错层级**：svc 是 `.svc.cluster.local`，pod 是 `.pod.cluster.local`，中间都带 `<namespace>`。
4. **Headless 返回值期待错**：headless 没有 VIP，DNS 直接回**全部 Pod IP**——题目问「解析出几个地址」要答副本数。
5. **清理命令混写（实测三次踩）**：`kubectl delete pod a b svc/c` 这种「裸名+资源/名」混用会报错，统一用 `pod/a pod/b svc/c` 形式。

## 🧹 重练

```bash
kubectl -n apps delete pod/db-0 pod/db-1 svc/db-hl --now
```
