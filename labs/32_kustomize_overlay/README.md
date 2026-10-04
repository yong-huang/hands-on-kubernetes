# 32 · Kustomize：base 与 overlay 的多环境管理

> 裸 YAML 多环境复制三份、Helm 模板引擎学习成本高——Kustomize 给出第三条路：不改模板，只做"叠加补丁"。本实验用一套 base + dev/staging 两个 overlay，让同一份清单渲染出两个参数不同的环境，并亲眼看到 configMapGenerator 的哈希机制如何解决"改了配置 Pod 不知道"。

## Background

多环境部署的配置管理有两条演进路线。第一条是复制：dev/staging/prod 各拷一份完整 YAML，各自修改差异——改一行模板逻辑要同步三处，漂移迟早发生。

第二条是模板引擎（lab 27 的 Helm）：把差异抽成 values——能力强，但要学会一门模板语言，且 chart 本身有维护成本。

Kustomize 选择了第三条路：**清单永远是合法的 YAML，环境差异用"补丁"叠加**。base 目录放标准清单，overlay 目录只声明差异（副本数、镜像 tag、配置内容），渲染时合并。它内置于 kubectl（`kubectl apply -k`），零额外安装。

## What

Kustomize 的核心结构是 base + overlay 两层：

| 目录 | 装什么 | 关键文件 |
|---|---|---|
| `base/` | 标准清单（Deployment + Service + ConfigMap） | kustomization.yaml 列出 resources |
| `overlays/dev` | 副本 1、`nameSuffix: -dev`、配置内容 A | patches / configMapGenerator |
| `overlays/staging` | 副本 2、配置内容 B | 同上 |

一句话心智模型：**base 是"标准件"，overlay 是"差量补丁（diff）"**——可以把 overlay 想象成 Photoshop 的调整图层；但和调整图层不同的是，叠加结果必须仍是合法 YAML，且每个环境一条命令渲染。

| 机制 | 作用 |
|---|---|
| `namespace` / `nameSuffix` | 整体重命名，多环境共存于同一集群 |
| `images` | 批量改镜像 tag |
| `patches` | 精确修改字段（支持 JSON6902——RFC 6902 定义的 JSON 补丁格式——与 strategic merge——K8s 原生的按字段合并——两种写法） |
| `configMapGenerator` | 从文件生成 ConfigMap，**名字自动带内容哈希** |

## When to Use

典型场景：同一应用发 dev/staging/prod（差异只是副本数、镜像 tag、配置内容）；想给 fork 来的第三方清单做小改动而不动原文件；要求"渲染产物是合法 YAML"可审计（`kubectl kustomize` 或 server-side dry-run）。

何时不用：差异本质是"模板逻辑"（if/else、循环）——Kustomize 无模板能力，回 Helm；团队已深度投资 Helm chart——两套并存徒增心智负担。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 复制三份 YAML | 直白但必然漂移 | 不要用 |
| Helm（lab 27） | 模板引擎，生态最大 | 差异是"参数化逻辑"、要分发 chart |
| Kustomize（本实验） | 补丁叠加，零模板语法 | 差异是"字段补丁"、要合法 YAML 产物 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../01_setup_env/README.md)）；无需安装 Kustomize（kubectl 内置）。

```bash
cd labs/32_kustomize_overlay
./kustomize.sh build    # 渲染两个 overlay, 对比差异
./kustomize.sh deploy   # apply -k overlays/dev
./kustomize.sh change   # 改 staging 配置内容, 看哈希滚动
./kustomize.sh verify   # 验证两个环境的响应与规格
./kustomize.sh clean
```

`build` 渲染对比（节选）：

```
--- kubectl kustomize overlays/dev (节选) ---
        return 200 "hello-from-dev\n";
  name: web-config-dev-48tgbk7gc8
  replicas: 1
      - image: nginx:1.27
--- kubectl kustomize overlays/staging (节选) ---
        return 200 "hello-from-staging\n";
  name: web-config-h9m62m2d7b
  replicas: 2
      - image: nginx:1.27
```

