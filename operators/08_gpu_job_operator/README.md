# GPU 训练任务 Operator（项目 8）

> 联动 labs/31 fake GPU：普通节点模拟 `nvidia.com/gpu` 扩展资源，TrainingJob CR
> 按 gpuCount 自动调度到"有卡"节点——无需真卡即可体验 AI Ops 完整流程。

## 1. 架构总览
![GPU Job](images/gpu_job.svg)
## 2. 快速开始
先跑 labs/31 的 fake GPU DaemonSet，然后 apply TrainingJob CR。
## 3. 文件结构
标准 kubebuilder 工程 + images/ 三件套。
