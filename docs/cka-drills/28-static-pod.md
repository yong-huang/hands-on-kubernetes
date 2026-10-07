# CKA 开工包 · 项目 28：静态 Pod 管理与修复

> 对应清单：`docs/cka.md` 项目 28 ｜ 环境：kind 集群 `k8s-learn`（docker exec 进节点操作）｜ 实测日期：2026-10-07
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` A broken static pod manifest has been placed in the static pod
> directory of node `cp1`, and kubelet logs are filling with errors. Fix the
> situation, then create a new static pod `my-nginx` (nginx image) directly
> via the manifests directory — not via the API. (Weight: 6%)
>
> 目标用时：10 分钟

## ✅ 实测全流程（2026-10-07）

```bash
# 1. 盘点：控制面四个静态 pod 的 manifest 都在这
docker exec k8s-learn-control-plane ls /etc/kubernetes/manifests/
# → etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

# 2. 放入合法静态 pod（不经 API！）
cat > my-nginx.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: my-nginx, labels: {app: my-nginx}}
spec:
  containers: [{name: web, image: nginx:1.25}]
EOF
docker cp my-nginx.yaml k8s-learn-control-plane:/etc/kubernetes/manifests/my-nginx.yaml
sleep 15
kubectl get pod my-nginx-k8s-learn-control-plane    # 1/1 Running ✅

# 3. 坏 YAML → kubelet 解析失败、无 pod、日志报错
docker cp broken.yaml k8s-learn-control-plane:/etc/kubernetes/manifests/broken.yaml
kubectl get pod | grep broken    # 无输出（解析不了就没有 mirror pod）
docker logs k8s-learn-control-plane --since 5m 2>&1 | grep -iE "manifest|couldn't"   # kind 里 kubelet 日志走容器 stdout
# 4. 修复 = 移除坏文件；5. 清场 = 删 my-nginx.yaml（pod 随文件消失，实测 0 残留）
```

## 🧠 实测确认的三条机制

1. **命名后缀规则**：静态 pod 的实际名字 = `<manifest 里的 name>-<节点名>`，如 `my-nginx-k8s-learn-control-plane`——题目让你创建静态 pod `my-nginx` 时，manifest 里写 `name: my-nginx`，别手滑把后缀写进去。
2. **文件即生命周期**：manifest 存在 → pod 秒级出现；删除文件 → pod 秒级消失（实测 12s 内 0 残留）。kubelet 用 fsnotify + 周期扫描监听目录。
3. **坏 manifest 无声**：解析失败的 YAML **不会产生任何 pod 对象**，唯一的线索是 kubelet 日志——考场在真机上用 `journalctl -u kubelet`，kind 里用 `docker logs <节点>`。

## ⚠️ 五大丢分点

1. **用 kubectl delete 静态 pod**：删不掉——kubelet 会按文件重建 mirror pod；正确做法是删/改**节点上的文件**。
2. **manifest 不完整**：静态 pod 的 spec 与普通 Pod 完全一致（apiVersion/kind/metadata/spec 四件套），别因为"是静态的"就省字段。
3. **找错节点**：题目指定 node `cp1`，必须在该节点的 manifests 目录操作；kind 里对应 `docker exec <集群名>-control-plane`。
4. **改 kubeadm 自带 manifest 要小心**：etcd/apiserver.yaml 动坏了控制面直接瘫痪——练习只用自建文件，改完立即验证 pod 出现。
5. **staticPodPath 别假设**：默认 `/etc/kubernetes/manifests/`，确认方法 `ps -ef | grep kubelet | grep -o 'static-pod-path=[^ ]*'` 或读 `/var/lib/kubelet/config.yaml` 的 `staticPodPath`。

## 🧹 重练

```bash
docker exec k8s-learn-control-plane ls /etc/kubernetes/manifests/   # 应只剩 4 个 kubeadm 自带文件
```
