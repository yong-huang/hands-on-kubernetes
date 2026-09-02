# Helm Chart 开发

## 1. 文件结构

```
27_helm_chart/
├── README.md              # 本文档
├── install.sh             # 全流程演示脚本（步骤见脚本头部注释）
├── manifests/
│   └── demo-chart/        # Helm Chart: templates + values
│       ├── Chart.yaml / values.yaml
│       └── templates/     # deployment/service/ingress/configmap + _helpers.tpl + NOTES.txt
└── images/
    ├── helm_pipeline.workflow.json  # 图源（Archify Typed JSON IR）
    ├── helm_pipeline.html           # 交互版流程图
    └── helm_pipeline.svg            # 双主题矢量版（本文档 §5 内嵌）
```

## 2. 项目概述

裸 `kubectl apply -f` 部署一个应用要维护四五份 YAML，换个环境改得满地找补。本项目（`manifests/demo-chart/` + `./install.sh`）从零写一个标准 Helm Chart——Deployment、Service、ConfigMap、Ingress 四件套加 `_helpers.tpl` 命名约定——完整走一遍 lint → template → install → upgrade → rollback → package 的开发闭环。目标是掌握"用一个 Chart 部署一套应用，用 values 描述所有环境差异"。

---

## 3. 核心机制解析

### 1. Chart 结构：模板与数据的分离

```text
manifests/demo-chart/
  Chart.yaml      # version(chart) 与 appVersion(镜像默认 tag) 解耦
  values.yaml     # 默认值
  templates/      # Go template + K8s manifest
  _helpers.tpl    # {{ include "demo-chart.fullname" . }}
```

模板里只写"形状"，值全部来自 `.Values`。`image.tag | default .Chart.AppVersion` 是惯用法：chart 升级与应用发版解耦——升级 chart 不动镜像版本，发新应用版本只改 appVersion。

### 2. Values 合并：三层覆盖优先级

```bash
helm upgrade demo ./manifests/demo-chart \
  --set image.tag=1.25.3 --reuse-values
```

优先级从低到高：chart 内置 values.yaml < `-f my-values.yaml` < `--set` 命令行。注意 Helm 3 里 upgrade **默认就复用**上次 release 的用户值（等价于隐式 `--reuse-values`）；`--set` 只覆盖显式给出的键。想回到"纯 chart 默认值 + 本次新值"必须显式传 `--reset-values`——不校验当前生效值直接 upgrade，才是生产事故的经典来源。

### 3. _helpers.tpl：命名约定决定多租户安全

```text
fullname = {{ .Release.Name }}-{{ .Chart.Name }}
labels: app.kubernetes.io/{name,instance,version}
```

所有资源名带 release 前缀、label 带 instance 标签，同一个 chart 才能以不同 release 名在同一命名空间部署多份而互不干扰（selector 精确匹配各自的 instance）。漏掉这一层，两个 release 会互相接管对方的 Pod。

### 4. Release 版本机制：Helm 的回滚底气

每次 `helm install/upgrade` 生成递增的 release 版本号，配置快照存在集群 Secret 里。`helm rollback demo 1` 秒级回到任意历史版本——但注意回滚的是**渲染产物**而非 Git 状态，真正的单一事实源应该还是 Git（见项目 28 ArgoCD）。

---

## 4. 可视化

![Helm 流水线](images/helm_pipeline.svg)

开发闭环画成流水线：三层 values 按优先级合并（chart 内置 < `-f` 文件 < `--set`）→ Go template 渲染成清单 → 校验提交 K8s API → 每次生成递增的 Release 快照（存集群 Secret）→ 工作负载运行。回滚分支点破一个认知：`helm rollback` 回滚的是**渲染产物**，真正的单一事实源仍应是 Git（见 28 ArgoCD）。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/labs/27_helm_chart/images/helm_pipeline.html)（或本地打开 [`images/helm_pipeline.html`](images/helm_pipeline.html)）。

---

## 5. 工程延伸

- **子 chart 与依赖**: Chart.yaml 的 dependencies 字段声明 Redis/PG 子 chart，父 values 里按子 chart 名覆盖其值
- **库 chart**: `type: library` 只提供模板不产生资源，把公共 deployment 模板抽给多个业务 chart 复用
- **OCI 分发**: `helm push demo-chart-0.1.0.tgz oci://registry/charts`，复用镜像仓库做 chart 分发，免建 ChartMuseum
- **测试**: helm unittest / chart-testing (ct lint-and-test)，把模板回归纳入 CI
