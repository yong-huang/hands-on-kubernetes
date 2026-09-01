#!/usr/bin/env python3
"""EFK 日志链路可视化: 采集管道 + DaemonSet 部署拓扑"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("EFK 日志聚合: Fluent Bit -> Elasticsearch -> Kibana", fontsize=16, fontweight="bold")

# ============================ Panel 1: 单条日志的生命周期 ============================
ax1.set_title("一条容器日志的旅程", fontsize=13)
stages = [
    (1.5, 8.3, "应用 stdout\nprintf JSON 日志", "#aec7e8"),
    (4.6, 8.3, "containerd 写文件\n/var/log/containers/*.log", "#8c564b"),
    (7.9, 8.3, "Fluent Bit tail\n(每节点, 5s Flush)", "#ff7f0e"),
    (7.9, 5.2, "kubernetes filter\n补 ns/pod/container 元数据", "#1f77b4"),
    (4.6, 5.2, "Merge_Log 解析\nJSON 体展开成字段", "#2ca02c"),
    (1.5, 5.2, "es output\n批量写 k8s-logs-日期", "#9467bd"),
    (4.6, 2.2, "Elasticsearch\n倒排索引 + 分片副本", "#d62728"),
    (7.9, 2.2, "Kibana Discover\nlog.level:ERROR 检索", "#f5a623"),
]
for cx, cy, txt, c in stages:
    ax1.add_patch(mpatches.FancyBboxPatch((cx - 1.35, cy - 0.7), 2.7, 1.4,
                  boxstyle="round,pad=0.08", fc=c, ec="black", alpha=0.92))
    tcolor = "black" if c == "#f5a623" else "white"
    ax1.text(cx, cy, txt, ha="center", va="center", fontsize=9, color=tcolor)
path = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7)]
for a, b in path:
    x1, y1 = stages[a][0], stages[a][1] - 0.75
    x2, y2 = stages[b][0], stages[b][1] + 0.75
    if a in (1,) or b in (3,):
        rad = 0.25 if a == 2 else -0.25
    else:
        rad = 0
    ax1.annotate("", xy=(x2, y2), xytext=(x1, y1),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5,
                                 connectionstyle=f"arc3,rad={rad}"))
ax1.text(4.7, 0.55, "关键取舍: Mem_Buf_Limit 控内存; Skip_Long_Lines 丢超长行保吞吐;\n"
                    "Logstash_Format On 按天分索引便于 ILM 删除旧数据",
         ha="center", fontsize=9, color="gray")
ax1.set_xlim(-0.3, 10); ax1.set_ylim(-0.3, 9.5); ax1.axis("off")

# ============================ Panel 2: 节点部署拓扑 ============================
ax2.set_title("DaemonSet 采集拓扑: 为什么是 tail 文件而不是直连容器", fontsize=13)
ax2.add_patch(mpatches.FancyBboxPatch((0.3, 3.4), 4.4, 5.6,
              boxstyle="round,pad=0.12", fc="#f0f4f8", ec="#1f77b4"))
ax2.text(2.5, 8.65, "node-1", ha="center", fontsize=11, fontweight="bold", color="#1f77b4")
for i, name in enumerate(["app-a", "app-b"]):
    ax2.add_patch(mpatches.FancyBboxPatch((0.7 + i * 2.0, 6.6), 1.7, 1.3,
                  boxstyle="round,pad=0.06", fc="#aec7e8", ec="black"))
    ax2.text(1.55 + i * 2.0, 7.25, f"{name}\nstdout/stderr", ha="center",
             va="center", fontsize=8.5)
    ax2.annotate("", xy=(1.55 + i * 2.0, 5.95), xytext=(1.55 + i * 2.0, 6.55),
                 arrowprops=dict(arrowstyle="-|>", lw=1.3, color="#8c564b"))
ax2.add_patch(mpatches.FancyBboxPatch((0.7, 4.6), 3.9, 1.15,
              boxstyle="round,pad=0.06", fc="#8c564b", ec="black"))
ax2.text(2.65, 5.18, "/var/log/containers/*.log\n(符号链接 -> containerd 日志目录)",
         ha="center", va="center", fontsize=8.5, color="white")
ax2.add_patch(mpatches.FancyBboxPatch((1.0, 3.5), 3.3, 0.85,
              boxstyle="round,pad=0.06", fc="#ff7f0e", ec="black"))
ax2.text(2.65, 3.92, "fluent-bit Pod (DaemonSet)", ha="center",
         va="center", fontsize=9, color="white")
# tail 关系: 日志文件 -> fluent-bit (节点内)
ax2.annotate("", xy=(2.65, 4.38), xytext=(2.65, 4.55),
             arrowprops=dict(arrowstyle="-|>", lw=1.3, color="#333"))

ax2.add_patch(mpatches.FancyBboxPatch((5.6, 3.4), 4.1, 5.6,
              boxstyle="round,pad=0.12", fc="#fdf3f3", ec="#d62728"))
ax2.text(7.65, 8.65, "集中层", ha="center", fontsize=11, fontweight="bold", color="#d62728")
for i, name in enumerate(["elasticsearch\n(StatefulSet)", "Kibana\n(Deployment)"]):
    cx = 6.7 + i * 2.0
    c = "#d62728" if i == 0 else "#f5a623"
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 0.9, 6.4), 1.8, 1.6,
                  boxstyle="round,pad=0.06", fc=c, ec="black"))
    ax2.text(cx, 7.2, name, ha="center", va="center", fontsize=8.5,
             color="white" if i == 0 else "black")
ax2.add_patch(mpatches.FancyBboxPatch((5.9, 3.8), 3.5, 1.9,
              boxstyle="round,pad=0.08", fc="#fff", ec="#999"))
ax2.text(7.65, 4.75, "为什么 tail 文件?", ha="center", fontsize=9.5, fontweight="bold")
ax2.text(7.65, 4.15, "• 应用只需写 stdout, 不感知采集器\n"
                     "• 容器崩溃日志仍在磁盘, 不丢\n"
                     "• 与 CRI 无关, 通吃 docker/containerd",
         ha="center", va="center", fontsize=8)

ax2.annotate("", xy=(5.85, 7.2), xytext=(4.35, 4.35),
             arrowprops=dict(arrowstyle="-|>", lw=2, color="#333"))
ax2.text(4.95, 2.6, "RBAC: fluent-bit SA 只需 get/list/watch pods+namespaces\n(k8s filter 反查元数据用)",
         ha="center", fontsize=8.5, color="#555")
ax2.set_xlim(0, 10); ax2.set_ylim(2.2, 9.2); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/logging_efk_arch.png', dpi=150, bbox_inches="tight")
print("saved logging_efk_arch.png")
