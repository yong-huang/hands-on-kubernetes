# CKA 开工包 · 项目 3：etcd 备份与恢复（真机全流程）

> 对应清单：`docs/cka.md` 项目 3 ｜ 环境：lima VM `cka-vm`（kubeadm 单控制面）｜ 实测日期：2026-10-07
> **完整恢复演练做过一遍**：快照 → 造差量 → 停 etcd → restore → 换数据目录 → 验证回滚时点。
> 先闭卷自做，再对照。

## ✅ 备份（考场高频原题，实测秒级完成）

```bash
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')
# ⚠️ etcd 镜像是 distroless（无 sh）：直接 exec etcdctl，不要 sh -c 包裹
kubectl -n kube-system exec $ETCD_POD -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/exam-snapshot.db

# 校验（考场必做）
kubectl -n kube-system exec $ETCD_POD -- etcdctl ...snapshot status /var/lib/etcd/exam-snapshot.db --write-out=table
# 实测: HASH c0e8e5f2 | REVISION 1826 | TOTAL KEYS 925 | SIZE 2.2MB
```

**证书三件套记忆法**：etcd 的 ca + server 证书（不是 apiserver 的）；路径都在 `/etc/kubernetes/pki/etcd/` 下。

## ✅ 恢复（完整演练，五个动作一个坑）

```bash
# 0. 造差量验证点：快照后建 ns pre-restore（恢复后应消失）
# 1. 停 etcd
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
# 2. restore 到【新数据目录】（考试铁律：不能原地恢复）
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd/exam-snapshot.db \
  --data-dir=/var/lib/etcd-restored
#    ⚠️ 节点上没有 etcdctl：从 etcd 镜像 docker cp 出来（arm64 对 arm64 VM）
# 3. 改 manifest（2 处 flag+1 处挂载，见下）并放回
sed -i 's|--data-dir=/var/lib/etcd\b|--data-dir=/var/lib/etcd-restored|' etcd.yaml
sed -i 's|path: /var/lib/etcd$|path: /var/lib/etcd-restored|'      etcd.yaml
sed -i 's|mountPath: /var/lib/etcd$|mountPath: /var/lib/etcd-restored|' etcd.yaml
sudo mv etcd.yaml /etc/kubernetes/manifests/
# 4. apiserver 卡在旧缓存时：重启 apiserver 静态 pod（mv 出去再回来）
# 5. 验证回滚时点：kubectl get ns → pre-restore 消失 ✅ 老资源健在 ✅
```

## ⚠️ 实测三大坑（本项目最贵的三个教训）

1. **manifest 要改三处不是两处**（实测翻车点）：`--data-dir` flag、hostPath `path:`、还有 **volumeMount 的 `mountPath:`**。漏第三处 → 容器内挂载点没跟上 → etcd 在容器层空目录上起了个**全新空集群** → apiserver 全线 Forbidden（RBAC 数据为空）。症状高度迷惑：etcdctl endpoint health 照样 healthy！
2. **恢复后 apiserver 不刷新就 Forbidden**：etcd 数据换了，apiserver 的 RBAC informer 缓存可能停留在中间态——**mv apiserver manifest 出去再回来强制重启**，立刻恢复。本机实测 `kubectl get ns` 从 Forbidden → 正常。
3. **诊断顺序**：Forbidden 时先用 etcdctl 直查 `/registry/clusterrolebindings/`（数据在不在）→ 查 `ss -ltnp | grep 2379`（谁在服务）→ 查 manifest 三处一致性 → 才轮到重启 apiserver。

## 🎓 对照考纲（本题覆盖点）

- snapshot save 的证书三件套与 status 校验（**考点：status 输出 HASH/REVISION/TOTAL KEYS**）
- restore 必须用 `--data-dir` 指向新目录；etcd 集群 ID 会变（单节点无感）
- 静态 pod manifest 即 etcd 生命周期开关（项目 28 原理的实战应用）
- 恢复后 apiserver/etcd 的联动关系：informer 缓存、证书不变、数据回滚时点验证法

## 🧹 重练

```bash
# VM 内：sudo rm -rf /var/lib/etcd-restored /var/lib/etcd/exam-snapshot.db
# manifest 三处 sed 回 /var/lib/etcd，mv 回位即可回到原生状态
```
