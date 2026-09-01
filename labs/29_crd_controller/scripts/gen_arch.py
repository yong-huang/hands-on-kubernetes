#!/usr/bin/env python3
"""CRD/Operator 可视化: 扩展 API 结构 + Reconcile 调谐循环"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("CRD 与 Controller: 声明式扩展 K8s API", fontsize=16, fontweight="bold")

# ============================ Panel 1: API 扩展结构 ============================
ax1.set_title("CRD 如何长进 API Server", fontsize=13)
ax1.add_patch(mpatches.FancyBboxPatch((0.5, 5.2), 4.3, 3.9,
              boxstyle="round,pad=0.12", fc="#f0f4f8", ec="#1f77b4"))
ax1.text(2.65, 8.7, "API Server 内置组", ha="center", fontsize=10,
         fontweight="bold", color="#1f77b4")
for i, res in enumerate(["apps/Deployments", "core/Pods", "batch/Jobs"]):
    ax1.add_patch(mpatches.FancyBboxPatch((0.9, 7.6 - i * 0.85), 3.4, 0.62,
                  boxstyle="round,pad=0.05", fc="#aec7e8", ec="black"))
    ax1.text(2.6, 7.9 - i * 0.85, res, ha="center", va="center", fontsize=9)

ax1.annotate("", xy=(2.65, 5.15), xytext=(2.65, 4.35),
             arrowprops=dict(arrowstyle="-|>", lw=2))
ax1.text(3.3, 4.75, "CRD 注册\napiextensions.k8s.io", ha="left", va="center",
         fontsize=9.5, color="#d62728", fontweight="bold")

ax1.add_patch(mpatches.FancyBboxPatch((0.5, 0.5), 4.3, 3.6,
              boxstyle="round,pad=0.12", fc="#fdf3ec", ec="#ff7f0e"))
ax1.text(2.65, 3.75, "自定义组 demo.example.com/v1alpha1", ha="center",
         fontsize=10, fontweight="bold", color="#ff7f0e")
rows = [
    ("REST 路径", "/apis/demo.example.com/v1alpha1/databases"),
    ("kubectl", "get databases / get db (shortNames)"),
    ("openAPIV3Schema", "字段强校验, 非法 CR 直接拒绝"),
    ("subresources.status", "spec/status 分权: 用户写 spec,\ncontroller 写 status"),
]
for i, (k, v) in enumerate(rows):
    yy = 3.05 - i * 0.72
    ax1.text(0.85, yy, k, fontsize=8.5, fontweight="bold")
    ax1.text(0.85, yy - 0.33, v, fontsize=8, color="#555")

ax1.add_patch(mpatches.FancyBboxPatch((5.4, 2.3), 4.3, 3.75,
              boxstyle="round,pad=0.12", fc="#f5f5f5", ec="#999"))
ax1.text(7.55, 5.7, "一份 Database CR 就是全部输入", ha="center",
         fontsize=10.5, fontweight="bold")
ax1.text(5.75, 5.32,
         "apiVersion: demo.example.com/v1alpha1\n"
         "kind: Database\n"
         "metadata:\n"
         "  name: orders-db\n"
         "spec:\n"
         "  engine: postgres   # enum 校验\n"
         "  size: 10Gi         # pattern 校验\n"
         "  replicas: 1        # min/max\n"
         "status:              # 由 controller 回写\n"
         "  phase: Running\n"
         "  endpoint: orders-db.crd-demo.svc",
         fontsize=8.5, va="top",
         family=["DejaVu Sans Mono", "Hiragino Sans GB", "Arial Unicode MS"])
ax1.set_xlim(0, 10); ax1.set_ylim(0, 9.4); ax1.axis("off")

# ============================ Panel 2: Reconcile 循环 ============================
ax2.set_title("Reconcile Loop: 永远朝期望状态收敛 (水平触发)", fontsize=13)
nodes = [
    (2.0, 8.3, 2.4, "Informer watch (生产版)\nDatabase 变化事件", "#aec7e8"),
    (5.2, 8.3, 2.3, "工作队列\n(key=ns/name 去重)", "#1f77b4"),
    (8.05, 8.3, 2.2, "Reconcile(name)\n读最新 CR", "#2ca02c"),
    (8.05, 5.4, 2.2, "对比 期望(spec)\nvs 实际(集群)", "#ff7f0e"),
    (5.2, 5.4, 2.3, "有差异 -> 创建/更新\nStatefulSet (VCT 数据卷)", "#d62728"),
    (2.0, 5.4, 2.4, "回写 status\nphase/endpoint", "#9467bd"),
    (5.2, 2.4, 2.3, "重新入队 / 周期重调谐\n(失败重试, 幂等安全)", "#444444"),
]
for cx, cy, w, txt, c in nodes:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - w / 2, cy - 0.62),
                  w, 1.24, boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=8.8,
             color="white")
arrows = [((3.24, 8.3), (4.01, 8.3)),      # informer -> 工作队列
          ((6.39, 8.3), (6.91, 8.3)),      # 队列 -> reconcile
          ((8.05, 7.66), (8.05, 6.06)),    # reconcile -> 对比
          ((6.91, 5.4), (6.39, 5.4)),      # 对比 -> 创建/更新
          ((4.6, 4.76), (3.24, 5.12)),     # 创建 -> 回写 status
          ((2.0, 4.76), (2.0, 3.06))]      # 回写 -> 重新入队
for (x1, y1), (x2, y2) in arrows:
    ax2.annotate("", xy=(x2, y2), xytext=(x1, y1),
                 arrowprops=dict(arrowstyle="-|>", lw=1.6))
# 循环回路: 重新入队 -> 沿左侧边回到 watch (水平触发, 漏事件也安全)
ax2.annotate("", xy=(1.2, 7.66), xytext=(4.0, 2.5),
             arrowprops=dict(arrowstyle="-|>", lw=1.5, color="#555",
                             connectionstyle="arc3,rad=-0.3"))
ax2.text(5.0, 0.9, "水平触发的本质: 不关心'发生了什么', 只关心'现在是什么';\n"
                   "reconcile 幂等 => 重启/漏事件/重复处理都安全",
         ha="center", fontsize=9.5, color="#333")
ax2.set_xlim(-0.7, 9.7); ax2.set_ylim(0.4, 9.3); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/crd_controller_arch.png', dpi=150, bbox_inches="tight")
print("saved crd_controller_arch.png")
