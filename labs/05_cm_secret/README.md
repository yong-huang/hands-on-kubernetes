# 05 · ConfigMap 与 Secret：配置与代码分离

> 把数据库地址、日志级别、密码写死在镜像里，环境一换就得重打镜像。ConfigMap / Secret 让"同一个镜像，配上不同配置跑 dev / staging / prod"成为可能——这是 12-Factor 第三条"在环境中存储配置"的 K8s 实现。

## 1. 为什么配置不能写死在镜像里

把 `db-prod.internal`、`LOG_LEVEL=info` 硬编码进镜像后：上测试环境要连 `db-test.internal`，重打镜像；临时开 `debug` 排查问题，再打一次。镜像越打越多，环境差异越来越大，最后没人说得清"哪个镜像配哪个环境"。

K8s 提供两个专门的对象：

- **ConfigMap**：非敏感配置（日志级别、端口号、nginx.conf）
- **Secret**：敏感配置（密码、Token、证书）

## 2. 总览：四种注入方式

![cm secret inject](images/cm_secret_inject.svg)
> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/05_cm_secret/images/cm_secret_inject.html)（或本地打开 [`images/cm_secret_inject.html`](images/cm_secret_inject.html)）。

ConfigMap（蓝）与 Secret（红）各自有两条路径进入容器，共四种组合：

| 方式 | YAML 字段 | 特点 |
|---|---|---|
| ① ConfigMap 单键 env | `env[].valueFrom.configMapKeyRef` | 一个键 → 一个环境变量 |
| ② ConfigMap 卷挂载 | `volumes[].configMap` | 每个键变成挂载目录下的一个文件 |
| ③ Secret 单键 env | `env[].valueFrom.secretKeyRef` | base64 自动解码后注入 |
| ④ Secret 卷挂载 | `volumes[].secret` | 每键一个文件，内容是解码后的明文，可设 `defaultMode: 0400` |

另有偷懒写法 `envFrom`：把整个 ConfigMap/Secret 的所有键一次性变成环境变量——方便，但有键名冲突风险。

热更新规则先记三句话，机制见 §5：**volume 会同步、env 不会、subPath 也不会**。

## 3. 快速开始

```bash
./cm_secret.sh         # 五步一条龙：
# 步骤1  kubectl create configmap --from-literal / --from-file
# 步骤2  kubectl create secret generic（并现场 base64 -d 验证"编码≠加密"）
# 步骤3  apply manifests/cm_secret.yaml，exec 验证 4 种注入方式
# 步骤4  patch ConfigMap，观察 volume 挂载热更新、env 纹丝不动
# 步骤5  清理全部资源
```

想手动把玩：

```bash
kubectl exec app-pod -- env | grep -E 'LOG_LEVEL|DB_PASSWORD'   # ①③ env 注入
kubectl exec app-pod -- ls -l /etc/config /etc/secret           # ②④ 卷挂载
kubectl exec app-pod -- cat /etc/secret/DB_PASSWORD              # Secret 卷里是解码后的明文
```

## 4. ConfigMap vs Secret

| 维度 | ConfigMap | Secret |
|---|---|---|
| 用途 | 非敏感配置 | 敏感数据（密码/证书/Token） |
| 存储形式 | 明文字符串 | base64 编码 |
| 大小限制 | 1MB（etcd 限制） | 1MB |
| 挂载文件权限 | 默认 0644 | 可设 `defaultMode: 0400` |
| 类型 | 无 | Opaque / kubernetes.io/tls / dockerconfigjson 等 |

最重要的认知——**base64 不是加密**——展开见 §6。

## 5. 热更新机制与 subPath 陷阱

kubelet 周期性检查（默认约 1 分钟）被挂载的 ConfigMap/Secret，内容变了就更新挂载目录（实际是**原子替换符号链接**）：

- **volume 挂载**：会热更新（应用是否重新读文件是应用自己的事）
- **env 注入**：**永不更新**——环境变量在容器启动时就固定了，改了 ConfigMap 也无济于事，必须重启 Pod
- **subPath 挂载**：**永不更新**——最经典的陷阱：

  ```yaml
  volumeMounts:
    - name: config-volume
      mountPath: /etc/nginx/nginx.conf   # 挂的是文件而不是目录
      subPath: nginx.conf
  ```

  这种写法 kubelet 不会同步更新，即使底层 ConfigMap 变了。原因：subPath 挂载被解析成绑定挂载，kubelet 的同步机制只作用于挂载点目录，不追踪 subPath 文件。想要"只挂一个文件且能热更新"，改用挂载整个目录 + 符号链接，或用 Reloader 之类的方案触发滚动重启。

