# 00 · 工具准备：安装 kind 与 kubectl

系列的前置步骤：把本机工具准备好。kind 用容器模拟 K8s 节点，是整套实验的地基；kubectl 是贯穿 31 个实验的命令行客户端。

## 文件结构

```
00_setup_kind/
├── README.md        # 本文档
└── setup_kind.sh    # 安装脚本: 检查 -> 安装(brew 或官方二进制) -> 验证
```

## 用法

```bash
./setup_kind.sh          # 安装 kind + kubectl 并验证
./setup_kind.sh verify   # 只验证版本
```

## 说明

- **macOS 推荐 Homebrew**：`brew install kind kubectl`，脚本检测到 brew 时自动走这条路。
- **无 brew 时走官方二进制**（Linux / 裸 macOS）：从 GitHub Releases 和 dl.k8s.io 下载，需要 `sudo` 移到 `/usr/local/bin`。兜底版本在脚本头部定义（`KIND_VERSION` / `KUBECTL_VERSION`）。
- **国内网络**：GitHub/dl.k8s.io 下载可能较慢，可自行用镜像代理替换 URL；Docker 本身也需提前装好（Docker Desktop 或 Docker Engine）——kind 的节点就是 Docker 容器。
- 已安装的工具会跳过，脚本可重复执行。

## 验证

```console
$ kind version
kind v0.25.0 go1.24.1 darwin/arm64
$ kubectl version --client
Client Version: v1.31.0
```

工具就绪后，进入 [01_setup_env](../01_setup_env/README.md) 创建学习集群。
