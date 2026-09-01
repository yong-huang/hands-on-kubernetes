"""PV/PVC 可视化: 绑定链路与绑定条件 + PV 生命周期状态机(静态 vs 动态供给)"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'pv_pvc_arch.png')

# 配色 (seaborn 风格系列色)
C_POD = '#4c72b0'        # Pod: 蓝
C_PVC = '#55a868'        # PVC: 绿
C_PV = '#c44e52'         # PV: 红
C_STORAGE = '#8172b3'    # storage: 紫
C_BOUND = '#f4c542'      # bound state: 黄
C_STATIC = '#64b5cd'     # static provisioning
C_DYNAMIC = '#937860'    # dynamic provisioning
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333'):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.14, title, ha='center', va='center',
                fontsize=9.5, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.18, sub, ha='center', va='center',
                fontsize=7.5, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=9.5, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None):
    """Draw an arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


def state_chip(ax, x, y, text, color):
    """Draw a small rounded state chip (lifecycle state)."""
    box = FancyBboxPatch((x - 0.62, y - 0.32), 1.24, 0.64,
                         boxstyle='round,pad=0.02',
                         facecolor=color, edgecolor='#555',
                         linewidth=1.2, zorder=3)
    ax.add_patch(box)
    ax.text(x, y, text, ha='center', va='center',
            fontsize=8.5, fontweight='bold', color=C_TEXT, zorder=4)


# ---------------------------------------------------------------------------
# Panel 1: Pod -> PVC -> PV -> hostPath chain + binding conditions
# ---------------------------------------------------------------------------
def panel_binding(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Static binding: Pod -> PVC -> PV -> storage\n(PVC request must match PV supply)',
                 fontsize=11, fontweight='bold')

    # Pod
    draw_box(ax, 1.5, 8.4, 2.4, 1.15, 'Pod', 'busybox /data',
             face=C_POD, edge='#2d4a75')

    # PVC (user request)
    draw_box(ax, 5.0, 8.4, 2.7, 1.15, 'PVC (request)', '1Gi  RWO  sc=manual',
             face=C_PVC, edge='#2e6b3e')

    # PV (cluster resource)
    draw_box(ax, 8.5, 8.4, 2.7, 1.15, 'PV (supply)', '1Gi  RWO  hostPath',
             face=C_PV, edge='#7a2e30')

    arrow(ax, 2.7, 8.4, 3.65, 8.4, color=C_POD)
    arrow(ax, 6.35, 8.4, 7.15, 8.4, color=C_PVC)

    # binding conditions box between PVC and PV
    draw_box(ax, 6.75, 6.35, 6.7, 1.8,
             'Binding conditions (all must hold)',
             'capacity: PV >= PVC request (1Gi >= 1Gi)\n'
             'accessModes: PV modes superset of PVC (RWO ⊇ RWO)\n'
             'storageClassName: manual == manual',
             face='#e8eef7', edge='#8899bb')

    arrow(ax, 6.35, 7.85, 6.6, 7.3, color='#8899bb', lw=1.2, cs='arc3,rad=0.2')
    arrow(ax, 7.2, 7.3, 8.3, 7.85, color='#8899bb', lw=1.2, cs='arc3,rad=0.2')
    ax.text(5.0, 7.6, 'controller binds\n(claimRef)', fontsize=7.5,
            color='#555', ha='center', va='center', style='italic')

    # storage layer
    draw_box(ax, 8.5, 5.2, 2.7, 1.0, 'hostPath', '/data/pv-demo\n(kind node fs)',
             face=C_STORAGE, edge='#4e3a7a')
    arrow(ax, 8.5, 7.8, 8.5, 5.75, color=C_PV)

    # namespace boundary note
    draw_box(ax, 2.9, 4.2, 5.2, 1.5,
             'PV is cluster-scoped (no namespace)',
             'PVC is namespaced; Pod finds PVC\nonly in its own namespace',
             face='#f2f2f2', edge='#999', )
    arrow(ax, 4.2, 5.45, 3.8, 5.0, color='#bbb', lw=1.0, cs='arc3,rad=-0.25')

    # data persistence note
    draw_box(ax, 5.0, 1.7, 8.2, 1.5,
             'Data outlives the Pod',
             'delete Pod -> re-apply -> PVC re-mounts the same PV,\n'
             'files in /data survive (verify step in pv.sh)',
             face='#fdf3d7', edge='#c9a227')