`change` 步骤的哈希滚动（真实输出节选）：

```
configmap/web-config-h9m62m2d7b created
configmap/web-config-97bbhchb79 created
ConfigMap 引用: web-config-h9m62m2d7b  ->  web-config-97bbhchb79
```

诚实预期：修改 ConfigMap 内容后新哈希名立即生成，但 **Pod 内文件由 kubelet 异步同步（约 1 分钟）**，curl 立刻验证会打到旧内容——脚本已内置轮询等待。

## How It Works

**哈希滚动是 configMapGenerator 的灵魂**：生成器给 ConfigMap 名字加内容哈希后缀（`web-config-h9m62m2d7b`），内容一变哈希就变，Deployment 对它的引用随之更新——对 K8s 来说这是"换了一个新 ConfigMap"，滚动更新自然触发。

你在 `change` 步骤看到的引用变化 `h9m62m2d7b → 97bbhchb79`，就是这条机制。它解决了 lab 05 的经典难题（volume 会同步、env 不会、subPath 也不会）——哈希引用用"换 ConfigMap"绕开了全部三个坑。

**overlay 的叠加顺序**：`resources` 引入 base 清单；`namespace`/`nameSuffix` 重命名；`images` 改镜像；`patches` 改字段。

最后 `configMapGenerator` 以 `behavior: replace` 整体替换 base 的 ConfigMap（对照 `merge` 的局部合并）。

渲染是纯文本操作，`kubectl kustomize` 随时可本地预览——你在 `build` 步骤看到的两个输出，就是同一 base 的两种投影。

**nameSuffix 不改 label（本实验最大的坑）**：`nameSuffix: -dev` 只重命名资源，Pod template 里的 label 还是 `app: web`。

后果是 dev/staging 两个 Deployment 的 selector 都能"认领"对方的 Pod，`kubectl exec deploy/web` 可能串到 dev 的实例。

解法是给 overlay 加 `labels + includeSelectors: true`（注入 `environment` 标签并把它并进 selector），这正是 lab 27 里 Helm `instance` 标签的 Kustomize 版——命名唯一化必须连同选择器一起做。

## Pitfalls & Q&A

踩坑清单：

- **Kustomize 不创建 namespace**：`namespace:` 字段只是重定向，目标命名空间不存在时 apply 报 NotFound——overlay 里要显式包含 Namespace 资源（本实验的 `namespace.yaml`）。
- **`behavior: merge` 只增改键、`replace` 整体替换**：想覆盖 base 里 ConfigMap 的同名键内容用 `replace` + `files:`；`merge` + `literals` 会新增键而非覆盖文件内容。
- **修改 ConfigMap 内容后立刻 curl**：kubelet 同步挂载卷有约 1 分钟延迟，且哈希滚动需要新 Pod——脚本用轮询解决，手动验证要等 rollout 完成后再等一拍。

**Q1: Kustomize 和 Helm 到底怎么选？**
按差异的"形态"判断：差异是**字段级补丁**（副本数、镜像 tag、几行配置）选 Kustomize——补丁本身就是合法 YAML，diff 友好。

差异是**结构级参数化**（可开关的组件、跨版本模板逻辑）选 Helm。两者可共存：chart 用 Helm 装，环境差异用 Kustomize 叠（Kustomize 支持用 URL 引用远程 base，可直接叠在 chart 渲染出的清单上）。

**Q2: base 里的默认值应该写什么？**
写"最保守、最通用的那套"。base 会被所有 overlay 继承，任何 overlay 没有显式覆盖的字段都会暴露 base 默认值——把生产参数误放 base 是常见事故源。原则：base 宁可"最小可用"，各环境显式声明自己的关键参数。

**Q3: 渲染产物怎么审计？**
`kubectl kustomize overlays/dev`（或 `kubectl apply -k --dry-run=server`）输出最终清单——叠加再多层，产物永远是确定的合法 YAML。

CI 里把"渲染产物 diff"作为评审材料，比读 overlay 源文件更接近真相。
