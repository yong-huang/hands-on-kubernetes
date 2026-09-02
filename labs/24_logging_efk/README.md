# 日志收集（EFK Stack）

## 1. 文件结构

```
24_logging_efk/
├── README.md              # 本文档
├── logging_efk.sh         # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── logging_efk.yaml   # 演示用的 K8s 清单
└── images/
    ├── log_pipeline.architecture.json  # 图源（Archify Typed JSON IR）
    ├── log_pipeline.html               # 交互版架构图
    └── log_pipeline.svg                # 双主题矢量版（本文档 §5 内嵌）
```

## 2. 项目概述

`kubectl logs` 只能看单个 Pod，跨节点排障时日志散落在几十台机器上。本项目（`logging_efk.yaml` + `logging_efk.sh`）搭建经典 EFK 栈：**Fluent Bit DaemonSet** 在每个节点尾读容器日志文件，补全 Kubernetes 元数据后转发给 **Elasticsearch** 建立倒排索引，**Kibana** 提供检索界面——目标是让所有 Pod 日志在一处可查、可过滤、可聚合。

---

## 3. 核心机制解析

### 1. 为什么采集的是文件而不是容器接口

```yaml
[INPUT]
    Name   tail
    Path   /var/log/containers/*.log
```

containerd 把每个容器的 stdout/stderr 落成宿主机文件，Fluent Bit 以 tail 方式读取。这个设计让应用只需"往 stdout 打印"，完全不感知采集器的存在；容器崩溃后日志仍在磁盘上不丢失；且与运行时无关——docker/containerd 换来换去管道不变。代价是符号链接解析与轮转处理需要 `Refresh_Interval` 和 `Skip_Long_Lines` 配合。

### 2. kubernetes filter：给裸日志补上下文

```ini
[FILTER]
    Name kubernetes
    Kube_URL https://kubernetes.default.svc:443
    Merge_Log On
```

原始日志行里只有容器 hash。filter 用 fluent-bit 的 ServiceAccount 反查 API Server，把 namespace/pod_name/container_name/container_id/docker_id 注进每条记录（label 默认**不会**注入，需显式配置 Labels；本实验未启用）；`Merge_Log On` 再把 JSON 格式的日志体自动展开成结构化字段。之后 `log.level:ERROR AND kubernetes.namespace_name:"logging-demo"` 这样的检索才成为可能。这也是清单里 RBAC 只授 `pods/namespaces` 只读权限的原因。

### 3. 索引策略：按天切分

```ini
[OUTPUT]
    Index k8s-logs
    Logstash_Format On     # -> k8s-logs-YYYY.MM.DD
```

按天分索引是日志保留管理的基石：删除 30 天前数据 = 删除整个索引（秒级），而不是对巨型索引做昂贵的按文档删除。生产环境再配 ILM 策略自动完成 hot→warm→delete 迁移。

### 4. DaemonSet + tolerations：无死角采集

```yaml
tolerations: [{operator: Exists}]
```

控制平面节点的 kubelet/etcd 日志同样有价值，默认 taint 会阻止 DaemonSet 上去，显式容忍全部 taint 才能覆盖全部节点。RBAC 部分 ClusterRole + ClusterRoleBinding 因为 filter 要跨命名空间读 Pod 元数据。

---

## 4. 可视化

![EFK 日志链路](images/log_pipeline.svg)

一条日志的旅程：应用只往 stdout 打印 → containerd 落盘成文件 → Fluent Bit（DaemonSet，每节点一个）tail 采集 → kubernetes filter 反查 API Server 补元数据、Merge_Log 展开结构化字段 → 写入 Elasticsearch 按天分索引 → Kibana 检索。节点边界框强调"采集发生在节点本地"，工程师的查询不再受单机限制。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/24_logging_efk/images/log_pipeline.html)（或本地打开 [`images/log_pipeline.html`](images/log_pipeline.html)）。

---

## 5. 工程延伸

- **资源隔离**: ES 是内存大户，单独的节点池 + local-path/NVMe 存储；Fluent Bit 限 `Mem_Buf_Limit` 防止打爆节点
- **Loki 替代**: 若只索引 label 不索引全文（LogCLI 按 selector 过滤），存储成本降一个数量级——Grafana 生态下常替代 EFK
- **多租户**: 按 namespace 建独立索引 + Kibana space，配合 ES 安全模块做权限隔离
- **采样与降噪**: 高频 DEBUG 先在 Fluent Bit filter 丢弃或采样，别把带宽和存储浪费在垃圾数据上
