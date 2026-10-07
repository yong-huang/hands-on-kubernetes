# CKA 开工包 · 项目 13：Service 各类型与 kubectl expose

> 对应清单：`docs/cka.md` 项目 13 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Expose deployment `backend` (port 8080) as a ClusterIP Service
> `backend-svc` on port 80. Expose deployment `web` as a NodePort Service
> `web-svc` on nodePort 30080. Verify both from inside and outside the
> cluster. (Weight: 4%)
>
> 目标用时：10 分钟

## ✅ 考场最优解（实测全过）

```bash
# 后端：busybox httpd，backend 听 8080、web 听 80
kubectl create deployment backend -n apps --image=busybox:1.36 --replicas=2 \
  -- sh -c "mkdir -p /www && echo backend-v1 > /www/index.html && httpd -f -p 8080 -h /www"
kubectl create deployment web -n apps --image=busybox:1.36 --replicas=2 \
  -- sh -c "mkdir -p /www && echo web-v1 > /www/index.html && httpd -f -p 80 -h /www"

# expose 三连
kubectl -n apps expose deployment backend --name=backend-svc --port=80 --target-port=8080
kubectl -n apps expose deployment web --name=web-svc --port=80 --target-port=80 --type=NodePort
kubectl -n apps patch svc web-svc -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'   # 钉住 nodePort
kubectl -n apps expose deployment backend --name=backend-hl --port=80 --cluster-ip=None     # Headless

# 双路验证
kubectl -n apps run svc-test --image=busybox:1.36 --restart=Never --command -- sleep 120
kubectl -n apps exec svc-test -- wget -qO- -T 5 http://backend-svc        # → backend-v1
kubectl -n apps exec svc-test -- nslookup backend-hl                      # → 2 个 Pod IP
curl http://<nodeIP>:30080/                                               # → web-v1
```

## 🧪 实测证据（2026-10-06）

```
backend-svc   ClusterIP   80/TCP          wget → backend-v1 ✅
web-svc       NodePort    80:30080/TCP    宿主机 curl → web-v1 ✅
backend-hl    ClusterIP(None)             nslookup → 10.244.1.27 / 10.244.2.17（Pod IP 列表）✅
```

Headless 的判定特征：nslookup 返回**每个 Pod 的 A 记录**；普通 Service 只返回 Service 的 ClusterIP。

## ⚠️ 五大丢分点

1. **port / targetPort / nodePort 三者混**：`port`=Service 端口（客户端用），`targetPort`=容器端口（deployment 的实际监听口），`nodePort`=节点入口（30000-32767）。expose 时 `--port` 给 Service 口，`--target-port` 必须对准容器真端口，写错服务直接不通。
2. **题面指定 nodePort 却不钉**：expose 默认随机分配 nodePort，题面点名 30080 就必须 patch 钉住——评分按「nodePort==30080 且通」打。
3. **Headless 写法**：`clusterIP: None`（字符串 None），YAML 里裸 None 或 nil 都错；且 Headless 没有负载均衡/VIP，DNS 直接回 Pod IP。
4. **验证只做一半**：题面说 inside and outside——集群内 `kubectl exec ... wget` + 宿主机 `curl nodeIP:nodePort` 都要做，缺一边丢一半分。
5. **容器名踩坑（项目 8 同源）**：`create deployment` 后容器名=镜像名；expose 按 deployment 找端口时是读 template 里的 `containerPort`，busybox httpd 这类**没声明 containerPort** 的 deployment 用 `--target-port` 显式指定最稳。

## 🧹 重练

```bash
kubectl -n apps delete pod/svc-test deploy/backend deploy/web \
  svc/backend-svc svc/web-svc svc/backend-hl --now
```

## 🔧 本机环境备注

宿主机访问 NodePort 用节点 IP（`kubectl get nodes -o wide` 的 INTERNAL-IP，如 192.168.107.x）直连即可（OrbStack 网段可达）；标准 kind 集群则需 `kubectl port-forward` 或 extraPortMappings。apiserver 若 TLS 握手超时，多为 OrbStack 闲置挂起后转发慢恢复——等几秒重试或 `orb start`。
