# 27 · Helm Chart：模板与值的分离

> 裸 `kubectl apply -f` 部署一个应用要维护四五份 YAML，换个环境改得满地找补。本实验从零写一个标准 Helm Chart——Deployment、Service、ConfigMap、Ingress 四件套加 `_helpers.tpl` 命名约定——完整走一遍 lint → template → install → upgrade → rollback → package 的开发闭环。

## What

Helm 把 K8s 清单拆成"模板"与"值"两层：模板里只写形状，值全部来自 `.Values`。Chart 的标准结构：

```text
manifests/demo-chart/
  Chart.yaml      # version(chart) 与 appVersion(镜像默认 tag) 解耦
  values.yaml     # 默认值
  templates/      # Go template + K8s manifest
  _helpers.tpl    # {{ include "demo-chart.fullname" . }}
```

一句话心智模型：**用一个 Chart 部署一套应用，用 values 描述所有环境差异**——dev/staging/prod 的差别收敛为两份 values 文件，模板一处维护。

## Why

同一个应用在三个环境只有镜像 tag、副本数、域名不同，裸 YAML 却要把整份清单复制三份——改一行模板逻辑要同步三处，漂移迟早发生。Helm 的价值不是"模板引擎"本身，而是把"不变的结构"和"可变的参数"拆开之后，环境差异变得可评审（diff 两个 values 文件即可）、可复用（一个 chart 服务所有环境）。

## How

```bash
cd labs/27_helm_chart
./install.sh lint       # helm lint 模板静态检查
./install.sh template   # helm template 本地渲染，肉眼校验产物
./install.sh install    # helm install 部署 demo-chart
./install.sh upgrade    # --set image.tag=... 升级，观察 release 版本递增
./install.sh rollback   # helm rollback 回到历史版本
./install.sh package    # helm package 打包 tgz
```

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

## Deep Dive

**Values 合并的默认行为是最大的坑**：Helm 3 里 upgrade **默认就复用**上次 release 的用户值（等价于隐式 `--reuse-values`）；`--set` 只覆盖显式给出的键。想回到"纯 chart 默认值 + 本次新值"必须显式传 `--reset-values`——不校验当前生效值直接 upgrade，才是生产事故的经典来源。

**_helpers.tpl：命名约定决定多租户安全**。所有资源名带 release 前缀（`fullname = {{ .Release.Name }}-{{ .Chart.Name }}`）、label 带标准标签（`app.kubernetes.io/{name,instance,version}`），同一个 chart 才能以不同 release 名在同一命名空间部署多份而互不干扰（selector 精确匹配各自的 instance）。漏掉这一层，两个 release 会互相接管对方的 Pod。

**Release 版本机制是 Helm 回滚的底气**：每次 `helm install/upgrade` 生成递增的 release 版本号，配置快照存在集群 Secret 里，`helm rollback demo 1` 秒级回到任意历史版本。但注意——回滚的是**渲染产物**而非 Git 状态，真正的单一事实源应该还是 Git（见 lab 28 的 ArgoCD）。

## Q&A

**Q1: 一个 chart 需要附带 Redis/PostgreSQL 时怎么办？**
子 chart 与依赖：Chart.yaml 的 `dependencies` 字段声明子 chart，父 values 里按子 chart 名覆盖其值。Helm 负责拉取、渲染、按序部署，业务团队不必关心依赖的部署细节。

**Q2: 多个业务 chart 重复写同样的 Deployment 模板怎么收敛？**
库 chart：`type: library` 只提供模板不产生资源，把公共 deployment 模板抽给多个业务 chart 复用——组织级"标准工作负载模板"的载体。

**Q3: chart 打包后怎么分发？**
OCI 分发：`helm push demo-chart-0.1.0.tgz oci://registry/charts`，直接复用镜像仓库做 chart 分发，免建 ChartMuseum；拉取用 `helm pull oci://...`，与容器镜像同一套鉴权和基础设施。

**Q4: 模板改坏了怎么防？**
测试进 CI：helm unittest 做模板级单测、chart-testing（ct lint-and-test）做 lint + 安装冒烟，把模板回归纳入流水线——模板是代码，就要有代码的纪律。
