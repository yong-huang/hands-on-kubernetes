#!/usr/bin/env python3
"""kubectl debug 可视化: 临时容器原理(共享命名空间) + 三种调试姿势决策树"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("高级排障: Ephemeral Container 与 kubectl debug", fontsize=16, fontweight="bold")

# ============================ Panel 1: Pod 剖面图 ============================
ax1.set_title("临时容器如何进入故障 Pod (--target 共享 PID ns)", fontsize=13)
ax1.add_patch(mpatches.FancyBboxPatch((0.4, 3.6), 5.2, 5.6,
              boxstyle="round,pad=0.12", fc="#f0f4f8", ec="#1f77b4"))
ax1.text(3.0, 8.85, "broken-app Pod (node-x)", ha="center",
         fontsize=11, fontweight="bold", color="#1f77b4")
ax1.add_patch(mpatches.FancyBboxPatch((0.8, 5.9), 4.4, 2.2,
              boxstyle="round,pad=0.08", fc="#d62728", ec="black"))
ax1.text(3.0, 7.55, "app 容器 (distroless, 无 shell)", ha="center",
         fontsize=10, color="white", fontweight="bold")
ax1.text(3.0, 6.55, "PID 1: /broken-binary  <- 启动即崩\nPID ns 本容器独有(net/ipc ns 为 Pod 级共享); 文件系统只读挂载",
         ha="center", va="center", fontsize=8.2, color="white")

ax1.add_patch(mpatches.FancyBboxPatch((0.8, 3.7), 4.4, 1.7,
              boxstyle="round,pad=0.08", fc="#2ca02c", ec="black"))
ax1.text(3.0, 4.95, "debugger 容器 (busybox) [临时容器]", ha="center",
         fontsize=9.5, color="white", fontweight="bold")
ax1.text(3.0, 4.25, "kubectl debug --target=app\n加入同一 PID ns -> ps 看到 PID 1,\n/proc/1/root 读到对方文件系统",
         ha="center", va="center", fontsize=8.2, color="white")

# 同一 net ns 说明
ax1.add_patch(mpatches.FancyBboxPatch((6.1, 5.9), 3.4, 2.2,
              boxstyle="round,pad=0.1", fc="#fff", ec="#1f77b4", ls="--"))
ax1.text(7.8, 7.55, "天然共享 (Pod 内所有容器):", ha="center", fontsize=9.5)
ax1.text(6.35, 6.65, "• network ns   同 IP:port\n• IPC ns       同信号量\n• UTS ns       同 hostname",
         ha="left", va="center", fontsize=9)

ax1.add_patch(mpatches.FancyBboxPatch((6.1, 3.9), 3.4, 1.6,
              boxstyle="round,pad=0.1", fc="#fff", ec="#d62728", ls="--"))
ax1.text(7.8, 5.05, "临时容器的限制:", ha="center", fontsize=9.5, color="#d62728")
ax1.text(6.35, 4.35, "• 禁止 ports/probes/lifecycle/resources\n• env 可以设置\n• 不能 restart; exec 需 -c 指定容器",
         ha="left", va="center", fontsize=8.5)

ax1.annotate("", xy=(3.0, 5.6), xytext=(3.0, 5.95),
             arrowprops=dict(arrowstyle="<|-|>", lw=1.8, color="#333"))
ax1.text(3.0, 3.15, "价值: 不改镜像、不动原容器, 就能诊断 '黑盒' 故障",
         ha="center", fontsize=10, color="#2ca02c", fontweight="bold")
ax1.set_xlim(0, 10); ax1.set_ylim(2.8, 9.4); ax1.axis("off")

# ============================ Panel 2: 三姿势决策树 ============================
ax2.set_title("三种调试姿势怎么选", fontsize=13)
root = (5.0, 8.6, "Pod 出问题了\nkubectl describe 先看 Events", "#444")
q1 = (2.6, 6.6, "容器还活着吗?", "#1f77b4")
a1 = (0.95, 4.4, "CrashLoop / 无 shell\n-> 姿势1 注入临时容器\n--target 共享PID", "#ff7f0e")
a2 = (2.6, 4.4, "探针互斥 / 怕影响线上\n-> 姿势2 复制克隆 Pod\n--copy-to 调试副本", "#2ca02c")
a3 = (4.6, 4.4, "怀疑节点层问题\n(CNI/kubelet/磁盘)\n-> 姿势3 节点调试\nchroot /host", "#9467bd")
for cx, cy, txt, c in [root, q1, a1, a2, a3]:
    w = 2.0 if (cx, cy) in [(root[0], root[1]), (q1[0], q1[1])] else 2.1
    ax2.add_patch(mpatches.FancyBboxPatch((cx - w / 2, cy - 0.75), w, 1.5,
                  boxstyle="round,pad=0.07", fc=c, ec="black", alpha=0.93))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=8,
             color="white" if c != "#444" else "white")
ax2.annotate("", xy=(2.6, 7.4), xytext=(5.0, 7.85),
             arrowprops=dict(arrowstyle="-|>", lw=1.5))
for x in (0.95, 2.6, 4.6):
    rad = {"0.95": "-0.35", "2.6": "0", "4.6": "0.35"}[str(x)]
    ax2.annotate("", xy=(x, 5.25), xytext=(2.6, 5.85),
                 arrowprops=dict(arrowstyle="-|>", lw=1.4,
                                 connectionstyle=f"arc3,rad={rad}"))

ax2.add_patch(mpatches.FancyBboxPatch((6.6, 3.6), 3.1, 5.4,
              boxstyle="round,pad=0.12", fc="#f5f5f5", ec="#999"))
ax2.text(8.15, 8.6, "常用工具箱镜像", ha="center", fontsize=10, fontweight="bold")
tools = [
    ("busybox", "ps / ls / nc 轻量"),
    ("nicolaka/netshoot", "tcpdump dig mtr 全套网络"),
    ("ubuntu", "通用 + chroot 宿主机"),
]
for i, (img, desc) in enumerate(tools):
    y = 7.7 - i * 1.35
    ax2.text(6.85, y, img, fontsize=8.5, family="monospace")
    ax2.text(6.85, y - 0.42, desc, fontsize=8, color="#666")
ax2.text(8.15, 4.0, "注意: 别把调试镜像\n留在生产 Pod spec 里", fontsize=8.5,
         color="#d62728", ha="center")
ax2.set_xlim(-0.35, 10); ax2.set_ylim(3.4, 9.4); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/ephemeral_debug_arch.png', dpi=150, bbox_inches="tight")
print("saved ephemeral_debug_arch.png")
