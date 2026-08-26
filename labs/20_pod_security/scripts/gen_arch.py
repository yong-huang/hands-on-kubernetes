#!/usr/bin/env python3
"""Pod Security Standards / Admission 可视化: 三等级策略 + 准入流程与标签解剖"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("Kubernetes Pod Security: PSS 三等级 与 PSA 准入流程", fontsize=16, fontweight="bold")

# ============================ Panel 1: 三等级金字塔 ============================
ax1.set_title("PSS 三个安全等级 (从严到宽)", fontsize=13)
levels = [
    ("restricted", 0.55, "#d62728", "最严格",
     ["必须 runAsNonRoot (禁 uid=0)", "必须 drop ALL capabilities",
      "必须 seccompProfile=RuntimeDefault", "禁止 allowPrivilegeEscalation"]),
    ("baseline", 0.78, "#ff7f0e", "中等",
     ["禁宿主命名空间 (hostNetwork/PID/IPC)", "禁特权容器 (privileged)",
      "禁危险挂载 (hostPath /proc /sys)", "禁新增 capabilities (如 CAP_SYS_ADMIN)"]),
    ("privileged", 1.0, "#2ca02c", "无限制",
     ["全部放开, 不做任何检查", "仅给系统组件 (CNI/CSI/监控) 使用"]),
]
y0 = 9.6
for i, (name, width, color, tag, items) in enumerate(levels):
    cx, cy, h = 5.0, y0 - i * 3.2, 2.4
    ax1.add_patch(mpatches.FancyBboxPatch(
        (cx - width * 5, cy - h / 2), width * 10, h,
        boxstyle="round,pad=0.08", fc=color, ec="black", alpha=0.85))
    ax1.text(cx, cy + 0.45, name, ha="center", fontsize=14,
             fontweight="bold", color="white")
    ax1.text(cx + width * 5 - 0.15, cy + 0.45, tag, ha="right",
             fontsize=9, color="white", style="italic")
    ax1.text(cx, cy - 0.55, "\n".join(items), ha="center", va="center",
             fontsize=8.5, color="white")
    if i < 2:
        ax1.annotate("", xy=(cx, cy - h / 2 - 0.65), xytext=(cx, cy - h / 2 - 0.05),
                     arrowprops=dict(arrowstyle="-|>", color="gray", lw=1.5))
ax1.text(5.0, y0 - 2 * 3.2 - 1.6, "包含关系: restricted 的要求 ⊇ baseline 的要求 ⊇ 无",
         ha="center", fontsize=9, color="gray")
ax1.set_xlim(0, 10); ax1.set_ylim(-1.2, 10.5); ax1.axis("off")

# ============================ Panel 2: 准入流程 + 标签解剖 ============================
ax2.set_title("PSA 准入流程与 namespace 标签", fontsize=13)
ax2.axis("off")

boxes = [
    (2.5, 8.6, "kubectl create pod", "#aec7e8"),
    (2.5, 6.9, "PodSecurity Admission\n读取所在 ns 的标签", "#1f77b4"),
]
for cx, cy, txt, c in boxes:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 2.1, cy - 0.55), 4.2, 1.1,
                  boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=10,
             color="white" if c == "#1f77b4" else "black")

ax2.annotate("", xy=(2.5, 7.5), xytext=(2.5, 8.0), arrowprops=dict(arrowstyle="-|>", lw=1.5))

# 标签解剖
ax2.add_patch(mpatches.FancyBboxPatch((0.25, 4.9), 4.5, 1.5,
              boxstyle="round,pad=0.1", fc="#f5f5f5", ec="#1f77b4", ls="--"))
ax2.text(2.5, 6.1, "标签解剖", ha="center", fontsize=10, fontweight="bold")
ax2.text(2.5, 5.35,
         "pod-security.kubernetes.io/enforce: restricted\n"
         "pod-security.kubernetes.io/enforce-version: v1.36\n"
         "mode ∈ {enforce, audit, warn}  version 可固定",
         ha="center", va="center", fontsize=8.5, family="monospace")
ax2.annotate("", xy=(2.5, 6.5), xytext=(2.5, 6.3),
             arrowprops=dict(arrowstyle="-|>", lw=1.2, color="#1f77b4"))

# 三种模式分支
modes = [
    (0.95, 3.3, "enforce 违规", "#d62728", "拒绝创建\nAPI 返回 Forbidden"),
    (2.5, 3.3, "audit 违规", "#ff7f0e", "照常创建\n审计日志记事件"),
    (4.05, 3.3, "warn 违规", "#e6b800", "照常创建\nkubectl 打印警告"),
    (2.5, 1.4, "合规", "#2ca02c", "静默放行"),
]
for cx, cy, head, c, body in modes:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 0.72, cy - 0.5), 1.44, 1.0,
                  boxstyle="round,pad=0.06", fc=c, ec="black", alpha=0.9))
    ax2.text(cx, cy + 0.18, head, ha="center", fontsize=9, color="white", fontweight="bold")
    ax2.text(cx, cy - 0.22, body, ha="center", va="center", fontsize=7.5, color="white")
for xy in [(0.95, 3.85), (2.5, 3.85), (4.05, 3.85)]:
    ax2.annotate("", xy=xy, xytext=(2.5, 4.85),
                 arrowprops=dict(arrowstyle="-|>", lw=1.2, color="#1f77b4"))
ax2.annotate("", xy=(2.5, 1.95), xytext=(2.5, 4.85),
             arrowprops=dict(arrowstyle="-|>", lw=1.2, color="#2ca02c",
                             connectionstyle="arc3,rad=-0.35"))

ax2.text(2.5, 0.4, "灰度路径: warn (观察影响面) -> audit (留痕) -> enforce (强制)",
         ha="center", fontsize=9, color="gray", style="italic")
ax2.set_xlim(0, 5); ax2.set_ylim(0, 9.6)

plt.tight_layout(rect=[0, 0, 1, 0.95])
plt.savefig('images/pod_security_arch.png', dpi=150, bbox_inches="tight")
print("saved pod_security_arch.png")
