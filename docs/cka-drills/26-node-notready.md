# CKA 开工包 · 项目 26：Node NotReady 与 kubelet 排障（真 systemd 实战）

> 对应清单：`docs/cka.md` 项目 26 ｜ 环境：lima VM `cka-vm`（真 systemd，v1.34.12）｜ 实测日期：2026-10-07
> 本题 10 分钟拿下：注入 → NotReady → 三步诊断 → 修复 → Ready。先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Node `node01` is in NotReady state. Investigate and fix the
> underlying issue so the node becomes Ready again. (Weight: 10%)
>
> 目标用时：10 分钟

## ✅ 实测全流程（2026-10-07）

```bash
# 注入（考官视角）
sudo systemctl stop kubelet && systemctl is-active kubelet   # inactive
sleep 60   # node lease 默认 40s 过期 → NotReady

# ── 考生诊断链（顺序即方法论）──
# ① 控制面视角：现象与原因
kubectl get nodes                       # NotReady
kubectl describe node node01 | grep -A5 Conditions
#   实测可见 Ready=Unknown + reason: KubeletStopped（kubelet 心跳停止）
# ② 节点侧：服务状态
systemctl status kubelet                # inactive (dead) ← 根因在此
# ③ 节点侧：日志（区分「停了」还是「起不来」）
journalctl -u kubelet --no-pager -n 20  # 实测：Stopped kubelet.service（干净的停，非报错）

# ── 修复 ──
sudo systemctl start kubelet            # 若 enabled 缺失：systemctl enable --now kubelet
# ~20 秒后 node lease 续上
kubectl get nodes    # ✅ Ready（实测第 2 轮 10 秒内恢复）
```

## 🧠 NotReady 诊断决策树（考场版）

```
kubectl describe node → Conditions / 事件
├─ KubeletNotReady + "container runtime network not ready" → CNI 挂了 → 查 flannel/calico pod
├─ Ready=Unknown + 心跳消失 → 上节点看 kubelet
│   ├─ systemctl status: inactive → start / enable --now（本题）
│   ├─ active 但日志报 swap/firewall → 修前置（项目 1 坑）
│   └─ active 且日志在刷连不上 apiserver → 控制面问题（项目 27）
└─ NotReady + containerd 报错 → systemctl status containerd / crictl ps
```

## ⚠️ 五大丢分点

1. **直奔重启**：不 `describe node` 不 `status kubelet` 就 systemctl restart——蒙对了也丢过程分，何况根因可能不是 kubelet。
2. **忘了 systemd 单元语义**：`stop` 后 `restart` 也能起，但考场标准答案是 `start`（或 `enable --now` 兼顾开机自启）。
3. **等不到 Ready 就交卷**：lease 恢复要 10-20 秒，跑一次 `kubectl get nodes -w` 确认再走。
4. **NotReady ≠ kubelet 一家**：containerd 挂、CNI 挂、磁盘压力（DiskPressure taint）都表现成 NotReady——决策树按 Conditions 的 reason 分叉。
5. **journalctl 用法**：`journalctl -u kubelet -n 20 --no-pager`（-u 按单元、-n 行数、--no-pager 防卡翻页）；考点常给一半日志让续写诊断。

## 🧹 重练

```bash
sudo systemctl stop kubelet && sleep 60   # NotReady 复现
# 闭卷走诊断链 → start → Ready
```
