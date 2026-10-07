# CKA 开工包 · 项目 11：探针配置与自愈验证

> 对应清单：`docs/cka.md` 项目 11 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Add a liveness probe (HTTP GET `/healthz`, port 80, initialDelay 10,
> period 5) and a readiness probe (HTTP GET `/ready`, port 80) to deployment
> `api`. Verify that killing the health endpoint causes the container to
> restart. (Weight: 4%)
>
> 目标用时：10 分钟

## ✅ 考场最优解（实测可复现）

```bash
# busybox httpd 起一个可控的 web：/healthz /ready 各一个文件，删文件即"探针坏"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: apps}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
      - name: web
        image: busybox:1.36
        command: ["sh","-c","mkdir -p /www && echo ok > /www/healthz && echo ok > /www/ready && httpd -f -p 80 -h /www"]
        ports: [{containerPort: 80}]
        livenessProbe:
          httpGet: {path: /healthz, port: 80}
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          httpGet: {path: /ready, port: 80}
EOF

# 验证重启：删掉 healthz 文件，等 kubelet 连续 3 次探活失败（failureThreshold 默认 3）
POD=$(kubectl -n apps get pod -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl -n apps exec $POD -- rm /www/healthz
# ~30 秒后观察
kubectl -n apps get pod $POD        # RESTARTS 1
kubectl -n apps describe pod $POD | grep -E "Liveness probe failed|Killing"
```

## 🧪 实测证据链（2026-10-06）

```
Warning  Unhealthy  (x3 over 41s)  kubelet  Liveness probe failed: HTTP probe failed with statuscode: 404
Normal   Killing                   kubelet  Container web failed liveness probe, will be restarted
# RESTARTS 0 → 1；重启后新容器重建 /www（command 重新执行），1/1 Running 自愈完成
```

**三探针职责速记**：liveness=挂了杀（重启容器）；readiness=没准备好不接流量（摘 Endpoints，不重启）；startup=给慢启动豁免期（成功后才轮到 liveness）。

## ⚠️ 五大丢分点

1. **探针字段位置写错**：probe 是 **container 级**字段（`spec.containers[].livenessProbe`），不是 pod 级——手写 YAML 放错层级直接校验报错。
2. **initialDelay 过短误杀**：慢启动应用（JVM 类）配 initialDelay 5s 会被反复杀死；解法是 startupProbe 而不是拉大 delay。
3. **readiness 与 liveness 用同一个依赖 DB 的接口**：DB 抖动 → 全部容器被杀重启雪崩。考场上按题面写即可，但概念题要能答出「readiness 失败只摘流量」。
4. **验证不动手**：题面说 verify，就必须制造一次失败（exec 删文件 / 杀进程）+ 贴 RESTARTS 上涨证据。
5. **tcpSocket/httpGet/exec 三种 handler 混淆**：考题给哪种照抄哪种；`port` 写容器端口名（`containerPort` 的 name）比写数字更不容易错。

## 🧹 重练

```bash
kubectl -n apps delete deploy api --now
```
