# 05 · ConfigMap 与 Secret：配置与代码分离

> 把数据库地址、日志级别、密码写死在镜像里，环境一换就得重打镜像。ConfigMap / Secret 让"同一个镜像，配上不同配置跑 dev / staging / prod"成为可能——这是 12-Factor（十二要素应用方法论）第三条"在环境中存储配置"的 K8s 实现。读完本篇，你将掌握四种注入方式、热更新的三条铁律，以及 Secret 安全性的真实边界。

## Background

配置外置之前，应用的发布流程通常是"改配置 → 重打镜像 → 重新发布"：上测试环境要连 `db-test.internal`，重打镜像；临时开 `debug` 排查问题，再打一次。镜像越打越多，环境差异越来越大，最后没人说得清"哪个镜像配哪个环境"。

更糟的是密码进了镜像层，`docker history` 就能挖出来。

12-Factor 方法论在 2011 年就把"配置存进环境、与代码严格分离"列为要素之一。Kubernetes 用两个专门对象落地这条原则：ConfigMap 承载非敏感配置，Secret 承载敏感配置——镜像保持"一次构建、处处运行"，环境差异收敛为两份 YAML。

## What

**ConfigMap** 放非敏感配置（日志级别、端口号、nginx.conf），**Secret** 放敏感配置（密码、Token、证书）。

一句话心智模型：**同一镜像 × 不同 ConfigMap/Secret = 多环境部署**——但和"改配置文件"不同的是，配置的变更由 K8s 对象承载，可以版本化、可以做权限控制。

配置进入容器共四种组合——{ConfigMap, Secret} × {env, volume}：

| 方式 | YAML 字段 | 特点 |
|---|---|---|
| ① ConfigMap 单键 env | `env[].valueFrom.configMapKeyRef` | 一个键 → 一个环境变量 |
| ② ConfigMap 卷挂载 | `volumes[].configMap` | 每个键变成挂载目录下的一个文件 |
| ③ Secret 单键 env | `env[].valueFrom.secretKeyRef` | base64 自动解码后注入 |
| ④ Secret 卷挂载 | `volumes[].secret` | 每键一个文件，内容是解码后的明文，可设 `defaultMode: 0400` |

另有偷懒写法 `envFrom`：把整个 ConfigMap/Secret 的所有键一次性变成环境变量——方便，但有键名冲突风险。热更新规则先记三句话：**volume 会同步、env 不会、subPath 也不会**（机制见 How It Works）。

| 维度 | ConfigMap | Secret |
|---|---|---|
| 用途 | 非敏感配置 | 敏感数据（密码/证书/Token） |
| 存储形式 | 明文字符串 | base64 编码 |
| 大小限制 | 1MB（etcd 限制） | 1MB |
| 挂载文件权限 | 默认 0644 | 可设 `defaultMode: 0400` |

## When to Use

典型场景：同一套服务发 dev / staging / prod 三个环境（只换 ConfigMap）；给应用下发完整配置文件（volume 挂载）；给应用发数据库密码、TLS 证书（Secret）。

何时不用：大配置（超过 1MB 是 etcd 硬限制，放对象存储/配置中心，ConfigMap 只存引用）；需要频繁按请求变化的动态配置（这不是 K8s 配置对象的用途，考虑配置中心）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 配置打进镜像 | 改配置 = 重打镜像 | 配置永远不变的原型验证 |
| ConfigMap / Secret | 声明式、可版本化、可授权 | K8s 上运行的绝大多数应用 |
| 外部配置中心（Nacos 等） | 动态推送、灰度下发 | 需要不重启的运行时配置变更 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）。

```bash
cd labs/05_cm_secret
./cm_secret.sh         # 五步一条龙：
# 步骤1  kubectl create configmap --from-literal / --from-file
# 步骤2  kubectl create secret generic（并现场 base64 -d 验证"编码≠加密"）
# 步骤3  apply manifests/cm_secret.yaml，exec 验证 4 种注入方式
# 步骤4  patch ConfigMap，观察 volume 挂载热更新、env 纹丝不动
# 步骤5  清理全部资源
```

成功判据：步骤 4 里 `/etc/config/app.conf` 内容变成新值，而 `echo $LOG_LEVEL` 仍是旧值——亲眼看到"volume 会同步、env 不会"（具体输出以运行为准）。

想手动观察：

```bash
kubectl exec app-pod -- env | grep -E 'LOG_LEVEL|DB_PASSWORD'   # ①③ env 注入
kubectl exec app-pod -- ls -l /etc/config /etc/secret           # ②④ 卷挂载
kubectl exec app-pod -- cat /etc/secret/DB_PASSWORD              # Secret 卷里是解码后的明文
```

关键字段写法（`manifests/cm_secret.yaml`）：

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

## How It Works

**热更新机制**：kubelet（节点上按清单启停容器的组件）周期性检查（默认约 1 分钟）被挂载的 ConfigMap/Secret，内容变了就更新挂载目录（实际是**原子替换符号链接**）：

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

`cm_secret.sh` 步骤 4 演示了前两条：patch ConfigMap 后轮询等待，`/etc/config/app.conf` 内容变了，而 `echo $LOG_LEVEL` 还是旧值——你在输出里看到的"文件变、变量不变"，就来自这条机制。

**Secret 的安全真相**：写入链路是 `stringData` 明文 → API Server 自动 base64 编码 → etcd 落盘；读取时 env / volume 自动解码为明文。

**任何人** `echo 'UEBzc3cwcmQtMTIz' | base64 -d` 都能秒解——Secret 的"安全"来自配套设施：

1. **etcd 静态加密**：开启 `EncryptionConfiguration` 后，Secret 落盘前再加密一层（默认安装下在 etcd 里就是 base64 裸奔，生产集群必须开启）
2. **RBAC**：`secrets` 是独立资源类型，可细粒度控制谁有 get 权限
3. **审计日志**：谁读了哪个 Secret 有迹可循
4. **不进镜像层**：密码永远不在镜像里，避免 `docker history` 泄露

**immutable 不可变配置**：`immutable: true` 的 ConfigMap/Secret 无法更新（只能删了重建）。好处：降低 kubelet watch 开销、防止误改、更安全。大规模集群推荐开启。

## Pitfalls & Q&A

踩坑清单：

- 改了 ConfigMap 等 env 变化：等不到，env 永不更新——重启 Pod 才生效。
- subPath 挂单文件期待热更新：同样等不到（原因见 How It Works）。
- 把 ConfigMap 当数据库用：1MB 是硬上限，超限创建直接被拒。

**Q1: env 还是 volume，怎么选？**
少量不常变的键值用 env（12-Factor 风格）；需要热更新或完整配置文件用 volume；敏感凭据优先 Secret volume（可设 0400）而不是 env——env 可能被日志、`/proc` 泄露。

**Q2: 配置超过 1MB 怎么办？**
1MB 是 etcd 对 ConfigMap/Secret 的硬限制。大配置应拆分成多个对象，或放对象存储/配置中心，ConfigMap 只存引用——别把 ConfigMap 当数据库用。

**Q3: Secret 到底安全吗？**
base64 只是编码不是加密，安全性完全取决于配套设施（etcd 加密 + RBAC + 审计）。需要更强保证时看 lab 22 的 Vault 动态凭证——凭据用完即吊销，泄露窗口从"永久"压缩到 TTL 级别。
