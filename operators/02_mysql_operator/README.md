# MySQL Operator（项目 2）

> 第一个**有状态应用** Operator：一个 `MySQL` CR 声明存储大小、密码引用与备份计划，
> Controller 编排 Headless Service + ClusterIP Service + StatefulSet（volumeClaimTemplates
> 持久化）+ 备份 CronJob，Finalizer 保证删 CR 时连 PVC 一起清理——数据安全不将就。

## 1. 它做什么

```yaml
apiVersion: mysql.example.com/v1
kind: MySQL
metadata: { name: mysql-sample }
spec:
  storageSize: 3Gi
  rootPasswordSecret: { name: mysql-creds, key: password }   # 密码不进 CR 明文
  backupSchedule: "*/2 * * * *"                              # 留空 = 不备份
```

apply 后：MySQL 单实例自动部署且数据持久化；备份 CronJob 按计划 mysqldump 到独立
备份 PVC；删 CR 时 Finalizer 清理全部 PVC——**宁可 Terminating 慢，不可留孤儿数据卷**。

## 2. 架构总览

![MySQL 全栈](images/mysql_stack.svg)

图中三条主线：**稳定网络**（Headless Service 给 Pod 稳定 DNS，ClusterIP 给应用连接）→
**数据持久化**（StatefulSet 的 volumeClaimTemplates 供给数据 PVC，Pod 重建绑回原卷）→
**备份**（CronJob 定时 mysqldump 写入独立备份 PVC）。Finalizer 保证删 CR 时按标签清理
全部 PVC，防止数据孤儿。

> 🌐 **交互版**：[在线打开（GitHub Pages）](https://yong-huang.github.io/hands-on-kubernetes/operators/02_mysql_operator/images/mysql_stack.html)
> （或本地打开 [`images/mysql_stack.html`](images/mysql_stack.html)）。

## 3. 快速开始

```bash
cd operators/02_mysql_operator
make install                 # 安装 CRD
make run                     # 本地跑 Controller
kubectl apply -f config/samples/mysql_v1_mysql.yaml   # Secret + CR 一起
kubectl get mysql,pvc,pod -l app.kubernetes.io/name=mysql-sample
```

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

## 4. Reconcile 代码走读

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

- **Finalizer 清理 PVC**：VCT 产的 PVC 不会随 CR 删除自动消失（防止数据误删），
  Controller 在删除分支按标签 `app.kubernetes.io/managed-by=mysql-operator`
  显式删除——宁可 Terminating 慢，不可留孤儿数据卷；
- **密码不进 CR**：`rootPasswordSecret` 引用 Secret，CR 进 etcd 与审计日志也不泄露。

**实测踩坑（最有价值的一条）**：备份 CronJob 引用的 `mysql-sample-backup` PVC
忘了由 controller 创建——CronJob 的卷引用**不会触发动态供给**，Pod 永远
`FailedScheduling: pvc not found`。静态检查全绿，只有真机跑到才暴露。

## 5. 验收记录（2026-09-05，kind v1.36）

| 验收项 | 结果 |
|:---|:---|
| CR → STS/双 Service/数据 PVC(3Gi Bound)/备份 CronJob 全自动出现 | ✅ |
| 写库 → 删 Pod 重建 → 数据还在（PVC 持久化） | ✅ |
| 备份 CronJob 手动触发 Job 成功，日志 backup-ok，dump 在独立 PVC | ✅ |
| 删 CR → Finalizer 清理全部 PVC，集群零残留 | ✅ |

## 6. 文件结构

```
02_mysql_operator/
├── README.md                        # 本文档
├── cmd/main.go                      # kubebuilder 入口
├── api/v1/                          # MySQL 类型定义 + deepcopy
├── internal/controller/             # Reconcile 核心（mysql_controller.go）
├── config/                          # CRD / RBAC / manager 部署清单
└── images/
    ├── mysql_stack.architecture.json  # 图源（Typed JSON IR）
    ├── mysql_stack.html               # 交互版架构图
    └── mysql_stack.svg                # 双主题矢量版（本文档 §2 内嵌）
```

## 7. 面试要点

1. **volumeClaimTemplates vs 引用 PVC**：VCT 为每副本生成专属 PVC（data-mysql-0），
   副本间隔离；引用同一个 PVC 则所有副本共享（适合只读）；
2. **Headless Service 的作用**：给每个 Pod 稳定 DNS（mysql-0.mysql-h.ns.svc），主从复制
   和客户端直连实例都靠它；
3. **密码为什么用 Secret 引用**：CR 明文进 etcd 与审计日志；Secret 引用让密码独立轮换，
   CR 无需变更；
4. **Finalizer 清理 PVC 的权衡**：不清理 = 数据孤儿占空间；清理 = 删 CR 就删数据。
   生产做法是 CR 上加开关（`deleteData: true`）或依赖备份先行。
