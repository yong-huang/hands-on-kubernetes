# CKA 开工包 · 项目 16：NetworkPolicy 默认拒绝与精准放行

> 对应清单：`docs/cka.md` 项目 16 ｜ 环境：独立 kind 集群 `cka-netpol`（Calico v1.33 operator 执行策略）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。**本机已搭好专用靶场并保留**，重练零准备；本文末尾附完整重建命令。

## 📝 题面（考场原题风格）

> `Task:` In namespace `netpol-demo`, first deny all ingress and egress traffic.
> Then allow: (a) pods with label `role=frontend` to reach pods `role=backend`
> on TCP 80; (b) backend pods to perform DNS lookups (UDP/TCP 53 to kube-system).
> Verify with wget from allowed and denied pods. (Weight: 7%)
>
> 目标用时：15 分钟

## ✅ 考场最优解（三份 YAML，实测全过）

```yaml
# 1. 全 namespace 默认拒绝（空 podSelector + 双向 policyTypes）
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-all, namespace: netpol-demo}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# 2. 放行 ingress：role=frontend → role=backend TCP 80
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-frontend-to-backend, namespace: netpol-demo}
spec:
  podSelector: {matchLabels: {role: backend}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {role: frontend}}}]
    ports: [{protocol: TCP, port: 80}]
---
# 3. 放行 frontend egress：→ backend:80 + → kube-dns:53 (UDP+TCP)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-frontend-egress, namespace: netpol-demo}
spec:
  podSelector: {matchLabels: {role: frontend}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {role: backend}}}]
    ports: [{protocol: TCP, port: 80}]
  - to:
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
      podSelector: {matchLabels: {k8s-app: kube-dns}}
    ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
```

## 🧪 实测证据链（2026-10-06，Calico 执行）

| 检查 | 命令要点 | 结果 |
|:---|:---|:---|
| 基线（无策略） | frontend/evil wget backend-svc | 双双 `backend-ok`（策略对象存在≠被执行，CNI 得是真执行的） |
| ✅ 正：白名单全链路 | frontend → `http://backend-svc`（走 DNS） | `backend-ok` |
| ❌ 反：evil 走域名 | evil wget backend-svc | `wget: bad address`（**它的 egress 全被拒，DNS 先死**） |
| ❌ 反：evil 绕开 DNS 走 IP | evil wget `http://<backendPodIP>/` | `download timed out`（**纯 ingress 拦截实锤**） |
| ❌ 反：backend 出站被断 | backend `nslookup kubernetes.default` | `connection timed; no servers could be reached`（egress 拒绝实锤） |

**方法论**：验证 ingress 拦截必须用 **Pod IP 直连**（排除 DNS 干扰）；验证 egress 拦截用 nslookup——「bad address」和「timeout」是两种不同的死法，分别对应「DNS 出不去」和「包进不来」。

## ⚠️ 五大丢分点

1. **DNS 例外忘放（考题第一坑）**：egress 一 deny，域名解析先死。任何「allow X to Y」的题，白名单客户端通常都要补 53 端口 UDP+TCP 双协议到 kube-system 的 kube-dns。
2. **namespaceSelector + podSelector 联写语义**：两者写在**同一个** to/from 元素里=「且」（该命名空间内且带该标签，上面 YAML 的 DNS 放行就是）；分成两个元素=「或」——语义天差地别。
3. **空 podSelector={} 不是没写**：`podSelector: {}` 匹配所有 pod（default-deny 的关键）；干脆不写 podSelector 字段策略不合法。
4. **策略叠加取并集**：多条策略对同一 pod 的效果是并集，不存在「后写的覆盖先写的」。
5. **CNI 不执行策略的假绿**：kind 默认 kindnet 会「创建成功但零隔离」——本靶场用 Calico；考场上策略类题目都是真实执行的，无需担心。

## 🧹 重练（本机靶场已保留，直接开做）

```bash
kubectl config use-context kind-cka-netpol
kubectl -n netpol-demo get netpol -o yaml > /tmp/np-backup.yaml   # 想对照时再看
kubectl -n netpol-demo delete netpol --all && kubectl apply -f 你的答案
# 正反验证命令照抄上面证据链表格
```

## 🔧 靶场完整重建命令（当前 cka-netpol 若被删，约 10 分钟）

```bash
# 1. 建集群（本机已有 kindest/node:v1.36.1 镜像；若提示拉取失败先 docker tag 3489c7674813 kindest/node:v1.36.1）
kind create cluster --name cka-netpol --image kindest/node:v1.36.1

# 2. Calico CRD（GitHub raw 被墙，走 gh-proxy 镜像站；文件含 26 个 CRD，2 个校验失败可忽略）
curl -sL "https://gh-proxy.com/https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/operator-crds.yaml" -o /tmp/operator-crds.yaml
kubectl apply --server-side --force-conflicts -f /tmp/operator-crds.yaml

# 3. Helm 装 Calico（chart v3.33.0 托管在 tigera.io 可达；必须关 whisker——它需要那个校验失败的 CRD）
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm install calico projectcalico/tigera-operator -n tigera-operator --create-namespace \
  --version v3.33.0 \
  --set 'installation.calicoNetwork.ipPools[0].cidr=10.244.0.0/16' \
  --set 'installation.calicoNetwork.ipPools[0].encapsulation=VXLAN' \
  --set whisker.enabled=false
kubectl -n kube-system delete ds kindnet        # 摘掉 kindnet 防双 CNI

# 4. busybox 灌进节点（kind load 在 containerd 2.x 有 digest bug，用 docker save | ctr import）
docker save busybox:1.36 | docker exec -i cka-netpol-control-plane ctr --namespace k8s.io images import -

# 5. 部署靶场三 Pod + svc（命令见上）
```
