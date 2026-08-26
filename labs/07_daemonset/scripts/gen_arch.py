"""DaemonSet 可视化: 每节点一个 Pod 的调度模型 (vs Deployment) + 日志采集流水线"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'daemonset_arch.png')

# 配色 (seaborn 风格系列色)
C_DS = '#4c72b0'       # DaemonSet: 蓝
C_DEPLOY = '#dd8452'   # Deployment: 橙
C_OK = '#55a868'       # ok / scheduled: 绿
C_BLOCK = '#c44e52'    # blocked / rejected: 红
C_NODE = '#e8eef7'     # node box face
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333',
             fs=9.5, sub_fs=7.5, title_color=None):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.16, title, ha='center', va='center',
                fontsize=fs, fontweight='bold',
                color=title_color or C_TEXT, zorder=4)
        ax.text(x, y - h * 0.2, sub, ha='center', va='center',
                fontsize=sub_fs, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=fs, fontweight='bold',
                color=title_color or C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None):
    """Draw an arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


# ---------------------------------------------------------------------------
# Panel 1: DaemonSet scheduling model (one pod per node) vs Deployment
# ---------------------------------------------------------------------------
def panel_model(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(-1, 10)
    ax.axis('off')
    ax.set_title('DaemonSet: exactly one pod per node\n(vs Deployment: N replicas on any nodes)',
                 fontsize=11, fontweight='bold')

    # ---------------- left: DaemonSet ----------------
    draw_box(ax, 2.4, 9.0, 4.4, 1.1, 'DaemonSet controller',
             'desired = number of nodes', face=C_DS, edge='#2d4a75')

    nodes = [
        (2.4, 6.9, 'node-1 (worker)', True, 'agent'),
        (2.4, 5.1, 'node-2 (worker)', True, 'agent'),
        (2.4, 3.3, 'node-3 (worker)', True, 'agent'),
        (2.4, 1.5, 'node-4 (control-plane)', True, 'agent'),
    ]
    for x, y, name, ok, label in nodes:
        # node box
        box = FancyBboxPatch((x - 2.2, y - 0.7), 4.4, 1.4,
                             boxstyle='round,pad=0.02',
                             facecolor=C_NODE, edgecolor='#8899bb',
                             linewidth=1.2, zorder=3)
        ax.add_patch(box)
        ax.text(x - 1.9, y, name, ha='left', va='center',
                fontsize=7.5, color=C_TEXT, zorder=4)
        # pod inside the node
        pod_face = '#bfe3b3' if ok else '#f2c4c4'
        pod_edge = C_OK if ok else C_BLOCK
        box = FancyBboxPatch((x + 0.5, y - 0.35), 1.5, 0.7,
                             boxstyle='round,pad=0.02',
                             facecolor=pod_face, edgecolor=pod_edge,
                             linewidth=1.3, zorder=4)
        ax.add_patch(box)
        ax.text(x + 1.25, y, label, ha='center', va='center',
                fontsize=7, fontweight='bold', color=C_TEXT, zorder=5)
        arrow(ax, x, 8.4, x, y + 0.75, color=C_DS, lw=1.0)

    # toleration note near control-plane node
    ax.text(5.0, 0.6, 'toleration needed:\n'
                      'node-role.kubernetes.io/control-plane:NoSchedule',
            fontsize=6.8, color=C_BLOCK, ha='center', va='top', style='italic')

    # ---------------- right: Deployment ----------------
    draw_box(ax, 7.6, 9.0, 4.4, 1.1, 'Deployment / ReplicaSet',
             'desired = replicas (3)', face=C_DEPLOY, edge='#9c5a2b')

    dep_nodes = [
        (7.0, 6.9, 'node-1', 2),      # 2 pods stacked here
        (7.0, 5.1, 'node-2', 1),
        (7.0, 3.3, 'node-3', 0),      # none here
        (7.0, 1.5, 'node-4 (cp)', 0, True),  # taint blocks
    ]
    for x, y, name, n, *blocked in dep_nodes:
        box = FancyBboxPatch((x - 1.0, y - 0.7), 3.2, 1.4,
                             boxstyle='round,pad=0.02',
                             facecolor=C_NODE, edgecolor='#8899bb',
                             linewidth=1.2, zorder=3)
        ax.add_patch(box)
        ax.text(x - 0.75, y, name, ha='left', va='center',
                fontsize=7, color=C_TEXT, zorder=4)
        # pod chips on the right side of the node
        for i in range(n):
            box = FancyBboxPatch((x + 0.6 + i * 0.6, y - 0.3), 0.55, 0.6,
                                 boxstyle='round,pad=0.02',
                                 facecolor='#f5cfa0', edgecolor=C_DEPLOY,
                                 linewidth=1.2, zorder=4)
            ax.add_patch(box)
        if blocked and blocked[0]:
            ax.text(x + 0.9, y, 'x taint', fontsize=7, color=C_BLOCK,
                    ha='center', va='center', zorder=5, fontweight='bold')
        elif n == 0:
            ax.text(x + 0.9, y, 'no pod', fontsize=7, color='#999',
                    ha='center', va='center', zorder=5, style='italic')
        arrow(ax, 7.6, 8.4, x, y + 0.75, color=C_DEPLOY, lw=1.0)

    # key difference note (below the Deployment side, no overlap with nodes)
    draw_box(ax, 7.9, -0.4, 4.2, 1.0, '',
             'DaemonSet: count driven by nodes\nDeployment: count driven by replicas',
             face='#fdf3d7', edge='#c9a227', sub_fs=7.2)


# ---------------------------------------------------------------------------
# Panel 2: log collection pipeline + gating (tolerations / nodeSelector)
# ---------------------------------------------------------------------------
def panel_pipeline(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Log collection pipeline & scheduling gates\n'
                 '(tolerations / nodeSelector / nodeAffinity)',
                 fontsize=11, fontweight='bold')

    # app pods -> node filesystem -> daemonset agent -> external store
    y_mid = 7.6
    draw_box(ax, 1.3, y_mid, 2.2, 1.5, 'app pods',
             'nginx, redis ...\nwrite stdout/stderr', face='#d4ecc9', edge=C_OK)
    draw_box(ax, 4.0, y_mid, 2.6, 1.5, 'node filesystem',
             '/var/log\n/var/lib/docker/containers', face=C_NODE, edge='#8899bb')
    draw_box(ax, 6.9, y_mid, 2.2, 1.5, 'DaemonSet agent',
             'fluent-bit\n(one per node)', face='#b8ccea', edge=C_DS)
    draw_box(ax, 9.2, y_mid, 1.5, 1.5, 'log store',
             'ES / Loki', face='#e6d7ef', edge='#7d5ba6')

    arrow(ax, 2.45, y_mid, 2.65, y_mid, color=C_OK, lw=1.8)
    ax.text(2.55, y_mid + 0.95, 'kubelet\nwrites', fontsize=6.5,
            ha='center', color='#555')
    arrow(ax, 5.35, y_mid, 5.75, y_mid, color=C_DS, lw=1.8)
    ax.text(5.55, y_mid + 0.95, 'hostPath\nmount', fontsize=6.5,
            ha='center', color='#555')
    arrow(ax, 8.05, y_mid, 8.4, y_mid, color='#7d5ba6', lw=1.8)
    ax.text(8.25, y_mid + 0.95, 'ship', fontsize=6.5,
            ha='center', color='#555')

    # hostPath note
    draw_box(ax, 4.0, 5.6, 4.0, 0.9, '',
             'hostPath: mount a directory of the NODE into the pod',
             face='#fdf3d7', edge='#c9a227', sub_fs=7.2)

    # -------- gates: scheduling filters drawn as a vertical flow --------
    gates = [
        (4.2, 'nodeSelector / nodeAffinity', 'keep only nodes with matching labels', C_DS),
        (2.8, 'taints & tolerations', 'control-plane taint rejected unless tolerated', C_BLOCK),
        (1.4, 'unschedulable / cordon', 'manual drain or failed node is skipped', C_DEPLOY),
    ]
    for y, title, sub, color in gates:
        draw_box(ax, 3.4, y, 5.8, 1.05, title, sub,
                 face='white', edge=color, fs=8.5, sub_fs=7)
    for y1 in [3.65, 2.25]:
        arrow(ax, 3.4, y1 + 0.1, 3.4, y1 - 0.35, color='#aaa', lw=1.2)
    arrow(ax, 3.8, 5.15, 3.6, 4.85, color='#aaa', lw=1.2)

    draw_box(ax, 8.3, 2.8, 2.4, 2.4, 'result',
             'one agent pod on\nevery eligible node\n(desired =\neligible nodes)',
             face='#d4ecc9', edge=C_OK, fs=9, sub_fs=7.2)
    arrow(ax, 6.35, 2.8, 7.05, 2.8, color=C_OK, lw=1.6)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(14.5, 7.0))
    panel_model(axes[0])
    panel_pipeline(axes[1])
    fig.suptitle('Kubernetes DaemonSet: One Pod Per Node & Log Collection Pipeline',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
