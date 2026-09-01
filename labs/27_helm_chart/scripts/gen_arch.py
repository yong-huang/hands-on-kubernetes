#!/usr/bin/env python3
"""Helm 可视化: Chart 目录结构 + 模板渲染流水线"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("Helm Chart: 目录结构与模板渲染流水线", fontsize=16, fontweight="bold")

# ============================ Panel 1: Chart 目录树 ============================
ax1.set_title("Chart 目录结构 (demo-chart)", fontsize=13)
tree = [
    ("demo-chart/", 0, True),
    ("Chart.yaml      # chart 版本 / appVersion", 1, False),
    ("values.yaml     # 默认值(可被 --set 覆盖)", 1, False),
    ("templates/", 1, True),
    ("deployment.yaml  # .Values.replicaCount", 2, False),
    ("service.yaml     # {{ include helpers }}", 2, False),
    ("configmap.yaml   # {{ range features }}", 2, False),
    ("ingress.yaml     # {{ if enabled }} 条件渲染", 2, False),
    ("_helpers.tpl     # 命名/标签公共定义", 2, False),
    ("NOTES.txt        # 安装后使用说明", 2, False),
    ("charts/          # 子 chart 依赖(可选)", 1, False),
]
y = 9.0
for name, depth, is_dir in tree:
    c = "#1f77b4" if is_dir else "#333333"
    ax1.text(0.4 + depth * 0.55, y, name, fontsize=9,
             color=c, fontweight="bold" if is_dir else "normal")
    y -= 0.82

ax1.add_patch(mpatches.FancyBboxPatch((5.6, 3.3), 4.15, 5.6,
              boxstyle="round,pad=0.12", fc="#f5f8fb", ec="#1f77b4"))
ax1.text(7.65, 8.55, "模板内置对象速查", ha="center", fontsize=10.5,
         fontweight="bold", color="#1f77b4")
objs = [
    (".Release.Name", "安装时指定的 release 名"),
    (".Chart.Name/AppVersion", "来自 Chart.yaml"),
    (".Values.*", "values.yaml 与 -f/--set 合并结果"),
    (".Capabilities", "集群 API 版本能力探测"),
]
for i, (obj, desc) in enumerate(objs):
    yy = 7.85 - i * 1.15
    ax1.text(5.95, yy, obj, fontsize=8.6)
    ax1.text(5.95, yy - 0.45, desc, fontsize=7.8, color="#666")

ax1.add_patch(mpatches.FancyBboxPatch((5.6, 0.6), 4.15, 2.2,
              boxstyle="round,pad=0.12", fc="#fff8e1", ec="#f5a623"))
ax1.text(7.65, 2.35, "命名约定 (_helpers.tpl)", ha="center",
         fontsize=9.5, fontweight="bold")
ax1.text(7.65, 1.25, "{{ release }}-{{ chart }} 前缀命名,\nselector 与 label 保持一致,\n同 chart 多 release 互不干扰",
         ha="center", va="center", fontsize=8.5)

ax1.set_xlim(-0.2, 10); ax1.set_ylim(-0.3, 9.6); ax1.axis("off")

# ============================ Panel 2: 渲染流水线 ============================
ax2.set_title("helm upgrade: values 合并 -> Go template -> K8s API", fontsize=13)
layers = [
    (5.0, 8.6, "chart 内置 values.yaml\n(默认值, 优先级最低)", "#aec7e8"),
    (2.6, 6.4, "-f my-values.yaml\n(文件覆盖)", "#2ca02c"),
    (7.4, 6.4, "--set image.tag=v2\n(命令行, 优先级最高)", "#ff7f0e"),
]
for cx, cy, txt, c in layers:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 1.75, cy - 0.62), 3.5, 1.24,
                  boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=9,
             color="white" if c != "#aec7e8" else "black")
for cx in (2.6, 7.4):
    ax2.annotate("", xy=(4.4, 8.0), xytext=(cx + (1.0 if cx < 5 else -1.0), 7.05),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5))

pipe = [
    (2.0, 4.3, "合并后的 .Values\n作用域对象", "#1f77b4"),
    (5.0, 4.3, "Go template 引擎\nhelm template 本地预览", "#9467bd"),
    (8.0, 4.3, "校验后提交\nK8s API", "#d62728"),
]
for cx, cy, txt, c in pipe:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 1.15, cy - 0.65), 2.3, 1.3,
                  boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=8.8, color="white")
for i in range(2):
    x1 = pipe[i][0] + 1.2; x2 = pipe[i + 1][0] - 1.2
    ax2.annotate("", xy=(x2, 4.3), xytext=(x1, 4.3),
                 arrowprops=dict(arrowstyle="-|>", lw=1.6))

# release 版本历史
ax2.add_patch(mpatches.FancyBboxPatch((0.6, 0.5), 8.8, 2.4,
              boxstyle="round,pad=0.12", fc="#f5f5f5", ec="#999"))
ax2.text(5.0, 2.55, "Release 版本机制 (可回滚的秘密)", ha="center",
         fontsize=10, fontweight="bold")
hist = [(1.6, "rev1\ninstall"), (3.8, "rev2\nupgrade 副本3"),
        (6.0, "rev3\nupgrade 改tag"), (8.2, "rollback 2\n回到 rev2")]
for cx, txt in hist:
    ax2.add_patch(mpatches.Circle((cx, 1.55), 0.16, fc="#d62728"))
    ax2.text(cx, 0.95, txt, ha="center", fontsize=8)
for i in range(3):
    ax2.plot([hist[i][0] + 0.18, hist[i + 1][0] - 0.18], [1.55, 1.55],
             color="#d62728", lw=1.5)

ax2.set_xlim(-0.2, 10); ax2.set_ylim(0.2, 9.5); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/helm_chart_arch.png', dpi=150, bbox_inches="tight")
print("saved helm_chart_arch.png")
