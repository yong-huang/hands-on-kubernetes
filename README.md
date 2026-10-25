# 🎛️ hands-on-kubernetes：Kubernetes 动手学习系列

> 3 条学习线、54 个可跑项目：labs 34 个实验、operators 10 个 Operator 项目、mart 10 个微服务项目，全部在本机 kind（用 Docker 容器模拟节点的本地 K8s 工具）集群真机跑通，读完任意一篇都能照着脚本跑通并理解背后的机制。每篇统一结构：六段式教程 README + 演示入口（labs / mart 为一键脚本 apply → observe → clean，operators 为 make install / run + 样例 CR）+ 架构图（双主题 SVG 共 56 张，多数另附可交互 HTML）。

## 🗺️ 实验线总表

| 线 | 系列 README | 技术栈 | 内容 | 进度 |
|:--|:--|:--|:--|:--|
| 实验线 | [labs/README.md](labs/README.md) | YAML 清单 + kind | 34 个实验：工作负载、网络、存储、安全、可观测、平台工程（00 为工具准备，32–34 进阶） | ✅ 34/34 |
| Operator 线 | [operators/README.md](operators/README.md) | Go / kubebuilder | 10 个项目：从资源编排、有状态应用到 AI 工作负载 | 🚧 7/10 |
| 微服务线 | [mart/README.md](mart/README.md) | Go + Python | mini-mart 迷你电商：10 个项目共同生长一个系统 | ✅ 10/10 |

选线一句话：labs 学会零件 → operators 学会造工具 → mart 学会组装机器。零基础从 labs 按序做；已会基础概念的可直接进 operators 01（需 Go）或 mart。

三条线共享同一个 k8s-learn 集群与一套脚本约定，operators 与 mart 直接引用 labs 建立的机制（如 labs/31 的 fake GPU 设备插件、labs/02 的探针健康检查）。

架构图在线版：[GitHub Pages](https://yong-huang.github.io/hands-on-kubernetes/)，本地用浏览器打开各 `images/*.html` 同效。

## 🚀 快速开始

前置：Docker 已安装；国内网络建议先配镜像加速。

```bash
# ① labs 线：装工具 → 建集群
cd labs/00_setup_kind && ./setup_kind.sh      # 装 kind + kubectl（未装过才需要）
cd ../01_setup_env && ./setup.sh up           # 建 k8s-learn 集群；kubectl get nodes 应见 3 节点 Ready
cd ../..                                      # 回到仓库根

# ② operators 线：装 CRD → 本地跑 Controller（make run 前台阻塞，另开终端）
cd operators/01_app_operator && make install && make run
cd ../..                                      # 回到仓库根

# ③ mart 线
cd mart && ./scripts/01_product_k8s.sh all
```

生命周期语义：每实验统一 apply → observe → clean——单实验用各自 `./xxx.sh clean` 或删 CR 级联清理；整个集群用 labs/01 的 `./setup.sh down` 删掉重建，零残留。

## ⚠️ 预期失败诚实标注

- 首次建集群、装组件要拉镜像，分钟级等待属正常；国内网络先跑 `scripts/load_images.sh` 预载（哪些实验会超时见 [labs/README.md](labs/README.md) 的 ⚠️ 节）。
- 端口被占用、实验资源未 clean 就进入下一个实验，都会让脚本第一步失败——逐线的失败清单指向各自系列 README 的 ⚠️ 节。
- operators 线的已知待修项（05 stable 缩容、07 教学模式、10 毕业项剩余能力）在其项目总表逐行标注。

## 🔧 环境要求

- 全线基线：Docker；kind ≥ 0.20、kubectl ≥ 1.28（labs/00 一键安装）。
- labs 线按实验额外：istioctl（13）、velero CLI（18）、trivy / cosign（21）、helm（27）、karmadactl（30）。
- operators 线：Go（Controller `make run` 本地编译运行）；项目 08 需先跑 labs/31。
- mart 线：Go + Python 双栈；本机 docker 可构建镜像。

## 📝 来源与许可

| 清单文档 | 对应 | 状态 |
|:--|:--|:--|
| [kubernetes.md](docs/kubernetes.md) | labs/ 的 34 个实验总清单（与 labs/ 一一对应） | ✅ 34/34 |
| [kubernetes_operator.md](docs/kubernetes_operator.md) | operators/ 的 10 个 Operator 开发项目 | 🚧 7/10（项目 5 代码完成待修，7、10 未勾选） |
| [microservices.md](docs/microservices.md) | mini-mart 微服务开发（Go/Python 双栈） | ✅ 10/10 |
| [TESTING.md](docs/TESTING.md) | 全仓测试报告与回归指南 | ✅ |

内容以 [MIT](LICENSE) 许可发布：实验代码与文档可自由使用、修改和分发，保留版权声明即可，可用于转载与培训。
