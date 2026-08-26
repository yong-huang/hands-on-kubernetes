"""StorageClass 可视化: 静态 vs 动态供给流程 + volumeBindingMode 与 CSI 驱动示例"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'storageclass_arch.png')

# 配色 (seaborn 风格系列色)
C_POD = '#4c72b0'        # Pod: 蓝
C_PVC = '#55a868'        # PVC: 绿
C_SC = '#55A868'        # StorageClass: 绿 (与 PVC 同族)
C_PV = '#c44e52'         # PV: 红
C_STORAGE = '#8172b3'    # storage: 紫
C_STATIC = '#64b5cd'     # static provisioning
C_DYNAMIC = '#DD8452'    # dynamic provisioning
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333',
             title_size=9.5, sub_size=7.5):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.14, title, ha='center', va='center',
                fontsize=title_size, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.18, sub, ha='center', va='center',
                fontsize=sub_size, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=title_size, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None):
    """Draw an arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


# ---------------------------------------------------------------------------
# Panel 1: static (project 15) vs dynamic (project 16) provisioning flow
# ---------------------------------------------------------------------------
def panel_flow(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Provisioning flow: static (15) vs dynamic (16)\n'
                 'no manual PV creation in dynamic mode',
                 fontsize=11, fontweight='bold')

    # ---- static flow (top) ----
    ax.text(0.3, 9.5, 'Static provisioning (15_pv_pvc):',
            fontsize=9.5, fontweight='bold', color=C_STATIC, va='center')

    draw_box(ax, 1.3, 8.0, 2.0, 1.05, 'admin', 'kubectl create PV\n(by hand)',
             face='#d9edf4', edge=C_STATIC)
    draw_box(ax, 4.0, 8.0, 1.9, 1.05, 'PV', 'pre-created\nhostPath 1Gi',
             face=C_PV, edge='#7a2e30')
    draw_box(ax, 6.6, 8.0, 1.9, 1.05, 'PVC', 'request 1Gi\nsc=manual',
             face=C_PVC, edge='#2e6b3e')
    draw_box(ax, 9.1, 8.0, 1.6, 1.05, 'Pod', 'mount', face=C_POD, edge='#2d4a75')
    arrow(ax, 2.3, 8.0, 3.05, 8.0, color=C_STATIC)
    arrow(ax, 4.95, 8.0, 5.65, 8.0, color='#666', style='<|-|>')  # bind
    arrow(ax, 7.55, 8.0, 8.3, 8.0, color=C_POD)
    ax.text(5.3, 8.75, 'controller binds', fontsize=6.8, ha='center', color='#555')

    # ---- dynamic flow (middle) ----
    ax.text(0.3, 6.7, 'Dynamic provisioning (16_storageclass):',
            fontsize=9.5, fontweight='bold', color=C_DYNAMIC, va='center')

    draw_box(ax, 1.3, 5.1, 2.0, 1.05, 'StorageClass', 'provisioner +\nparameters',
             face='#e8eef7', edge='#4c72b0')
    draw_box(ax, 4.0, 5.1, 1.9, 1.05, 'PVC', 'request 500Mi\nsc=fast-local',
             face=C_PVC, edge='#2e6b3e')
    draw_box(ax, 6.6, 5.1, 1.9, 1.05, 'PV', 'auto-created\nby provisioner',
             face=C_PV, edge='#7a2e30')
    draw_box(ax, 9.1, 5.1, 1.6, 1.05, 'Pod', 'mount', face=C_POD, edge='#2d4a75')
    # PVC -> SC lookup, SC -> provisioner -> PV, PVC-PV bind
    arrow(ax, 3.05, 5.1, 2.3, 5.1, color='#4c72b0', style='<|-')
    draw_box(ax, 4.0, 3.6, 3.6, 0.85,
             'provisioner / CSI plugin', 'rancher local-path | EBS CSI | PD CSI',
             face='#efe6df', edge=C_DYNAMIC, title_size=8.5)
    arrow(ax, 3.9, 4.55, 4.0, 4.05, color=C_DYNAMIC)
    arrow(ax, 5.6, 4.05, 6.5, 4.55, color=C_DYNAMIC, cs='arc3,rad=-0.2')
    arrow(ax, 4.95, 5.1, 5.65, 5.1, color='#666', style='<|-|>')
    arrow(ax, 7.55, 5.1, 8.3, 5.1, color=C_POD)

    # ---- key differences ----
    draw_box(ax, 5.0, 1.9, 9.0, 1.9,
             'Key differences',
             'static: PV first, admin sizes it, binding "rounds up" (500Mi -> 1Gi PV)\n'
             'dynamic: PVC first, PV sized exactly to request, created on demand\n'
             'dynamic reclaimPolicy=Delete: PV (and backend volume) removed with PVC',
             face='#fdf3d7', edge='#c9a227')


