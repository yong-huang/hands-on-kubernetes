#!/usr/bin/env python3
"""CSI 快照架构可视化: 快照/还原数据流 + 备份策略光谱 + 驱动支持矩阵"""
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 7.5))
fig.suptitle("CSI Snapshot: 快照/还原链路与备份策略对比", fontsize=15, fontweight="bold")

C_K8S, C_CTRL, C_CSI, C_STORE, C_NEW = "#4A90D9", "#E67E22", "#8E44AD", "#16A085", "#C0392B"


def box(ax, x, y, w, h, text, color, fs=9):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02",
                                fc=color, ec="black", alpha=0.85))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fs, color="white", fontweight="bold")


def arrow(ax, x1, y1, x2, y2, label="", style="-|>", color="black", ls="-"):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style,
                                 mutation_scale=14, color=color, linestyle=ls, lw=1.4))
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 0.015, label, ha="center",
                fontsize=7.5, color=color,
                bbox=dict(fc="white", ec="none", alpha=0.8, pad=0.5))


# ---------------- Panel 1: 快照/还原链路 ----------------
ax1.set_title("快照与还原数据流", fontsize=12)
ax1.set_xlim(0, 10); ax1.set_ylim(0, 10); ax1.axis("off")

ax1.text(0.1, 9.6, "快照流程", fontsize=10, fontweight="bold", color=C_CSI)
box(ax1, 0.2, 7.8, 2.0, 1.2, "VolumeSnapshot\n(用户 CR)", C_K8S)
box(ax1, 3.0, 7.8, 2.4, 1.2, "snapshot-controller\n(转发 gRPC)", C_CTRL)
box(ax1, 6.2, 7.8, 2.0, 1.2, "CSI 驱动\nCreateSnapshot", C_CSI)
box(ax1, 8.6, 7.8, 1.2, 1.2, "存储后端\n快照", C_STORE)
arrow(ax1, 2.2, 8.4, 3.0, 8.4, "watch")
arrow(ax1, 5.4, 8.4, 6.2, 8.4)
arrow(ax1, 8.2, 8.4, 8.6, 8.4)
box(ax1, 0.2, 6.3, 2.0, 0.9, "源 PVC\n(snap-source)", C_K8S)
arrow(ax1, 1.2, 7.8, 1.2, 7.2, "spec.source\n.pvcName", style="<|-")
box(ax1, 3.6, 6.3, 3.0, 0.9, "VolumeSnapshotContent\n(集群级, 绑定快照)", C_K8S)
arrow(ax1, 7.0, 8.0, 6.4, 7.2, "创建并回填", ls="--")
ax1.text(5.5, 5.75, "status: readyToUse=true / restoreSize=1Gi", fontsize=7.5,
         ha="center", style="italic", color="#555")

ax1.text(0.1, 4.9, "还原流程 (永远生成新 PVC, 不能原地覆盖)", fontsize=10,
         fontweight="bold", color=C_NEW)
box(ax1, 0.2, 3.2, 2.2, 1.0, "新 PVC\ndataSource: VolumeSnapshot", C_K8S, 8)
box(ax1, 3.4, 3.2, 2.2, 1.0, "存储控制器\n从快照 clone 新卷", C_CSI, 8)
box(ax1, 6.4, 3.2, 1.6, 1.0, "新 PV\nBound", C_STORE, 8)
arrow(ax1, 2.4, 3.7, 3.4, 3.7, "引用快照")
arrow(ax1, 5.6, 3.7, 6.4, 3.7)
ax1.text(5.0, 2.6, "新 Pod 挂新 PVC → 读到快照时刻的数据", fontsize=8.5, ha="center")

ax1.text(0.1, 1.9, "kind 上的现实 (诚实预期)", fontsize=10, fontweight="bold", color="#7F8C8D")
ax1.add_patch(FancyBboxPatch((0.2, 0.3), 9.6, 1.3, boxstyle="round,pad=0.05",
                             fc="#FDF2E9", ec="#E67E22"))
ax1.text(5.0, 0.95,
         "local-path (rancher.io/local-path) 未实现 CSI 快照接口:\n"
         "VolumeSnapshot 对象能创建, 但 readyToUse 永远不变 true;\n"
         "还原 PVC 只会一直 Pending —— 换 EBS/Longhorn/Ceph 才能走通全链路",
         ha="center", va="center", fontsize=8.5, color="#B9540B")

# ---------------- Panel 2: 备份策略光谱 + 驱动矩阵 ----------------
ax2.set_title("备份策略光谱与驱动支持矩阵", fontsize=12)
ax2.set_xlim(0, 10); ax2.set_ylim(0, 10); ax2.axis("off")

strategies = [
    ("CSI Snapshot", "存储级快照, 秒级增量,\n同集群内回滚/克隆", C_CSI, 7.8),
    ("Velero", "K8s 对象 + PV 数据,\n可跨集群/异地容灾", C_CTRL, 4.3),
    ("应用级备份", "mysqldump / pg_dump,\n逻辑导出, 可跨存储引擎", C_STORE, 0.8),
]
for name, desc, color, y in strategies:
    box(ax2, 0.2, y, 2.4, 1.6, name, color, 9)
    ax2.text(2.8, y + 0.8, desc, fontsize=8, va="center", color="#333")

arrow(ax2, 5.6, 8.6, 5.6, 1.0, "通用性增强 / 速度下降", color="#666")
ax2.text(5.0, 9.4, "三层并不互斥: 生产常组合使用 (快照保 RPO + Velero 保容灾)",
         fontsize=8.5, ha="center", color="#666", style="italic")

rows = [
    ("EBS CSI (AWS)", "ebs.csi.aws.com", "支持"),
    ("Cinder (OpenStack)", "cinder.csi.openstack.org", "支持"),
    ("Portworx", "pxd.openstorage.org", "支持"),
    ("Longhorn", "driver.longhorn.io", "支持"),
    ("Ceph RBD", "rbd.csi.ceph.com", "支持"),
    ("kind local-path", "rancher.io/local-path", "不支持"),
]
ax2.text(5.9, 6.6, "CSI 驱动快照支持矩阵", fontsize=10, fontweight="bold")
for i, (name, driver, ok) in enumerate(rows):
    y = 5.9 - i * 0.85
    fc = "#EAFAF1" if ok == "支持" else "#FDEDEC"
    ec = "#16A085" if ok == "支持" else "#C0392B"
    ax2.add_patch(FancyBboxPatch((5.9, y - 0.28), 3.9, 0.7,
                                 boxstyle="round,pad=0.02", fc=fc, ec=ec))
    ax2.text(6.05, y, name, fontsize=8, va="center", fontweight="bold")
    ax2.text(8.0, y, driver, fontsize=6.5, va="center", color="#555")
    ax2.text(9.5, y, ok, fontsize=8, va="center", ha="right",
             color=("#16A085" if ok == "支持" else "#C0392B"), fontweight="bold")

plt.tight_layout()
plt.savefig('images/csi_snapshot_arch.png', dpi=150, bbox_inches="tight")
print("saved csi_snapshot_arch.png")
