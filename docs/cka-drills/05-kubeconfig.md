# CKA 开工包 · 项目 5：kubeconfig 多集群上下文管理

> 对应清单：`docs/cka.md` 项目 5 ｜ 环境：本机沙箱 `/tmp/cka-drill`（不碰真实 `~/.kube/config`）｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。本机改编：用 `kind-ai-infra` 模拟「日常主配置」、`kind-k8s-learn` 抽出改名模拟「外来 staging 配置」。

## 📝 题面（考场原题风格）

> `Task:` Merge the kubeconfig located at `/root/staging-config` into your default kubeconfig.
> Rename the new context to `staging` and switch to it.
> Confirm you can list nodes of the staging cluster. (Weight: 3%)
>
> 目标用时：6 分钟

## ✅ 考场最优解

```bash
# 1. 合并（关键：--flatten 把证书内联，去掉会留文件引用路径）
KUBECONFIG=$HOME/.kube/config:/root/staging-config kubectl config view --flatten > /tmp/merged
mv /tmp/merged $HOME/.kube/config
# 2. 重命名新 context 并切换（rename-context 旧名在前，新名在后）
kubectl config rename-context <原始context名> staging
kubectl config use-context staging
kubectl config current-context          # 确认
kubectl get nodes                       # 验收：列出 staging 集群节点
```

## 🧪 本机沙箱实测（2026-10-06，全程 `cd /tmp/cka-drill`）

```bash
# 造素材：把两个 kind 集群各抽成单上下文 kubeconfig
kubectl config view --minify --flatten --context kind-ai-infra > main-config
kubectl config view --minify --flatten --context kind-k8s-learn > staging-raw
kubectl config --kubeconfig=staging-raw rename-context kind-k8s-learn cluster-east

# 演练：合并 → 重命名 → 切换 → 验收
KUBECONFIG=main-config:staging-raw kubectl config view --flatten > merged
kubectl config --kubeconfig=merged rename-context cluster-east staging
kubectl config --kubeconfig=merged use-context staging
kubectl --kubeconfig=merged get nodes        # ✅ 输出 k8s-learn 的 3 节点
```

实测结果：`get-contexts` 显示 `kind-ai-infra` 与 `staging*` 两个 context，`*` 在 staging 上，`get nodes` 返回 k8s-learn 集群 3 节点 —— 验收达成。

## ⚠️ 五大丢分点

1. **`--flatten` 漏掉**：合并产物里 cluster 写的是 certificate-authority 文件路径，环境一变就失效；考场要求「能列出节点」时 flatten 版最稳。
2. **重定向自吃自身**：`KUBECONFIG=a:b kubectl config view --flatten > a` 会把 a 清掉重写，展开顺序出问题；先写到临时文件再 `mv` 覆盖。
3. **rename-context 参数顺序反了**：旧名在前、新名在后，写反会报 `no context named` 之类错误还容易手忙脚乱。
4. **切完不确认**：`use-context` 后不跑 `current-context`，后面题目全做错集群——CKA 头号丢分习惯，本题就是练这个肌肉的。
5. **证书路径陷阱**：外来 kubeconfig 常用相对路径引用证书，合并前先 `kubectl config view --raw` 或 flatten，别用文本编辑器手拼。

## 🧹 重练

```bash
rm -rf /tmp/cka-drill   # 清掉沙箱重来；真实 ~/.kube/config 全程未被触碰
```
