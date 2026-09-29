# 02 · MySQL Operator：有状态应用编排

> 第一个**有状态应用** Operator：一个 `MySQL` CR （Custom Resource：向 K8s API 注册的自定义资源对象，spec 写期望、status 写实际） 声明存储大小、密码引用与备份计划，Controller 编排 Headless Service + ClusterIP Service + StatefulSet（volumeClaimTemplates 持久化）+ 备份 CronJob，Finalizer 保证删 CR 时连 PVC 一起清理——数据安全不将就。读完本篇，你将看到"删 Pod 数据还在、删 CR 卷清理干净"的完整生命周期。

## Background

数据库上 K8s 的早期做法是把 StatefulSet 清单和备份脚本分别交给人工维护：扩容改副本数要懂 PVC 细节，备份靠 crontab，删环境时 PVC 残留占着存储没人认领。这类运维知识散落在文档和值班经验里，换个团队就丢一遍。

有状态应用的纪律其实很明确：网络标识要稳定（Headless DNS）、数据要跟着身份走（每副本独立卷）、销毁必须干净（卷随环境清理）。本实验把这些纪律固化进 Operator：一个 `MySQL` CR 声明期望，Controller 编排全套资源并守护生命周期——纪律从文档变成代码。

## What

一个 `MySQL` CR 长这样：

```yaml
apiVersion: mysql.example.com/v1
kind: MySQL
metadata: { name: mysql-sample }
spec:
  storageSize: 3Gi
  rootPasswordSecret: { name: mysql-creds, key: password }   # 密码不进 CR 明文
  backupSchedule: "*/2 * * * *"                              # 留空 = 不备份
```

apply 后：MySQL 单实例自动部署且数据持久化；备份 CronJob 按计划 mysqldump 到独立备份 PVC；删 CR 时 Finalizer 清理全部 PVC。

一句话心智模型：**一个 CR 管数据库从生到死的全部家当**——但和"一键安装脚本"不同的是，它在数据库活着的时候也一直管：Pod 重建、备份触发、删除清理都由 Controller 收敛。

| 编排产物 | 职责 |
|---|---|
| Headless Service | Pod 稳定 DNS（`mysql-0.mysql-h.ns.svc`） |
| ClusterIP Service | 应用连接入口 |
| StatefulSet + VCT | 有序部署 + 每副本独立 PVC |
| 备份 CronJob | 定时 mysqldump 到独立备份 PVC |

## When to Use

典型场景：给开发团队提供"提 CR 即得数据库"的自助能力；需要备份计划内建（改 CR 的 cron 即生效）；需要删除环境时连 PVC 一起清干净（不留孤儿数据卷）。

何时不用：生产级多主/故障转移（本实验是单实例，生产用成熟方案如 Vitess/云 RDS，或按此模式扩展 Operator）；只读分析库挂载现成数据（直接挂 PVC 即可，无需编排）。

同类方案对比：

| 方案 | 差异 | 什么时候选它 |
|---|---|---|
| 手写 StatefulSet 清单 | 一次到位但运维靠人 | 单实例长期不动 |
| 本实验 Operator | CR 声明 + 全生命周期收敛 | 学习 Operator 模式、自建平台 |
| 成熟方案（Vitess/云 RDS） | 高可用与运维完备 | 生产关键数据库 |

## Quick Start

前置条件：kind 集群已就绪（见 [labs/01](../../labs/01_setup_env/README.md)）；Go 环境可用。

```bash
cd operators/02_mysql_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller
kubectl apply -f config/samples/mysql_v1_mysql.yaml   # Secret + CR 一起
kubectl get mysql,pvc,pod -l app.kubernetes.io/name=mysql-sample
```

诚实预期：apply 后先 `kubectl get pod -w` 等 `mysql-sample-0` 变 Running(1/1) 再执行下面的 exec（首次初始化约半分钟）；重复验证备份前先 `kubectl delete job backup-test`，否则报 AlreadyExists。

写数据 → 删 Pod → 验证持久化：

