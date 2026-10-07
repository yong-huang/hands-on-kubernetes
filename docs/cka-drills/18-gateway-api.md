# CKA 开工包 · 项目 18：Gateway API 实战（HTTPRoute/Gateway）

> 对应清单：`docs/cka.md` 项目 18 ｜ 环境：kind 集群 `k8s-learn`（GatewayClass `eg` = Envoy Gateway 已预装）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。本题实测收获 4 个考场级知识点，见加粗。

## 📝 题面（考场原题风格）

> `Task:` Using Gateway API, create a Gateway `prod-gw` (class from the
> installed GatewayClass) listening on port 80, and an HTTPRoute `api-route`
> for host `api.example.com` routing path `/v1` to service `api-v1` on port
> 8080. Verify with curl through the Gateway address. (Weight: 4%)
>
> 目标用时：12 分钟

## ✅ 考场最优解（实测全过）

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: prod-gw, namespace: apps}
spec:
  gatewayClassName: eg          # 先 kubectl get gatewayclass 看有哪些
  listeners: [{name: http, port: 80, protocol: HTTP}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: api-route, namespace: apps}
spec:
  parentRefs: [{name: prod-gw}] # attach 机制：route 挂到 gateway
  hostnames: [api.example.com]
  rules:
  - matches: [{path: {type: PathPrefix, value: /v1}}]
    backendRefs: [{name: api-v1, port: 8080}]
```

## 🧪 实测证据链（2026-10-06）

```
[正] curl -H "Host: api.example.com" http://<代理节点IP>:<nodePort>/v1/  → api-v1-gw
[反] 错 Host → 404；错路径 → 404（访问日志 response_flags=NR, route_not_found）
```

**四个实测知识点（考场级）**：

1. **EG 的代理不在 Gateway 的命名空间**：本机 EG 版本把代理部署在 `envoy-gateway-system`，名字 `envoy-apps-prod-gw-<hash>`（hash 由 Gateway 名派生）。找代理 svc：
   `kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=prod-gw`
2. **kind 无 LB 控制器 → Gateway `Programmed=False AddressNotAssigned`**：LoadBalancer 型代理 svc 的 EXTERNAL-IP 永远 pending——**这是环境现象不是配置错误**，路由功能完全正常。考场集群有真 LB，不会遇到；但要看懂这个状态。
3. **`externalTrafficPolicy: Local` 的丢包行为**：经 NodePort 访问代理时，**只有代理 Pod 所在节点的 IP 能通**，其他节点连接超时（无本地端点直接丢包）——先查 `get pod -o wide` 找到代理在哪个节点再 curl。
4. **xDS 传播延迟**：后端 Pod 重建换 IP 后立刻 curl 会拿到空响应/旧上游——等 endpoint 传播 + 几秒 xDS 下发再验。

**另一族 404（与项目 15 呼应）**：访问日志 `response_code_details: via_upstream` = 后端自己回的 404（GET /v1 打到 docroot=/www 下没有 v1 目录）；修法是让后端按 `/v1/` 提供文件，或给 route 加 `URLRewrite` filter。busybox 对无尾斜杠目录还会 302（`location: /v1/`）。

## ⚠️ 五大丢分点

1. **gatewayClassName 抄错**：先 `kubectl get gatewayclass`，本机是 `eg`；考场装什么抄什么。
2. **parentRefs 漏写**：没有 parentRef 的 HTTPRoute 是孤儿，谁都不会实现它。
3. **404 无脑改路由**：先分清三层——envoy 的 `route_not_found`（NR）=规则没匹配；`via_upstream`=后端回的；连不上=端口/策略问题（对照项目 15 的判别法）。
4. **验证时忽略代理位置**：LB 地址 pending 时（kind 环境）改用 nodePort，且只能打代理所在节点的 IP（见知识点 3）。
5. **条件状态误判**：`Accepted=True` + `ResolvedRefs=True`（route 侧）+ `Programmed=False`（gateway 侧，kind 无 LB）三者要分开读——别看到 False 就推翻自己的 YAML。

## 🧹 重练

```bash
kubectl -n apps delete pod/api-v1 svc/api-v1 gateway/prod-gw httproute/api-route --now
# 注意：Gateway 删除会连带删掉 EG 的代理 deploy/svc；重建 Gateway 会生成新 nodePort，重新查
```

## 🔧 本机环境备注

k8s-learn 预装了 Envoy Gateway（`eg` class）和 Istio（`istio` class），labs/33 的材料可用于在新集群安装。Gateway API CRD 版本 v1.2.x；考场按 kubernetes.io 的 Gateway API 文档核对字段。
