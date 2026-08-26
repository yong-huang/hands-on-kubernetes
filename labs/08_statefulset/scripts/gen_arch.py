"""StatefulSet 可视化: Deployment vs StatefulSet 对比 + 有序部署/缩容/滚动更新时序"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'statefulset_arch.png')

# 配色 (seaborn 风格系列色)
C_DEPLOY = '#4c72b0'    # Deployment / 对照组: 蓝
C_STS = '#55a868'       # StatefulSet: 绿
C_PVC = '#dd8452'       # PVC: 橙
C_DEAD = '#c44e52'      # deleted pod: 红
C_POD_OK = '#8cd98c'    # healthy pod
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333',
             fs=9.5, sub_fs=7.5):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.14, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.18, sub, ha='center', va='center',
                fontsize=sub_fs, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>'):
    """Draw an arrow between two points."""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), zorder=2,
                arrowprops=dict(arrowstyle=style, color=color, lw=lw,
                                shrinkA=2, shrinkB=2))


# ---------------------------------------------------------------------------
# Panel 1: Deployment vs StatefulSet — identity, storage, DNS
# ---------------------------------------------------------------------------
def panel_compare(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Deployment vs StatefulSet:\nrandom interchangeable pods vs stable identity',
                 fontsize=11, fontweight='bold')

    # ---- left: Deployment ----
    draw_box(ax, 2.5, 9.0, 3.6, 1.1, 'Deployment', 'stateless, shared-nothing',
             face=C_DEPLOY, edge='#2d4a75')
    random_names = ['web-7d9f-x2kp', 'web-7d9f-9mqzl', 'web-7d9f-c4t8v']
    for i, name in enumerate(random_names):
        x = 1.1 + i * 1.4
        box = FancyBboxPatch((x - 0.62, 6.9), 1.24, 1.0,
                             boxstyle='round,pad=0.02',
                             facecolor='#dfe6f1', edgecolor='#8899bb',
                             linewidth=1.2, zorder=3)
        ax.add_patch(box)
        ax.text(x, 7.55, 'Pod', ha='center', va='center',
                fontsize=8.5, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, 7.15, name, ha='center', va='center',
                fontsize=5.6, color='#555', zorder=4)
        arrow(ax, x, 8.42, x, 8.02, color='#8899bb', lw=1.0)
    ax.text(2.5, 6.35, 'random suffixes, recreated with NEW names\nno DNS name per pod (VIP load-balances)',
            fontsize=7, color=C_DEPLOY, ha='center', style='italic')

    # ---- right: StatefulSet ----
    draw_box(ax, 7.5, 9.0, 3.6, 1.1, 'StatefulSet', 'stateful, ordered identity',
             face=C_STS, edge='#2d6a45')
    for i in range(3):
        x = 6.1 + i * 1.4
        # dedicated PVC below each pod
        draw_box(ax, x, 5.35, 1.16, 0.75, f'data-web-{i}', '',
                 face='#fbe4d0', edge=C_PVC, fs=7, sub_fs=6)
        # pod box with stable name + DNS
        box = FancyBboxPatch((x - 0.62, 6.9), 1.24, 1.0,
                             boxstyle='round,pad=0.02',
                             facecolor=C_POD_OK, edgecolor='#2d6a45',
                             linewidth=1.2, zorder=3)
        ax.add_patch(box)
        ax.text(x, 7.55, f'web-{i}', ha='center', va='center',
                fontsize=8.5, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, 7.15, 'mysql', ha='center', va='center',
                fontsize=6, color='#444', zorder=4)
        arrow(ax, x, 8.42, x, 8.02, color='#2d6a45', lw=1.0)
        arrow(ax, x, 6.85, x, 5.78, color=C_PVC, lw=1.0)
    ax.text(7.5, 4.55, 'stable names web-0/1/2 + dedicated PVC each\nDNS: web-0.mysql-h.ns.svc.cluster.local',
            fontsize=7, color='#2d6a45', ha='center', style='italic')

    # separator + bottom note
    ax.plot([5.0, 5.0], [3.4, 9.6], color='#bbb', lw=1.0, linestyle=':')
    draw_box(ax, 5, 1.9, 9.0, 1.5,
             'Deployment: any pod serves any request (peers)',
             'StatefulSet: pod identity matters — clients address web-0 (primary) by name',
             face='#e8f2ea', edge='#2d6a45', fs=8.5)


# ---------------------------------------------------------------------------
# Panel 2: ordered deploy / scale / delete + rolling update
# ---------------------------------------------------------------------------
def panel_order(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Ordered lifecycle (OrderedReady)\n+ rolling update from the highest ordinal',
                 fontsize=11, fontweight='bold')

    def pod_chip(x, y, label, color, edge, dead=False):
        box = FancyBboxPatch((x - 0.42, y - 0.32), 0.84, 0.64,
                             boxstyle='round,pad=0.02',
                             facecolor=color, edgecolor=edge, linewidth=1.2,
                             zorder=3, linestyle='--' if dead else '-')
        ax.add_patch(box)
        ax.text(x, y, label, ha='center', va='center',
                fontsize=7, color=C_TEXT, zorder=4)

    # ---- deploy: 0 -> 1 -> 2 ----
    ax.text(0.4, 8.9, 'deploy', fontsize=9, fontweight='bold', color=C_STS,
            va='center')
    rows = [('t0', [], 'empty'),
            ('t1', [('0', 1)], 'web-0 created, must be Ready first'),
            ('t2', [('0', 1), ('1', 1)], 'then web-1 created'),
            ('t3', [('0', 1), ('1', 1), ('2', 1)], 'finally web-2')]
    y = 8.9
    for name, pods, desc in rows:
        y -= 0.95
        ax.text(0.45, y, name, fontsize=8, color=C_TEXT, va='center')
        x = 1.35
        for ordinal, _ in pods:
            pod_chip(x, y, f'web-{ordinal}', C_POD_OK, '#2d6a45')
            x += 1.0
        ax.text(x + 0.1, y, desc, fontsize=7, va='center', color='#555')
    arrow(ax, 0.95, 8.55, 0.95, 6.55, color=C_STS, lw=1.2)

    # ---- delete: 2 -> 1 -> 0 (reverse order) ----
    ax.text(0.4, 5.15, 'delete', fontsize=9, fontweight='bold', color=C_DEAD,
            va='center')
    rows = [('t0', [('0', 1), ('1', 1), ('2', 1)], 'scale down: highest ordinal first'),
            ('t1', [('0', 1), ('1', 1), ('2', 0)], 'web-2 terminated before web-1'),
            ('t2', [('0', 1), ('1', 0), ('2', 0)], 'then web-1'),
            ('t3', [], 'finally web-0 (PVCs data-web-* are kept!)')]
    y = 5.15
    for name, pods, desc in rows:
        y -= 0.95
        ax.text(0.45, y, name, fontsize=8, color=C_TEXT, va='center')
        x = 1.35
        for ordinal, alive in pods:
            pod_chip(x, y, f'web-{ordinal}',
                     '#f5d0d0' if not alive else C_POD_OK,
                     C_DEAD if not alive else '#2d6a45',
                     dead=not alive)
            x += 1.0
        ax.text(x + 0.1, y, desc, fontsize=7, va='center', color='#555')
    arrow(ax, 0.95, 4.8, 0.95, 2.6, color=C_DEAD, lw=1.2)

    # ---- rolling update note ----
    draw_box(ax, 5, 1.1, 9.2, 1.55,
             'Rolling update: web-2 -> web-1 -> web-0 (reverse ordinal order)',
             'partition=N canaries: only ordinals >= N get the new template',
             face='#fdf3d7', edge='#c9a227', fs=8.5)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_compare(axes[0])
    panel_order(axes[1])
    fig.suptitle('Kubernetes StatefulSet: Stable Identity & Ordered Lifecycle',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
