#!/usr/bin/env python3
"""Fake GPU Operator 可视化: 真实设备插件链路 vs 模拟实现 + 调度/配额关卡"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("Fake GPU Operator: 设备插件机制 与 AI 任务调度", fontsize=16,
             fontweight="bold")

# ============================ Panel 1: 设备插件链路 ============================
ax1.set_title("nvidia.com/gpu 从哪来: 真实链路与模拟对照", fontsize=13)
# 左列: 真实
ax1.add_patch(mpatches.FancyBboxPatch((0.4, 6.6), 4.0, 2.4,
              boxstyle="round,pad=0.12", fc="#f5f8fb", ec="#76b7b2"))
ax1.text(2.4, 8.65, "真实 GPU 链路", ha="center", fontsize=10.5,
         fontweight="bold", color="#76b7b2")
real_steps = [
    (7.55, "NVIDIA Driver / container-toolkit"),
    (6.85, "gpu-operator DaemonSet 跑 device plugin"),
    (6.15, "plugin 经 gRPC socket 向 kubelet 上报设备"),
]
for cy, txt in real_steps:
    ax1.text(0.65, cy, "• " + txt, fontsize=8.3)
# 右列: 模拟
ax1.add_patch(mpatches.FancyBboxPatch((5.5, 6.6), 4.1, 2.4,
              boxstyle="round,pad=0.12", fc="#fdf3ec", ec="#ff7f0e"))
ax1.text(7.55, 8.65, "Fake 模拟链路 (本项目)", ha="center", fontsize=10.5,
         fontweight="bold", color="#ff7f0e")
fake_steps = [
    "无驱动无卡; DaemonSet 每 15s 补写",
    "python updater 直调 API (RBAC 最小化)",
    "patch nodes/status 改 capacity/allocatable",
]
for i, txt in enumerate(fake_steps):
    ax1.text(5.75, 7.55 - i * 0.7, "• " + txt, fontsize=8.3)

# 中部: kubelet / node status
ax1.add_patch(mpatches.FancyBboxPatch((2.9, 4.35), 4.2, 1.5,
              boxstyle="round,pad=0.1", fc="#1f77b4", ec="black"))
ax1.text(5.0, 5.45, "Node Status (etcd)", ha="center", fontsize=10.5,
         fontweight="bold", color="white")
ax1.text(5.0, 4.75, "allocatable:\n  nvidia.com/gpu: 8",
         ha="center", va="center", fontsize=9, family="monospace",
         color="#cfe8ff")
for x in (2.4, 7.55):
    ax1.annotate("", xy=(2.95 if x < 5 else 7.05, 5.1), xytext=(x, 6.55),
                 arrowprops=dict(arrowstyle="-|>", lw=1.6))

# 底部: 调度器视角
ax1.add_patch(mpatches.FancyBboxPatch((1.4, 1.9), 7.2, 1.6,
              boxstyle="round,pad=0.1", fc="#2ca02c", ec="black"))
ax1.text(5.0, 3.05, "Scheduler 视角完全一致", ha="center", fontsize=10.5,
         fontweight="bold", color="white")
ax1.text(5.0, 2.35, "扩展资源只是一个数字 —— 不校验真伪;\n"
                    "requests.gpu=1 的 Pod 只会被调度到 allocatable 足够的节点",
         ha="center", va="center", fontsize=8.8, color="white")
ax1.annotate("", xy=(5.0, 3.55), xytext=(5.0, 4.3),
             arrowprops=dict(arrowstyle="-|>", lw=1.8))
ax1.text(5.0, 1.25, "适用: 本地体验 GPU Ops 流程 / CI 测试调度逻辑 / 平台功能开发",
         ha="center", fontsize=9, color="#666")
ax1.set_xlim(0, 10); ax1.set_ylim(0.9, 9.3); ax1.axis("off")

# ============================ Panel 2: 两道关卡 ============================
ax2.set_title("AI 训练任务的调度关卡: 配额 -> 过滤 -> 绑定", fontsize=13)
gate = [
    (2.6, 8.4, "Job 提交\ntrain-big: requests.gpu=6", "#aec7e8"),
    (2.6, 6.3, "第1关 ResourceQuota\nns 总额度 4 卡", "#ff7f0e"),
    (2.6, 4.2, "第2关 Scheduler Filter\n节点 allocatable >= 6 ?", "#1f77b4"),
    (2.6, 2.1, "绑定节点 -> kubelet 分配\n(device plugin 池中扣减)", "#2ca02c"),
]
for cx, cy, txt, c in gate:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 1.95, cy - 0.68), 3.9, 1.36,
                  boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=8.8,
             color="white" if c != "#aec7e8" else "black")
# 第1关之前的箭头: 两个任务都会提交
ax2.annotate("", xy=(2.6, 7.65 - 0.75), xytext=(2.6, 7.65),
             arrowprops=dict(arrowstyle="-|>", lw=1.6))
# 第1关之后: 只有 train-small 能继续走到过滤/绑定 (虚线示意)
for y in (5.55, 3.45):
    ax2.annotate("", xy=(2.6, y - 0.75), xytext=(2.6, y),
                 arrowprops=dict(arrowstyle="-|>", lw=1.4, ls="--",
                                 color="#555"))
ax2.text(1.05, 5.35, "train-big 在第1关即被拒 (admission)\n后面关卡只有 train-small 走",
         ha="left", va="center", fontsize=7.8, color="#d62728", zorder=5,
         bbox=dict(boxstyle="round,pad=0.18", fc="white", ec="none", alpha=0.92))

outcomes = [
    (6.9, 7.3, "train-small (1卡)", "#2ca02c",
     "配额内 + 有空闲卡\n-> Running, describe node\n可见 GPU 已分配 1/8"),
    (6.9, 6.3, "train-big (6卡)", "#d62728",
     "已用1+要6 > 额度4\n-> exceeded quota,\nPod 在第1关即被拒, 根本不创建"),
]
for cx, cy, head, c, body in outcomes:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 2.0, cy - 0.5), 4.0, 1.0,
                  boxstyle="round,pad=0.07", fc=c, ec="black"))
    ax2.text(cx, cy + 0.18, head, ha="center", fontsize=9.5,
             color="white", fontweight="bold")
    ax2.annotate("", xy=(4.55, cy), xytext=(cx - 2.0, cy),
                 arrowprops=dict(arrowstyle="-|>", lw=1.4, ls="--",
                                 color=c if c == "#d62728" else "black"))
ax2.add_patch(mpatches.FancyBboxPatch((5.1, 1.6), 3.6, 1.5,
              boxstyle="round,pad=0.08", fc="#f5f5f5", ec="#999"))
ax2.text(6.9, 2.72, "巡检命令", ha="center", fontsize=9, fontweight="bold")
ax2.text(6.9, 2.1, "describe nodes -> Allocated\nresources 区段看 GPU 用量;\ncustom-columns 按 Pod 列表",
         ha="center", va="center", fontsize=8)

ax2.set_xlim(0, 10); ax2.set_ylim(0.9, 9.4); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/fake_gpu_operator_arch.png', dpi=150, bbox_inches="tight")
print("saved fake_gpu_operator_arch.png")
