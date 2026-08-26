#!/usr/bin/env python3
"""Prometheus + Grafana 监控可视化: 指标数据流 + Operator 声明式监控对象"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("Prometheus + Grafana: 指标流与声明式监控", fontsize=16, fontweight="bold")

# ============================ Panel 1: 指标数据流 ============================
ax1.set_title("指标采集与告警数据流", fontsize=13)
nodes = [
    (1.6, 8.3, "应用 Pod\n/metrics (15s)", "#aec7e8", 2.4),
    (5.0, 8.3, "Prometheus\n拉取+存储 TSDB", "#e4572e", 2.6),
    (8.3, 8.3, "Grafana\n查询渲染面板", "#f5a623", 2.2),
    (5.0, 5.0, "Alertmanager\n去重/分组/路由", "#9467bd", 2.8),
    (1.6, 2.0, "值班人员\n(IM/电话)", "#444444", 2.0),
    (8.3, 2.0, "On-Call 升级链\n(超时升级)", "#76b7b2", 2.2),
]
for cx, cy, txt, c, w in nodes:
    ax1.add_patch(mpatches.FancyBboxPatch((cx - w / 2, cy - 0.75), w, 1.5,
                  boxstyle="round,pad=0.08", fc=c, ec="black", alpha=0.92))
    ax1.text(cx, cy, txt, ha="center", va="center", fontsize=10,
             color="white" if c not in ("#f5a623",) else "black")
arrows = [((2.85, 8.3), (3.65, 8.3)), ((6.35, 8.3), (7.15, 8.3)),
          ((5.0, 7.5), (5.0, 5.8)), ((4.0, 4.55), (2.0, 2.8)),
          ((6.0, 4.55), (8.0, 2.8))]
labels = ["pull", "query", "alert", "notify", "escalate"]
for (x1, y1), (x2, y2), lb in zip(arrows[0], arrows[1], labels):
    pass
for i, ((p1, p2), lb) in enumerate(zip([(a[0], a[1]) for a in arrows], labels)):
    x1, y1 = arrows[i][0]; x2, y2 = arrows[i][1]
    ax1.annotate("", xy=(x2, y2), xytext=(x1, y1),
                 arrowprops=dict(arrowstyle="-|>", lw=1.8, color="#333"))
    ax1.text((x1 + x2) / 2 + 0.25, (y1 + y2) / 2, lb, fontsize=9,
             color="#333", style="italic")
ax1.text(5.0, 0.5, "核心原则: 指标留在集群内查询, 出门的只有告警",
         ha="center", fontsize=10, color="gray", style="italic")
ax1.set_xlim(-0.3, 10); ax1.set_ylim(-0.3, 9.5); ax1.axis("off")

# ============================ Panel 2: CRD 对象关系 ============================
ax2.set_title("Operator 模式: 监控即代码 (CRD -> 配置热加载)", fontsize=13)
crds = [
    (2.2, 8.4, "ServiceMonitor\n抓取谁/多久", "#aec7e8"),
    (2.2, 6.2, "PodMonitor\n直连 Pod 抓取", "#aec7e8"),
    (6.6, 7.3, "PrometheusRule\n告警/录制规则", "#ff7f0e"),
]
for cx, cy, txt, c in crds:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 1.75, cy - 0.65), 3.5, 1.3,
                  boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=9.5)
ax2.add_patch(mpatches.FancyBboxPatch((4.4, 3.6), 3.6, 1.6,
              boxstyle="round,pad=0.1", fc="#e4572e", ec="black"))
ax2.text(6.2, 4.4, "Prometheus Operator\nwatch 全部 CR 变化",
         ha="center", va="center", fontsize=10.5, color="white", fontweight="bold")
ax2.add_patch(mpatches.FancyBboxPatch((0.6, 3.6), 3.0, 1.6,
              boxstyle="round,pad=0.1", fc="#d62728", ec="black"))
ax2.text(2.1, 4.4, "prometheus-k8s\nStatefulSet (TSDB)",
         ha="center", va="center", fontsize=10.5, color="white", fontweight="bold")

for cx, cy in [(2.2, 7.7), (2.2, 5.5), (6.6, 6.6)]:
    pass
ax2.annotate("", xy=(4.35, 4.7), xytext=(2.2, 5.5),
             arrowprops=dict(arrowstyle="-|>", lw=1.6))
ax2.annotate("", xy=(5.6, 4.9), xytext=(6.6, 6.6),
             arrowprops=dict(arrowstyle="-|>", lw=1.6))
ax2.annotate("", xy=(3.65, 4.6), xytext=(5.4, 4.0),
             arrowprops=dict(arrowstyle="<|-|>", lw=1.6, ls="--"))
ax2.text(4.6, 5.15, "渲染配置\ngenerateSecret", ha="center", fontsize=8, color="#555")
ax2.text(3.05, 3.35, "reload", ha="center", fontsize=8, color="#555", style="italic")

ax2.add_patch(mpatches.FancyBboxPatch((0.6, 0.6), 7.4, 1.9,
              boxstyle="round,pad=0.1", fc="#f5f5f5", ec="#1f77b4", ls="--"))
ax2.text(4.3, 2.1, "关键 label 联动", ha="center", fontsize=10, fontweight="bold")
ax2.text(4.3, 1.15,
         "SM/Rule 必须带 operator 的 serviceMonitorSelector/ruleSelector 标签\n"
         "Grafana sidecar 扫描 grafana_datasource/dashboard 标签的 ConfigMap 自动加载",
         ha="center", va="center", fontsize=8.5)

ax2.set_xlim(0, 9.2); ax2.set_ylim(0, 9.5); ax2.axis("off")
plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/monitoring_arch.png', dpi=150, bbox_inches="tight")
print("saved monitoring_arch.png")
