"""Deployment 可视化: Deployment->ReplicaSet->Pod 层级 + 滚动更新过程 (maxSurge/maxUnavailable)"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'deploy_arch.png')

# 配色 (seaborn 风格系列色)
C_DEPLOY = '#4c72b0'   # Deployment: 蓝
C_RS_OLD = '#c44e52'   # old ReplicaSet: 红
C_RS_NEW = '#55a868'   # new ReplicaSet: 绿
C_POD_OK = '#8cd98c'   # healthy pod
C_POD_DEAD = '#e8a0a0' # terminated pod
C_POD_SURGE = '#f4c542'  # surge pod (over desired count)
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


def draw_pod(ax, x, y, state='ok', label='Pod'):
    """Draw a small pod box; state in {'ok','dead','surge','new'}."""
    colors = {'ok': C_POD_OK, 'dead': C_POD_DEAD,
              'surge': C_POD_SURGE, 'new': C_POD_OK}
    edge = '#999' if state == 'dead' else '#333'
    box = FancyBboxPatch((x - 0.42, y - 0.25), 0.84, 0.5,
                         boxstyle='round,pad=0.02',
                         facecolor=colors[state], edgecolor=edge,
                         linewidth=1.2, zorder=3,
                         linestyle='--' if state == 'dead' else '-')
    ax.add_patch(box)
    txt = {'dead': 'x', 'surge': '+', }.get(state, '')
    ax.text(x, y, f'{label}{txt}', ha='center', va='center',
            fontsize=7, color=C_TEXT, zorder=4)


# ---------------------------------------------------------------------------
# Panel 1: Deployment -> ReplicaSet -> Pods hierarchy during a rolling update
# ---------------------------------------------------------------------------
def panel_hierarchy(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Deployment owns ReplicaSets, ReplicaSets own Pods\n(during a rolling update)',
                 fontsize=11, fontweight='bold')

    # Deployment node
    draw_box(ax, 5, 8.8, 3.4, 1.3, 'Deployment', 'replicas=3  nginx',
             face=C_DEPLOY, edge='#2d4a75')

    # Two ReplicaSets: old (scaling down) and new (scaling up)
    draw_box(ax, 2.6, 6.0, 3.2, 1.2, 'ReplicaSet (old)',
             'nginx:1.25  desired=0', face='#f5d0d0', edge=C_RS_OLD)
    draw_box(ax, 7.4, 6.0, 3.2, 1.2, 'ReplicaSet (new)',
             'nginx:1.26  desired=3', face='#d4ecc9', edge=C_RS_NEW)

    arrow(ax, 4.2, 8.15, 2.9, 6.65, color=C_RS_OLD)
    arrow(ax, 5.8, 8.15, 7.1, 6.65, color=C_RS_NEW)
    ax.text(3.0, 7.5, 'scale down', fontsize=7.5, color=C_RS_OLD, rotation=18)
    ax.text(6.6, 7.5, 'scale up', fontsize=7.5, color=C_RS_NEW, rotation=-18)

    # Old RS pods: all terminated
    for i, x in enumerate([1.4, 2.6, 3.8]):
        draw_pod(ax, x, 4.4, state='dead')
        arrow(ax, x, 5.4, x, 4.75, color='#bbb', lw=1.0)
    ax.text(2.6, 3.5, 'old pods terminated', fontsize=7.5,
            color=C_RS_OLD, ha='center', style='italic')

    # New RS pods: 3 healthy + 1 surge during transition
    for x in [6.2, 7.4, 8.6]:
        draw_pod(ax, x, 4.4, state='ok')
        arrow(ax, x, 5.4, x, 4.75, color=C_RS_NEW, lw=1.0)
    draw_pod(ax, 9.5, 4.4, state='surge')
    ax.text(7.5, 3.5, 'new pods Ready (+1 surge during update)',
            fontsize=7.5, color=C_RS_NEW, ha='center', style='italic')

    # Controller loop note
    draw_box(ax, 5, 1.7, 7.6, 1.3,
             'Deployment controller: create new RS, scale both RSs step by step',
             'Pod template hash label keeps each RS\'s pods distinct',
             face='#e8eef7', edge='#8899bb')


# ---------------------------------------------------------------------------
# Panel 2: rolling update timeline with maxSurge / maxUnavailable
# ---------------------------------------------------------------------------
def panel_rolling(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Rolling update step by step\n(replicas=3, maxSurge=1, maxUnavailable=0)',
                 fontsize=11, fontweight='bold')

    steps = [
        ('t0', 'v1 v1 v1', 'steady state: 3 old pods, total=3'),
        ('t1', 'v2 v1 v1 v1', 'surge: +1 new pod (4 total, 0 unavailable)'),
        ('t2', 'v2 v1 v1', 'one v1 killed after v2 Ready (3 total)'),
        ('t3', 'v2 v2 v1 v1', 'surge again: +1 new pod (4 total)'),
        ('t4', 'v2 v2 v2', 'done: rollout complete, old RS desired=0'),
    ]

    y = 8.3
    for name, pods, desc in steps:
        ax.text(0.5, y, name, fontsize=9, fontweight='bold',
                color=C_TEXT, va='center')
        x = 1.6
        for p in pods.split():
            v2 = p == 'v2'
            box = FancyBboxPatch((x - 0.38, y - 0.3), 0.76, 0.6,
                                 boxstyle='round,pad=0.02',
                                 facecolor=C_POD_OK if v2 else '#d9d9d9',
                                 edgecolor=C_RS_NEW if v2 else '#888',
                                 linewidth=1.3, zorder=3)
            ax.add_patch(box)
            ax.text(x, y, p, ha='center', va='center',
                    fontsize=7.5, zorder=4, color=C_TEXT)
            x += 0.95
        ax.text(x + 0.15, y, desc, fontsize=7.5, va='center', color='#555')
        y -= 1.55

    for y1 in [7.65, 4.55, 3.0]:
        arrow(ax, 1.0, y1 + 0.15, 1.0, y1 - 0.35, color='#aaa', lw=1.0)

    draw_box(ax, 5, 1.0, 7.4, 1.35,
             'maxSurge: max extra pods above replicas (speeds update up)',
             'maxUnavailable: max pods below replicas (speeds update up, costs capacity)',
             face='#fdf3d7', edge='#c9a227')


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_hierarchy(axes[0])
    panel_rolling(axes[1])
    fig.suptitle('Kubernetes Deployment: Ownership Hierarchy & Rolling Update',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