# ---------------------------------------------------------------------------
# Panel 2: volumeBindingMode + cloud CSI examples table
# ---------------------------------------------------------------------------
def panel_mode(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('volumeBindingMode & cloud CSI drivers\n'
                 'when is the volume actually created?',
                 fontsize=11, fontweight='bold')

    # ---- Immediate ----
    draw_box(ax, 2.7, 8.1, 4.9, 2.1,
             'Immediate',
             'PVC created -> volume provisioned at once\n'
             'pod may be scheduled to another zone ->\n'
             'volume unreachable, pod stuck ContainerCreating',
             face='#d9edf4', edge=C_STATIC)

    # ---- WaitForFirstConsumer ----
    draw_box(ax, 7.6, 8.1, 4.9, 2.1,
             'WaitForFirstConsumer (recommended)',
             'PVC stays Pending until first pod is scheduled\n'
             'scheduler picks node -> zone; volume created there\n'
             'topology always correct; PVC pending is normal here',
             face='#efe6df', edge=C_DYNAMIC)

    # timeline chips for WFFC
    chips = [('PVC\nPending', '#f5d0d0'), ('Pod\nscheduled', '#cfe3f5'),
             ('provision\nPV', '#f4c542'), ('PVC\nBound', '#cfe3f5'),
             ('Pod\nRunning', '#e6f2e6')]
    xs = [1.0, 3.0, 5.0, 7.0, 9.0]
    for (label, color), x in zip(chips, xs):
        draw_box(ax, x, 5.6, 1.8, 1.0, label, '', face=color, edge='#555',
                 title_size=8)
    for i in range(4):
        arrow(ax, xs[i] + 0.95, 5.6, xs[i + 1] - 0.95, 5.6, color='#888', lw=1.3)
    ax.text(5.0, 4.55, 'WaitForFirstConsumer timeline (demo in sc.sh deploy)',
            fontsize=8, ha='center', color='#555', style='italic')

    # ---- cloud CSI examples table ----
    rows = [
        ('provisioner (CSI driver)', 'typical parameters', 'topology'),
        ('ebs.csi.aws.com', 'type: gp3, iops, fsType: ext4', 'AWS availability zone'),
        ('pd.csi.storage.gke.io', 'type: pd-balanced / pd-ssd', 'GCP zone'),
        ('disk.csi.azure.com', 'skuName: Premium_LRS', 'Azure zone'),
        ('rancher.io/local-path (kind)', '(none; node local dir)', 'specific node'),
    ]
    y = 3.4
    for i, (c1, c2, c3) in enumerate(rows):
        face = '#e8eef7' if i == 0 else 'white'
        weight = 'bold' if i == 0 else 'normal'
        row_h = 0.62
        for x, w, text in ((2.4, 3.6, c1), (5.6, 3.4, c2), (8.3, 3.0, c3)):
            box = FancyBboxPatch((x - w / 2, y - row_h / 2), w, row_h,
                                 boxstyle='round,pad=0.01',
                                 facecolor=face, edgecolor='#999',
                                 linewidth=1.0, zorder=3)
            ax.add_patch(box)
            ax.text(x, y, text, ha='center', va='center', fontsize=7.2,
                    fontweight=weight, color=C_TEXT, zorder=4)
        y -= row_h + 0.08

    draw_box(ax, 5.0, 0.7, 9.2, 0.9,
             'default StorageClass: annotation storageclass.kubernetes.io/is-default-class=true',
             '', face='#fdf3d7', edge='#c9a227', title_size=7.8)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_flow(axes[0])
    panel_mode(axes[1])
    fig.suptitle('Kubernetes StorageClass: dynamic provisioning',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
