# CKA 开工包 · 项目 15：Ingress 路由规则配置

> 对应清单：`docs/cka.md` 项目 15 ｜ 环境：kind 集群 `k8s-learn`（ingress-nginx 已预装，hostPort 80/443）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。本题实测浓缩出「三层 404 判别法」，见下。

## 📝 题面（考场原题风格）

> `Task:` Create an Ingress `app-ingress` in namespace `apps` for host
> `app.example.com`: path `/api` (Prefix) routes to service `api` on port 80,
> all other paths route to service `web` on port 80. (Weight: 4%)
>
> 目标用时：10 分钟

## ✅ 考场最优解（实测全过）

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: apps
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /   # 后端收 / 而不是 /api，见实测
spec:
  ingressClassName: nginx
  defaultBackend:
    service: {name: web, port: {number: 80}}
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service: {name: api, port: {number: 80}}
```

验证（kind 清单里 controller 用 hostPort 80/443，curl 任意节点 IP）：

```bash
NIP=$(kubectl -n ingress-nginx get pod -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.hostIP}')
curl -H "Host: app.example.com" http://$NIP/         # → web-v1（defaultBackend）
curl -H "Host: app.example.com" http://$NIP/api/     # → api-v1
curl -H "Host: app.example.com" http://$NIP/api/v1   # → api-v1（Prefix 连续段匹配）
curl -H "Host: other.example.com" http://$NIP/       # → 404
```

## 🧪 实测：三层 404 判别法（考场读 404 的核心技能）

| 现象 | 404 页面长相 | 含义 | 动作 |
|:---|:---|:---|:---|
| ① 规则没挂上 | nginx 官方样式（`<center>nginx</center>`） | controller 收到但无匹配规则 | 查 ingressClassName / controller 日志 |
| ② 无后端端点 | 同上（日志有 `does not have any active Endpoint`） | Service 的 Endpoints 为空 | 回项目 14 排障 |
| ③ 路由已通、路径没对上 | **后端自己的 404**（busybox 样式「The requested URL was not found」） | Ingress 把原始 `/api/` 透传给后端，后端 docroot 对不上 | 加 rewrite-target 注解 |

实测顺序：先见 ③（busybox 404，说明已路由到 api），加 `rewrite-target: /` 注解后全部通过。另外实测确认：**Prefix 是按「/」分段连续匹配**——`/api` 不会匹配 `/apis`。

## ⚠️ 五大丢分点

1. **rewrite-target 想当然**：题目说 `/api` 路由到 api 服务，没说 rewrite；但后端若按根路径提供服务就必须加注解——先 curl 看后端 404 长相再决定（判别法③）。
2. **ingressClassName 漏写**：不写 class 的 Ingress 没人认领（除非 controller 配了 `--watch-ingress-without-class`，本机恰好配了——别赌考场的）。
3. **defaultBackend 忘配**：题面「all other paths」就是 defaultBackend；漏了非匹配路径全部落 nginx 默认页。
4. **controller 未装误判**：`kubectl get ingress` ADDRESS 一直空 / `get svc -n ingress-nginx` External IP pending ≠ 题目错误，是环境问题——先确认 controller 存活。
5. **pathType 三值混淆**：Prefix（分段前缀）/ Exact（精确）/ ImplementationSpecific（留给控制器）；考场题面写什么抄什么。

## 🧹 重练

```bash
kubectl -n apps delete ingress app-ingress --now
# ingress-nginx 保留（k8s-learn 本就预装），重练只重建 Ingress 与后端
```

## 🔧 本机环境备注

k8s-learn 已预装 ingress-nginx（22d 前装的，hostPort 80/443 模式）。OrbStack 下节点 IP（192.168.107.x）宿主机直连可达，无需 port-forward。给新 kind 集群装 controller：用 `labs/11_ingress/manifests/ingress-nginx-kind.yaml`（本地缓存）+ `kind load docker-image registry.k8s.io/ingress-nginx/controller:v1.15.1 registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9 --name <集群名>`；admission job 若因镜像 digest 卡住可删，不影响路由。
