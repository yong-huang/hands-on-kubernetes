# CKA 开工包 · 项目 10：ConfigMap 与 Secret 配置注入

> 对应清单：`docs/cka.md` 项目 10 ｜ 环境：kind 集群 `k8s-learn`（v1.36.1）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Create a ConfigMap `app-config` containing key `APP_MODE=prod`, and a
> Secret `db-cred` with keys `user=admin, pass=secret123`. Inject the ConfigMap
> as a volume at `/etc/conf` and the Secret as env vars into a new pod `app`
> in namespace `apps`. (Weight: 4%)
>
> 目标用时：10 分钟

## ✅ 考场最优解

```bash
kubectl create configmap app-config -n apps --from-literal=APP_MODE=prod
kubectl create secret generic db-cred -n apps \
  --from-literal=user=admin --from-literal=pass=secret123

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: apps
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    envFrom:
    - secretRef:
        name: db-cred
    volumeMounts:
    - name: conf
      mountPath: /etc/conf
  volumes:
  - name: conf
    configMap:
      name: app-config
EOF

# 验收取证
kubectl -n apps exec app -- env | grep -E '^(user|pass)='    # user=admin / pass=secret123
kubectl -n apps exec app -- cat /etc/conf/APP_MODE           # prod
```

## 🧪 实测记录（2026-10-06）

- Secret 在 etcd 中以 base64 存：`{"pass":"c2VjcmV0MTIz","user":"YWRtaW4="}`——base64 ≠ 加密，进容器后是明文。
- `envFrom` 后**键名即环境变量名**：容器内 `user=admin`、`pass=secret123`。
- ConfigMap 卷挂载后**键名即文件名**：`/etc/conf/APP_MODE` 内容 `prod`。

## ⚠️ 五大丢分点

1. **两种注入写法记混**：`envFrom`（secretRef/configMapRef，键名=变量名）vs `env[].valueFrom.secretKeyRef`（可重命名变量）——YAML 手写时最容易把 `secretRef` 写成 `configMapKeyRef`。
2. **base64 误区**：Secret 不是加密；知识题常问「Secret 数据在 etcd 里是否加密」——默认只是 base64，加密要靠 etcd encryption at rest 配置。
3. **`data` vs `stringData`**：手写 Secret YAML 时 `data` 要自己 base64，`stringData` 写明文由 API 转——考场手滑双写会冲突。
4. **挂载路径覆盖**：`mountPath: /etc/conf` 是目录挂载（键变文件）；若写单个文件路径要用 `subPath`，否则把 `/etc` 整个盖掉，Pod 起不来。
5. **更新语义**：env 注入的 ConfigMap/Secret 改了**不会**热更新（要重建 Pod）；volume 挂载的会自动同步（约 1 分钟内）；`immutable: true` 的改了要删了重建。

## 🧹 重练

```bash
kubectl -n apps delete pod/app cm/app-config secret/db-cred --now
```