# ---------------------------------------------------------------------------
# Panel 2: PV lifecycle states + static vs dynamic provisioning
# ---------------------------------------------------------------------------
def panel_lifecycle(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('PV lifecycle & reclaim policies\n(static vs dynamic provisioning)',
                 fontsize=11, fontweight='bold')

    # ---- lifecycle states (top half) ----
    ax.text(0.4, 9.3, 'PV lifecycle:', fontsize=9, fontweight='bold',
            color=C_TEXT, va='center')

    state_chip(ax, 1.6, 8.2, 'Available', '#cfe3f5')
    state_chip(ax, 4.0, 8.2, 'Bound', C_BOUND)
    state_chip(ax, 6.5, 8.2, 'Released', '#f5d0d0')

    arrow(ax, 2.25, 8.2, 3.35, 8.2, color='#555')
    ax.text(2.8, 8.6, 'PVC binds', fontsize=7, ha='center', color='#555')
    arrow(ax, 4.65, 8.2, 5.85, 8.2, color='#555')
    ax.text(5.25, 8.6, 'PVC deleted\n(Retain)', fontsize=7, ha='center', color='#555')

    # outcome boxes
    draw_box(ax, 8.9, 9.0, 2.0, 0.95, 'Retain', 'Released ->\nmanual clean & reuse',
             face='#e6f2e6', edge='#2e6b3e')
    draw_box(ax, 8.9, 7.4, 2.0, 0.95, 'Delete', 'PV + data\ngone',
             face='#f2dede', edge='#7a2e30')
    # Retain path: PVC deleted -> Released -> manual reuse
    arrow(ax, 7.15, 8.45, 7.85, 8.9, color='#2e6b3e')
    # Delete path: PVC deleted while reclaimPolicy=Delete -> PV removed directly from Bound
    arrow(ax, 4.9, 7.85, 7.85, 7.5, color='#7a2e30', cs='arc3,rad=-0.25')
    ax.text(5.9, 6.85, 'PVC deleted (Delete): PV deleted directly,\nnever enters Released',
            fontsize=7, ha='center', color='#7a2e30')

    # ---- static vs dynamic provisioning (bottom half) ----
    ax.text(0.4, 6.3, 'Provisioning:', fontsize=9, fontweight='bold',
            color=C_TEXT, va='center')

    # static
    draw_box(ax, 2.7, 4.6, 4.6, 2.5,
             'Static (this demo)',
             'admin pre-creates PV (hostPath/local)\n'
             'PVC binds an existing PV\n'
             'no StorageClass controller involved\n'
             'sc=manual is just a match label',
             face='#d9edf4', edge=C_STATIC)

    # dynamic
    draw_box(ax, 7.6, 4.6, 4.6, 2.5,
             'Dynamic (production default)',
             'StorageClass + CSI driver (e.g. EBS)\n'
             'PVC pending -> controller provisions PV\n'
             'reclaimPolicy Delete: PV removed with PVC\n'
             'empty sc in PVC = default StorageClass',
             face='#efe6df', edge=C_DYNAMIC)

    arrow(ax, 2.7, 3.3, 4.9, 3.3, color='#aaa', lw=1.0, style='<|-')
    ax.text(5.0, 3.3, 'both end up as: Pod mounts PVC -> PV', fontsize=7.5,
            va='center', color='#555')

    # accessModes reference
    draw_box(ax, 5.0, 1.7, 8.4, 1.5,
             'accessModes',
             'RWO ReadWriteOnce: single node (most block storage)\n'
             'ROX ReadOnlyMany: many pods read-only  |  RWX ReadWriteMany: NFS/shared fs',
             face='#fdf3d7', edge='#c9a227')


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_binding(axes[0])
    panel_lifecycle(axes[1])
    fig.suptitle('Kubernetes PersistentVolume / PersistentVolumeClaim',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
