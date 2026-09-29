# 27 · Helm Chart：模板与值的分离

> 裸 `kubectl apply -f` 部署一个应用要维护四五份 YAML，换个环境改得满地找补。本实验从零写一个标准 Helm Chart——Deployment、Service、ConfigMap、Ingress 四件套加 `_helpers.tpl` 命名约定——完整走一遍 lint → template → install → upgrade → rollback → package 的开发闭环。读完本篇，你将理解"模板与数据分离"的价值，以及 values 合并的默认行为为什么是最大的坑。

## Background

一个应用在三个环境部署，裸 YAML 的做法是把整份清单复制三份再各自改差异：镜像 tag、副本数、域名散落在每份文件的各个角落。改一行模板逻辑要同步三处，漏一处就是环境间漂移——"staging 好的，prod 不行"有一半根源在这。

配置管理工具的演进方向都是"不变的结构与可变的参数分离"：Ansible 有模板变量，Terraform 有 variables。Helm 把同样的思路带给 K8s 清单：模板只写形状，值全部来自 values 文件——环境差异收敛为两份可 diff 的 values，模板一处维护。

## What

Helm 把 K8s 清单拆成"模板"与"值"两层：模板里只写形状，值全部来自 `.Values`。Chart 的标准结构：

```text
manifests/demo-chart/
  Chart.yaml      # version(chart) 与 appVersion(镜像默认 tag) 解耦
  values.yaml     # 默认值
  templates/      # Go template + K8s manifest
  _helpers.tpl    # {{ include "demo-chart.fullname" . }}
```

一句话心智模型：**用一个 Chart 部署一套应用，用 values 描述所有环境差异**——可以把 chart 想象成"应用安装器"；但和安装器不同的是，它输出的不是二进制而是一套 K8s 清单，且每次安装/升级都留下可回滚的版本快照（Release，见 How It Works）。

| 文件 | 职责 |
|---|---|
| Chart.yaml | chart 元数据；`appVersion` 是镜像默认 tag |
| values.yaml | 默认值（被 -f / --set 覆盖） |
| templates/ | Go template（Go 语言的标准模板语法，`{{ }}` 占位符在渲染时替换成值）渲染的 K8s 清单 |
| _helpers.tpl | 命名约定等可复用模板片段 |

## When to Use

典型场景：同一服务发 dev/staging/prod（环境差异收敛为两份 values 文件，一份模板）；团队沉淀标准化的应用模板（新服务拷 chart 改 values 即上线）；把应用打包分发给别人（`helm package` + OCI 仓库）。

何时不用：单一环境、清单稳定不变的小工具（裸 YAML 更简单）；模板逻辑复杂到需要大量条件嵌套（考虑 Kustomize 的 overlay 模式或直接生成）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 裸 YAML | 直白但复制三份 | 单环境原型 |
| Helm | 模板 + values，生态最大 | 多环境、可分发（默认选择） |
| Kustomize | base + overlay 补丁，无模板引擎 | 差异是"小补丁"而非"参数化" |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；helm 已安装。

```bash
cd labs/27_helm_chart
./install.sh lint       # helm lint 模板静态检查
./install.sh template   # helm template 本地渲染，肉眼校验产物
./install.sh install    # helm install 部署 demo-chart
./install.sh upgrade    # --set image.tag=... 升级，观察 release 版本递增
./install.sh rollback   # helm rollback 回到历史版本
./install.sh package    # helm package 打包 tgz
```

诚实预期：install/upgrade 触发镜像拉取时 Pod 可能 Pending 数分钟；upgrade 成功的标志是 release 的 REVISION 递增 1；lint/template 报错时先看首个 error 行即可定位模板文件。

values 覆盖的三种写法（优先级从低到高：chart 内置 values.yaml < `-f my-values.yaml` < `--set` 命令行）：

```bash
helm upgrade demo ./manifests/demo-chart \
  --set image.tag=1.25.3 --reuse-values
```

模板里最常用的一个惯用法——chart 升级与应用发版解耦：

```text
image.tag | default .Chart.AppVersion
```

升级 chart 不动镜像版本，发新应用版本只改 appVersion。

## How It Works

**Values 合并的默认行为是最大的坑**：Helm 3 里 upgrade **默认就复用**上次 release 的用户值（等价于隐式 `--reuse-values`）；`--set` 只覆盖显式给出的键。

想回到"纯 chart 默认值 + 本次新值"必须显式传 `--reset-values`——不校验当前生效值直接 upgrade，才是生产事故的经典来源。

**_helpers.tpl：命名约定决定多租户安全**。

所有资源名带 release 前缀（`fullname = {{ .Release.Name }}-{{ .Chart.Name }}`）、label 带标准标签（`app.kubernetes.io/{name,instance,version}`），

同一个 chart 才能以不同 release 名在同一命名空间（K8s 的资源分组单位）部署多份而互不干扰（selector 即按 label 筛选资源的查询器，精确匹配各自的 instance 标签）。

漏掉这一层，两个 release 会互相接管对方的 Pod。

**Release 版本机制是 Helm 回滚的底气**：每次 `helm install/upgrade` 生成递增的 release 版本号，配置快照存在集群 Secret 里，

`helm rollback demo 1` 秒级回到任意历史版本——你在 `rollback` 步骤看到的秒级还原，读的就是这些 Secret 里的快照。

但注意——回滚的是**渲染产物**而非 Git 状态，真正的单一事实源应该还是 Git（见 lab 28 的 ArgoCD）。

## Pitfalls & Q&A

踩坑清单：

- upgrade 忘了带 values：Helm 3 会复用上次值，多数情况是你要的；确认"应该从默认值重算"时显式 `--reset-values`。
- 两个 release 在同一 namespace 互相接管 Pod：`_helpers.tpl` 的 instance 标签漏了。
- 模板改完直接 install：先 `helm lint` + `helm template` 本地校验，别拿集群当试错场。

**Q1: 一个 chart 需要附带 Redis/PostgreSQL 时怎么办？**
子 chart 与依赖：Chart.yaml 的 `dependencies` 字段声明子 chart，父 values 里按子 chart 名覆盖其值。Helm 负责拉取、渲染、按序部署，业务团队不必关心依赖的部署细节。

**Q2: 多个业务 chart 重复写同样的 Deployment 模板怎么收敛？**
库 chart：`type: library` 只提供模板不产生资源，把公共 deployment 模板抽给多个业务 chart 复用——组织级"标准工作负载模板"的载体。

**Q3: chart 打包后怎么分发？**
OCI 分发：`helm push demo-chart-0.1.0.tgz oci://registry/charts`，直接复用镜像仓库做 chart 分发，免建 ChartMuseum；拉取用 `helm pull oci://...`，与容器镜像同一套鉴权和基础设施。

**Q4: 模板改坏了怎么防？**
测试进 CI：helm unittest 做模板级单测、chart-testing（ct lint-and-test）做 lint + 安装冒烟，把模板回归纳入流水线——模板是代码，就要有代码的纪律。
