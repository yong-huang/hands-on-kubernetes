#!/usr/bin/env python3
"""Karmada 多集群联邦可视化: 控制面架构 + 副本分发与故障转移"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("Karmada 多集群联邦: 一份声明, 多集群编排", fontsize=16, fontweight="bold")

# ============================ Panel 1: 控制面架构 ============================
ax1.set_title("控制面与资源传播链", fontsize=13)
ax1.add_patch(mpatches.FancyBboxPatch((0.4, 5.6), 9.2, 3.6,
              boxstyle="round,pad=0.12", fc="#f5f8fb", ec="#1f77b4"))
ax1.text(5.0, 8.85, "Karmada 控制面 (host 集群)", ha="center",
         fontsize=11, fontweight="bold", color="#1f77b4")
comps = [
    (1.9, "karmada-apiserver\n统一入口(兼容原生API)", "#aec7e8"),
    (4.3, "karmada-controller\n创建 ResourceBinding", "#2ca02c"),
    (6.7, "karmada-scheduler\n选集群/拆副本", "#ff7f0e"),
    (8.6, "execution-controller\n下发到成员集群", "#9467bd"),
]
for cx, txt, c in comps:
    ax1.add_patch(mpatches.FancyBboxPatch((cx - 0.95, 6.6), 1.9, 1.7,
                  boxstyle="round,pad=0.07", fc=c, ec="black"))
    ax1.text(cx, 7.45, txt, ha="center", va="center", fontsize=7.8,
             color="white")
for i in range(3):
    x1 = comps[i][0] + 0.98; x2 = comps[i + 1][0] - 0.98
    ax1.annotate("", xy=(x2, 7.45), xytext=(x1, 7.45),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5))

# 用户提交侧
ax1.add_patch(mpatches.FancyBboxPatch((0.6, 4.35), 3.2, 0.9,
              boxstyle="round,pad=0.07", fc="#444444"))
ax1.text(2.2, 4.8, "用户只提交: Deployment\n+ PropagationPolicy",
         ha="center", va="center", fontsize=8.8, color="white")
ax1.annotate("", xy=(1.9, 5.55), xytext=(2.2, 5.3),
             arrowprops=dict(arrowstyle="-|>", lw=1.5))

# 成员集群
members = [(2.2, 2.6, "member-us", "#d62728", "replicas=4\nnginx:1.25-us"),
           (7.8, 2.6, "member-ap", "#e377c2", "replicas=2\n镜像源替换为\nregistry.ap...")]
for cx, cy, name, c, detail in members:
    ax1.add_patch(mpatches.FancyBboxPatch((cx - 1.6, cy - 0.95), 3.2, 1.9,
                  boxstyle="round,pad=0.1", fc="white", ec=c, lw=2))
    ax1.text(cx, cy + 0.55, name, ha="center", fontsize=11,
             fontweight="bold", color=c)
    ax1.text(cx, cy - 0.25, detail, ha="center", va="center", fontsize=8)
ax1.annotate("", xy=(2.2, 3.65), xytext=(8.6, 6.55),
             arrowprops=dict(arrowstyle="-|>", lw=1.6,
                             connectionstyle="arc3,rad=-0.15"))
ax1.annotate("", xy=(7.8, 3.65), xytext=(8.6, 6.55),
             arrowprops=dict(arrowstyle="-|>", lw=1.6,
                             connectionstyle="arc3,rad=0.15"))
ax1.text(5.0, 0.75, "成员集群只需网络可达 host; 不装任何 Karmada 组件 (push 模式)",
         ha="center", fontsize=9.5, color="#555")
ax1.set_xlim(-0.2, 10); ax1.set_ylim(0.3, 9.5); ax1.axis("off")

# ============================ Panel 2: 调度与故障转移 ============================
ax2.set_title("副本拆分与故障转移 (Divided + Weighted)", fontsize=13)
# 初始状态
ax2.text(0.5, 8.7, "初始: replicas=6, 权重 us:ap = 4:2", fontsize=10,
         fontweight="bold")
ax2.add_patch(mpatches.FancyBboxPatch((0.6, 7.2), 4.0, 1.2,
              boxstyle="round,pad=0.08", fc="#d62728", alpha=0.85))
ax2.text(2.6, 7.8, "member-us: 4 pods", ha="center", va="center",
         fontsize=10, color="white")
ax2.add_patch(mpatches.FancyBboxPatch((5.0, 7.2), 2.4, 1.2,
              boxstyle="round,pad=0.08", fc="#e377c2", alpha=0.85))
ax2.text(6.2, 7.8, "member-ap: 2", ha="center", va="center",
         fontsize=10, color="white")
ax2.add_patch(mpatches.FancyBboxPatch((7.7, 7.2), 1.9, 1.2,
              boxstyle="round,pad=0.08", fc="#eeeeee", ec="#999"))
ax2.text(8.65, 7.8, "空闲容量", ha="center", va="center",
         fontsize=9, color="#666")

# 扩容
ax2.annotate("", xy=(5.0, 6.9), xytext=(5.0, 7.1),
             arrowprops=dict(arrowstyle="-|>", lw=1.5))
ax2.text(0.5, 6.15, "扩容 replicas 6 -> 12: 按 4:2 权重再平衡为 8/4",
         fontsize=10, fontweight="bold")
ax2.add_patch(mpatches.FancyBboxPatch((0.6, 4.6), 4.0, 1.2,
              boxstyle="round,pad=0.08", fc="#d62728", alpha=0.85))
ax2.text(2.6, 5.2, "member-us: 8 pods", ha="center", va="center",
         fontsize=10, color="white")
ax2.add_patch(mpatches.FancyBboxPatch((5.0, 4.6), 2.4, 1.2,
              boxstyle="round,pad=0.08", fc="#e377c2", alpha=0.85))
ax2.text(6.2, 5.2, "member-ap: 4", ha="center", va="center",
         fontsize=10, color="white")

# 故障转移
ax2.text(0.5, 3.55, "failover: member-ap 失联 60s -> 份额自动迁移",
         fontsize=10, fontweight="bold", color="#d62728")
ax2.add_patch(mpatches.FancyBboxPatch((5.0, 2.0), 2.4, 1.2,
              boxstyle="round,pad=0.08", fc="#bbbbbb", ec="#999", ls="--"))
ax2.text(6.2, 2.6, "member-ap\nNotReady x", ha="center", va="center",
         fontsize=9.5, color="#666")
ax2.add_patch(mpatches.FancyBboxPatch((0.6, 2.0), 4.0, 1.2,
              boxstyle="round,pad=0.08", fc="#d62728", alpha=0.95))
ax2.text(2.6, 2.6, "member-us: 8 -> 12 pods\n接管全部流量", ha="center",
         va="center", fontsize=9.5, color="white")
ax2.annotate("", xy=(2.6, 3.3), xytext=(5.0, 2.6),
             arrowprops=dict(arrowstyle="-|>", lw=2, color="#d62728"))

ax2.add_patch(mpatches.FancyBboxPatch((0.6, 0.45), 9.0, 1.05,
              boxstyle="round,pad=0.08", fc="#fff8e1", ec="#f5a623"))
ax2.text(5.1, 0.97, "策略对象分工:", ha="left", fontsize=9, fontweight="bold")
ax2.text(5.1, 0.68, "PropagationPolicy 决定'去哪/几份' | OverridePolicy 决定'差异长什么样'\n"
                    "ResourceBinding 记录调度结果 | clusterTolerations 触发故障转移",
         ha="left", fontsize=8)

ax2.set_xlim(0, 10); ax2.set_ylim(0.2, 9.1); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/multicluster_federation_arch.png', dpi=150, bbox_inches="tight")
print("saved multicluster_federation_arch.png")