`cm_secret.sh` 步骤 4 演示了前两条：patch ConfigMap 后轮询等待，`/etc/config/app.conf` 内容变了，而 `echo $LOG_LEVEL` 还是旧值。

## 6. Secret 的安全真相

![secret base64](images/secret_base64.svg)
> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/05_cm_secret/images/secret_base64.html)（或本地打开 [`images/secret_base64.html`](images/secret_base64.html)）。

写入链路：`stringData` 明文 → API Server 自动 base64 编码 → etcd 落盘；读取时 env / volume 自动解码为明文。**任何人** `echo 'UEBzc3cwcmQtMTIz' | base64 -d` 都能秒解——Secret 的"安全"来自配套设施：

1. **etcd 静态加密**：开启 `EncryptionConfiguration` 后，Secret 落盘前再加密一层（默认安装下在 etcd 里就是 base64 裸奔，生产集群必须开启）
2. **RBAC**：`secrets` 是独立资源类型，可细粒度控制谁有 get 权限
3. **审计日志**：谁读了哪个 Secret 有迹可循
4. **不进镜像层**：密码永远不在镜像里，避免 `docker history` 泄露

## 7. YAML 关键字段

```yaml
# Secret 用 stringData 免手动 base64：
stringData:
  DB_PASSWORD: "P@ssw0rd-123"   # API Server 自动编码存 etcd

# 单键注入环境变量：
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: DB_PASSWORD

# 卷挂载 + 权限收紧：
volumes:
  - name: secret-volume
    secret:
      secretName: db-secret
      defaultMode: 0400          # 只有 owner 可读，适合密码文件
```

## 8. 文件结构

```
05_cm_secret/
├── README.md               # 本文档
├── cm_secret.sh            # 命令行实战：create / 验证 / 热更新 / 清理
├── manifests/
│   └── cm_secret.yaml      # 2 个 ConfigMap + 1 个 Secret + 1 个消费 Pod
└── images/
    ├── cm_secret_inject.workflow.json          # 图源（Typed JSON IR）
    ├── cm_secret_inject.html        # 交互版（浏览器打开）
    └── cm_secret_inject.svg          # 双主题矢量版   
    ├── secret_base64.workflow.json          # 图源（Typed JSON IR）
    ├── secret_base64.html        # 交互版（浏览器打开）
    └── secret_base64.svg          # 双主题矢量版      
```

## 9. 深入要点

1. **Secret 到底安全吗？** base64 只是编码不是加密。真正的安全性靠：etcd 静态加密（`EncryptionConfiguration`）、RBAC、审计日志。默认安装下 Secret 在 etcd 里就是 base64 裸奔，生产集群必须开启加密。
2. **ConfigMap 大小限制 1MB**：etcd 的限制。大配置应拆分，或放对象存储/配置中心，ConfigMap 只存引用。
3. **subPath 不热更新**：面试高频陷阱题。subPath 挂载被解析成绑定挂载，kubelet 的同步机制只作用于挂载点目录，不追踪 subPath 文件。
4. **immutable 不可变配置**：`immutable: true` 的 ConfigMap/Secret 无法更新（只能删了重建）。好处：降低 kubelet watch 开销、防止误改、更安全。大规模集群推荐开启。
5. **env vs volume 怎么选？** 少量不常变的键值用 env（12-Factor 风格）；需要热更新或完整配置文件用 volume；敏感凭据优先 Secret volume（可设 0400）而不是 env（env 可能被日志、`/proc` 泄露）。

## 10. 总结

- 配置与代码分离：同一镜像 × 不同 ConfigMap/Secret = 多环境部署
- 四种注入方式 = {ConfigMap, Secret} × {env, volume}
- Secret 的 base64 **不是加密**，安全靠 etcd 加密 + RBAC + 审计的组合拳
- 热更新三句话：**volume 会同步、env 不会、subPath 也不会**
- 生产建议：敏感配置走 Secret volume + `defaultMode: 0400`，大配置放配置中心，不变的配置加 `immutable: true`

下一篇：06 讲卷与持久化存储（Volume / PV / PVC）。
