# CKA 开工包 · 项目 2：kubeadm 集群版本升级（v1.33.13 → v1.34.12 真机实战）

> 对应清单：`docs/cka.md` 项目 2 ｜ 环境：lima VM `cka-vm`（单控制面）｜ 实测日期：2026-10-07
> **史上最曲折的一题**：五轮失败教会的事全在这里。考场考的是标准流程（20 分钟），本文前半是流程，后半是离线环境的六个坑。

## ✅ 考场标准流程（背这个，20 分钟版）

```bash
# 0. 前置：升级 etcd 快照一份（自带保险，考场加分项）
# 1. 升 kubeadm 二进制（只升 kubeadm，别一把梭）
apt-mark unhold kubeadm && apt-get install -y kubeadm=1.34.x-1.1 && apt-mark hold kubeadm
# 2. 看计划
kubeadm upgrade plan
# 3. drain（单控制面：静态 pod 自动跳过；有裸 Pod 加 --force）
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# 4. 应用
kubeadm upgrade apply v1.34.x --yes
# 5. 升 kubelet/kubectl 二进制并重启
apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.34.x-1.1 kubectl=1.34.x-1.1 && apt-mark hold kubelet kubectl kubeadm
systemctl daemon-reload && systemctl restart kubelet
# 6. uncordon + 验证
kubectl uncordon <node>
kubectl get nodes          # 双双 v1.34.x 且 Ready
# worker 节点：kubeadm upgrade node（无 apply），其余同 5-6
```

## ⚠️ 离线环境实测六坑（每坑一轮失败，全记录）

1. **升级镜像必须离线预导**：`kubeadm config images list --kubernetes-version v1.34.12`（用新 kubeadm 二进制拿权威清单）→ 宿主机 `docker pull`（其中 kube-proxy 首拉断流，重试）→ save/cp/ctr import。
2. ** OrbStack docker save 对部分多架构镜像导出残包**（coredns:v1.12.1 连 layer 都没有）：单平台按 digest 拉也不行；最终靠「已导入的 content + 修复镜像记录链」自愈。**经验：导入后必跑 `ctr -n k8s.io images check`，逐个确认 true 才算数**。
3. **apply 卡在健康检查 Job**：`upgrade-health-check` Job 用 pause:3.10.1 + 20 秒 deadline——**节点 cordon 着就永远调度不了**。先 uncordon 再 apply（或 `--ignore-preflight-errors=CreateJob`）。
4. **静态 pod 升级超时连锁**：etcd 3.5→3.6 数据迁移本身成功，但 apiserver 替换慢导致 `static Pod hash did not change after 5m0s`，kubeadm 自动回滚 manifest——**etcd 却留在 3.6.5**（升级成功的一半），形成 v1.33 apiserver + etcd 3.6 混合态：scheduler RBAC 全线 Forbidden、leader election 超时、无法调度。
5. **混合态的破局 = 手动冲完升级**：`systemctl stop kubelet` → sed 三个 manifest 到 v1.34.12 → `apt install kubelet kubectl 1.34.12` → `daemon-reload && restart kubelet`。新 apiserver 起来后 RBAC 恢复、scheduler 拿到 lease。
6. **升级后测试 Pod 一直 Pending？先看 taint**：kubeadm 给控制面节点打 `node-role.kubernetes.io/control-plane:NoSchedule`，单节点靶场摘掉（`kubectl taint node <n> node-role.kubernetes.io/control-plane:NoSchedule-`）才能跑业务 Pod。**项目 1 的 net-check 其实也是这么 Pending 的**。

## 🎓 对照考纲

- drain → upgrade apply → kubelet 二进制 → daemon-reload/restart → uncordon：五步顺序即评分点
- `kubeadm upgrade plan` 先行（考点：看 Target version 与组件版本表）
- kubelet 必须在 apply 之后单独升（顺序反了 kubelet 起不来）
- apt hold/unhold 语义（考场 Ubuntu 环境同款）

## 🧹 重练

```bash
# VM 内 kubeadm reset -f 后按项目 1 重装 v1.33，再走一遍完整升级（约 40 分钟）
```