```bash
kubectl exec mysql-sample-0 -- mysql -uroot -p"demo-root-pw" \
  -e "CREATE DATABASE hands_on; USE hands_on; CREATE TABLE t(id INT); INSERT INTO t VALUES(42);"
kubectl delete pod mysql-sample-0           # STS 自动重建同名 Pod
kubectl exec mysql-sample-0 -- mysql -uroot -p"demo-root-pw" \
  -e "SELECT * FROM hands_on.t"             # 42 还在 —— 数据在 PVC 不在 Pod
```

手动触发一次备份并验证 dump：

```bash
kubectl create job --from=cronjob/mysql-sample-backup backup-test
kubectl logs job/backup-test | tail -1       # backup-ok
```

## How It Works

**三条编排主线**：**稳定网络**——Headless Service 给 Pod 稳定 DNS（`mysql-0.mysql-h.ns.svc`），ClusterIP 给应用连接，主从复制和客户端直连实例都靠前者；

**数据持久化**——StatefulSet 的 volumeClaimTemplates 供给数据 PVC（`data-mysql-0`），Pod 重建绑回原卷；**备份**——CronJob 定时 mysqldump 写入独立备份 PVC。

代码走读——VCT 直接在 StatefulSet spec 里声明：

```go
// Headless Service：clusterIP: None，给 Pod 稳定 DNS（mysql-h）
// StatefulSet：serviceName 指向它，Pod 才有 web-0 式稳定网络标识
sts.Spec.VolumeClaimTemplates = []corev1.PersistentVolumeClaim{{
    ObjectMeta: metav1.ObjectMeta{Name: "data", Labels: mysqlLabels(db.Name)},
    Spec: corev1.PersistentVolumeClaimSpec{
        AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
        Resources:   ...{Requests: {Storage: size}},
    },
}}
```

- **Finalizer 清理 PVC**：VCT 产的 PVC 不会随 CR 删除自动消失（防止数据误删），Controller 在删除分支按标签 `app.kubernetes.io/managed-by=mysql-operator` 显式删除——宁可 Terminating 慢，不可留孤儿数据卷；
- **密码不进 CR**：`rootPasswordSecret` 引用 Secret，CR 进 etcd 与审计日志也不泄露；且密码可独立轮换，CR 无需变更。

验收记录（2026-09-05，kind v1.36）：

| 验收项 | 结果 |
|:---|:---|
| CR → STS/双 Service/数据 PVC(3Gi Bound)/备份 CronJob 全自动出现 | ✅ |
| 写库 → 删 Pod 重建 → 数据还在（PVC 持久化） | ✅ |
| 备份 CronJob 手动触发 Job 成功，日志 backup-ok，dump 在独立 PVC | ✅ |
| 删 CR → Finalizer 清理全部 PVC，集群零残留 | ✅ |

## Pitfalls & Q&A

踩坑清单：

- **备份 CronJob 引用的 `mysql-sample-backup` PVC 忘了由 controller 创建**——CronJob 的卷引用**不会触发动态供给**，Pod 永远 `FailedScheduling: pvc not found`。静态检查全绿，只有真机跑到才暴露：任何被引用的 PVC 必须有供给来源。
- 把备份 dump 和数据写进同一个 PVC：源损坏连备份一起没——备份卷必须独立。

**Q1: volumeClaimTemplates 和引用现成 PVC 怎么选？**
VCT 为每副本生成专属 PVC（`data-mysql-0`），副本间数据隔离，重建绑回原卷——有状态应用的默认选择；引用同一个 PVC 则所有副本共享一份数据，只适合只读场景（如挂载模型文件）。数据库类 CRD 一律走 VCT。

**Q2: Finalizer 清 PVC 是不是太激进了？删 CR 就删数据？**

确实是个权衡：不清理 = 数据孤儿占空间且无人认领；清理 = 删 CR 就删数据。本实验选择"删干净"是教学语义下的正确取向。

生产做法是 CR 上加开关（如 `deleteData: true`），或规定删除前必须先有备份（labs/17 的 CSI 快照 / labs/18 的 Velero 都能兜底）——无论如何，策略必须是显式声明的，不能靠"忘了删"来保留数据。
