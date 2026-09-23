# 24 · 日志收集：EFK 栈

> `kubectl logs` 只能看单个 Pod，跨节点排障时日志散落在几十台机器上。本实验搭建经典 EFK 栈：**Fluent Bit DaemonSet** 在每个节点尾读容器日志文件，补全 Kubernetes 元数据后转发给 **Elasticsearch** 建立倒排索引，**Kibana** 提供检索界面——让所有 Pod 日志在一处可查、可过滤、可聚合。

## What

| 组件 | 角色 |
|------|------|
| Fluent Bit（DaemonSet，每节点一个） | tail 节点上的容器日志文件，补全 K8s 元数据后转发 |
| Elasticsearch | 倒排索引，全文检索与聚合 |
| Kibana | 检索与可视化界面 |

一句话心智模型：**应用只管往 stdout 打印，采集、索引、检索全部由基础设施接管**——一条日志的旅程：containerd 落盘成文件 → Fluent Bit tail 采集 → kubernetes filter 补元数据 → 按天写入 ES 索引 → Kibana 查询。

## Why

容器化把日志从"一台机器一个文件"变成了"几十台机器 × 每台几十个短命容器"：Pod 重建后日志对象就没了，跨节点排障要逐台 ssh 翻文件。集中式日志把"找日志"从运维动作变成一次检索查询——`log.level:ERROR AND kubernetes.namespace_name:"logging-demo"` 这样的过滤，只有日志进了统一索引才可能。

## How

```bash
cd labs/24_logging_efk
./logging_efk.sh install   # 部署 Elasticsearch + Kibana + Fluent Bit DaemonSet
./logging_efk.sh deploy    # 部署多副本 demo 应用，产生日志
./logging_efk.sh verify    # Kibana 中检索 demo 日志，验证元数据与结构化字段
./logging_efk.sh clean
```

Fluent Bit 采集配置三段（`manifests/logging_efk.yaml`）：

```ini
[INPUT]
    Name   tail
    Path   /var/log/containers/*.log
```

```ini
[FILTER]
    Name kubernetes
    Kube_URL https://kubernetes.default.svc:443
    Merge_Log On
```

```ini
[OUTPUT]
    Index k8s-logs
    Logstash_Format On     # -> k8s-logs-YYYY.MM.DD
```

无死角采集的调度配置——显式容忍全部 taint，控制面节点的 kubelet/etcd 日志同样要采：

```yaml
tolerations: [{operator: Exists}]
```

## Deep Dive

**为什么采集的是文件而不是容器接口**：containerd 把每个容器的 stdout/stderr 落成宿主机文件（`/var/log/containers/*.log`），Fluent Bit 以 tail 方式读取。这个设计让应用只需"往 stdout 打印"，完全不感知采集器的存在；容器崩溃后日志仍在磁盘上不丢失；且与运行时无关——docker/containerd 换来换去管道不变。代价是符号链接解析与轮转处理需要 `Refresh_Interval` 和 `Skip_Long_Lines` 配合。

**kubernetes filter：给裸日志补上下文**：原始日志行里只有容器 hash。filter 用 Fluent Bit 的 ServiceAccount 反查 API Server，把 namespace/pod_name/container_name/container_id/docker_id 注进每条记录——注意 label 默认**不会**注入，需显式配置 Labels（本实验未启用）。`Merge_Log On` 再把 JSON 格式的日志体自动展开成结构化字段，结构化检索才成为可能。这也是清单里 RBAC 只授 `pods/namespaces` 只读权限的原因，且必须用 ClusterRole + ClusterRoleBinding——filter 要跨命名空间读 Pod 元数据。

**索引策略：按天切分**：`Logstash_Format On` 产出 `k8s-logs-YYYY.MM.DD`。按天分索引是日志保留管理的基石：删除 30 天前数据 = 删除整个索引（秒级），而不是对巨型索引做昂贵的按文档删除。生产环境再配 ILM 策略自动完成 hot→warm→delete 迁移。

**DaemonSet 全覆盖**：默认 taint 会阻止 DaemonSet 上控制面节点，`operator: Exists` 容忍全部 taint 才能覆盖全部节点——采集覆盖面与 lab 07 的 DaemonSet 模型完全一致。

## Q&A

**Q1: EFK 的资源开销怎么控制？**
ES 是内存大户，给单独的节点池 + local-path/NVMe 存储；Fluent Bit 限 `Mem_Buf_Limit` 防止日志洪峰打爆节点。日志管道的每个环节都要假设"上游可能瞬间放大 100 倍"。

**Q2: 存储成本太高有什么替代？**
Loki：只索引 label 不索引全文（LogCLI 按 selector 过滤），存储成本降一个数量级——Grafana 生态下常替代 EFK。取舍是放弃了全文检索的灵活性，复杂的多条件模糊查询不如 ES。

**Q3: 多团队共用一套 ES 怎么隔离？**
按 namespace 建独立索引 + Kibana space，配合 ES 安全模块做权限隔离——索引命名规范（`k8s-<ns>-*`）在一开始就要定好，事后迁移索引的成本很高。

**Q4: 高频 DEBUG 日志怎么办？**
采样与降噪前移：在 Fluent Bit filter 里丢弃或采样，别把带宽和存储浪费在垃圾数据上。日志管道的带宽是全节点共享的，垃圾数据进来之前挡掉永远是最便宜的。
