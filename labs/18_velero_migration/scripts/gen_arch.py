"""Velero 可视化: 架构(controller + node agent -> 对象存储) + 跨集群迁移流程 vs CSI 快照"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'velero_migration_arch.png')

# 配色
C_CTRL = '#4c72b0'      # velero controller: 蓝
C_AGENT = '#55a868'     # node agent: 绿
C_STORE = '#8172b3'     # object storage: 紫
C_BACKUP = '#f4c542'    # backup arrow: 黄
C_RESTORE = '#c44e52'   # restore arrow: 红
C_CSI = '#64b5cd'       # CSI snapshot: 浅蓝
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333', fs=9.5):
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.14, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.18, sub, ha='center', va='center',
                fontsize=7.5, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None):
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


# ---------------------------------------------------------------------------
# Panel 1: Velero architecture
# ---------------------------------------------------------------------------
def panel_arch(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Velero architecture: two data planes\n(API objects + PV file-level data)',
                 fontsize=11, fontweight='bold')

    # Kubernetes API / workload
    draw_box(ax, 1.8, 8.3, 3.0, 1.1, 'K8s API server', 'StatefulSet/Svc/PVC objects',
             face='#e8eef7', edge='#8899bb')

    # velero controller
    draw_box(ax, 1.8, 5.8, 3.0, 1.2, 'velero controller', 'backup/restore CRD\nwatch + export objects',
             face=C_CTRL, edge='#2d4a75')

    # node agents (DaemonSet)
    draw_box(ax, 1.8, 3.2, 3.4, 1.2, 'node agent (DaemonSet)', 'restic / kopia\nmount PVC, tar & upload files',
             face=C_AGENT, edge='#2e6b3e')

    # PV data source
    draw_box(ax, 1.8, 1.1, 3.4, 0.9, 'PV / PVC data', '/data in pods', face='#d9edf4', edge='#3a7a9a')

    # object storage
    draw_box(ax, 7.6, 4.5, 3.2, 2.6, 'Backup storage', 'S3 / MinIO / OSS\n\nobjects tarball (gz)\nvolume file backups (kopia/restic)\n+ metadata JSON',
             face=C_STORE, edge='#4e3a7a')

    # backup arrows
    arrow(ax, 3.3, 6.1, 6.0, 5.4, color=C_BACKUP, lw=2.0)
    ax.text(4.3, 6.15, 'backup: objects', fontsize=7.5, color='#967c1e', ha='center')
    arrow(ax, 3.55, 3.2, 6.0, 3.9, color=C_BACKUP, lw=2.0)
    ax.text(4.6, 2.95, 'backup: volume files', fontsize=7.5, color='#967c1e', ha='center')

    # restore arrows (both anchored at the Backup storage box left edge)
    arrow(ax, 6.0, 5.7, 2.6, 8.0, color=C_RESTORE, lw=2.0, cs='arc3,rad=-0.25')
    arrow(ax, 6.0, 3.8, 3.0, 2.6, color=C_RESTORE, lw=2.0, cs='arc3,rad=0.2')
    ax.text(6.4, 7.15, 'restore: recreate\nobjects (new ns)', fontsize=7.5,
            color=C_RESTORE, ha='left')
    ax.text(5.6, 1.75, 'restore: write files\nback into new PVCs', fontsize=7.5,
            color=C_RESTORE, ha='center')

    # notes
    draw_box(ax, 1.8, 6.95, 3.2, 0.55, 'hooks: pre/post backup', face='#fdf3d7', edge='#c9a227', fs=7.5)
    draw_box(ax, 7.6, 8.3, 4.4, 1.2,
             'Schedule backups',
             'velero schedule create daily-*\n--schedule="0 2 * * *" (cron)',
             face='#f2f2f2', edge='#999')
    arrow(ax, 7.6, 7.7, 7.6, 5.85, color='#aaa', lw=1.2)


# ---------------------------------------------------------------------------
# Panel 2: migration flow vs CSI snapshot
# ---------------------------------------------------------------------------
def panel_flow(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Cross-cluster migration (Velero)\nvs same-cluster CSI snapshot',
                 fontsize=11, fontweight='bold')

    # ---- migration flow (top) ----
    ax.text(0.4, 9.3, 'Migration with Velero:', fontsize=9, fontweight='bold',
            color=C_TEXT, va='center')

    draw_box(ax, 1.7, 7.6, 2.7, 1.35, 'Cluster A (source)', 'velero-demo ns\nStatefulSet + PVC',
             face='#e8eef7', edge='#8899bb')
    draw_box(ax, 5.0, 7.6, 2.4, 1.35, 'S3 / MinIO', 'backup tarball\n+ volume data',
             face=C_STORE, edge='#4e3a7a')
    draw_box(ax, 8.3, 7.6, 2.7, 1.35, 'Cluster B (target)', 'velero-demo-restored\nnew PVCs, data restored',
             face='#e6f2e6', edge='#2e6b3e')

    arrow(ax, 3.1, 7.6, 3.75, 7.6, color=C_BACKUP, lw=2.0)
    ax.text(3.45, 8.45, 'backup', fontsize=7.5, color='#967c1e', ha='center')
    arrow(ax, 6.25, 7.6, 6.9, 7.6, color=C_RESTORE, lw=2.0)
    ax.text(6.6, 8.45, 'restore', fontsize=7.5, color=C_RESTORE, ha='center')

    draw_box(ax, 5.0, 5.7, 6.8, 1.0,
             'restore flags',
             '--namespace-mappings a:b   --exclude-resources events   --selector app=web',
             face='#fdf3d7', edge='#c9a227')

    # ---- CSI snapshot (bottom) ----
    ax.text(0.4, 4.6, 'CSI snapshot (17_csi_snapshot):', fontsize=9, fontweight='bold',
            color=C_TEXT, va='center')

    draw_box(ax, 5.0, 2.9, 8.2, 1.7,
             'same storage system, same cluster',
             'VolumeSnapshot -> point-in-time snapshot\n'
             'restore = new PVC from snapshot (storage-level, fast)\n'
             'cannot cross clusters / storage vendors',
             face='#d9edf4', edge=C_CSI)

    # ---- comparison ----
    draw_box(ax, 5.0, 1.0, 8.6, 1.3,
             'choose:',
             'Velero: app-level portability, any storage, cross-cluster  |  '
             'CSI: fast same-cluster PITR\netcd backup: whole-cluster last resort, no per-app granularity',
             face='#f2f2f2', edge='#999')


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_arch(axes[0])
    panel_flow(axes[1])
    fig.suptitle('Velero: stateful app backup & migration',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
