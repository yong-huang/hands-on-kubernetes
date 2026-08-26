"""Affinity & scheduling 可视化: 四种调度工具地图 + topologySpreadConstraints 打散原理"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'affinity_arch.png')

# 配色 (seaborn 风格系列色)
C_BLUE = '#4c72b0'    # nodeSelector / node side
C_GREEN = '#55a868'   # podAffinity (co-locate)
C_ORANGE = '#dd8452'  # podAntiAffinity (spread)
C_RED = '#c44e52'     # violations / Pending
C_POD_OK = '#8cd98c'
C_POD_NEW = '#f4c542'
C_NODE_BG = '#e8eef7'
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333',
             fs=9.5, sub_fs=7.0):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.16, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.20, sub, ha='center', va='center',
                fontsize=sub_fs, color='#555', zorder=4, wrap=True)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None):
    """Draw an arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


def draw_pod(ax, x, y, face=C_POD_OK, label='web', fs=6.5, edge='#333'):
    """Draw a small pod box."""
    box = FancyBboxPatch((x - 0.40, y - 0.24), 0.80, 0.48,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.0, zorder=4)
    ax.add_patch(box)
    ax.text(x, y, label, ha='center', va='center',
            fontsize=fs, color=C_TEXT, zorder=5)


# ---------------------------------------------------------------------------
# Panel 1: four scheduling tools map
# ---------------------------------------------------------------------------
def panel_tools(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Four scheduling tools: from node picking to pod spreading',
                 fontsize=11, fontweight='bold')

    # --- nodeSelector (top-left) ---
    draw_box(ax, 2.5, 8.4, 4.4, 2.0, 'nodeSelector',
             'simplest: pin to nodes with a label',
             face='#dfe7f5', edge=C_BLUE)
    ax.text(0.6, 6.95, 'nodeSelector:\n  disktype: ssd', fontsize=6.5,
            family='monospace', color='#445', va='top')

    # --- nodeAffinity (bottom-left) ---
    draw_box(ax, 2.5, 5.4, 4.4, 2.0, 'nodeAffinity',
             'match node labels with logic:\nrequired (hard) / preferred (soft + weight)',
             face='#dfe7f5', edge=C_BLUE)
    ax.text(0.6, 3.7, 'required: disktype In [ssd]\npreferred: zone=east, weight 80',
            fontsize=6.5, family='monospace', color='#445', va='top')

    # --- podAffinity (top-right) ---
    draw_box(ax, 7.5, 8.4, 4.4, 2.0, 'podAffinity',
             'co-locate with matching pods\n(same node / same zone)',
             face='#dcefe0', edge=C_GREEN)
    ax.text(5.6, 6.95, 'same zone as:\n  app=cache', fontsize=6.5,
            family='monospace', color='#355', va='top')

    # --- podAntiAffinity (bottom-right) ---
    draw_box(ax, 7.5, 5.4, 4.4, 2.0, 'podAntiAffinity',
             'spread away from matching pods\n(avoid same topology domain)',
             face='#f8e3d5', edge=C_ORANGE)
    ax.text(5.6, 3.7, 'NOT same node as:\n  app=web', fontsize=6.5,
            family='monospace', color='#742', va='top')

    # --- node vs pod dimension arrows ---
    arrow(ax, 4.75, 8.4, 5.25, 8.4, color='#999')
    arrow(ax, 4.75, 5.4, 5.25, 5.4, color='#999')
    ax.text(5.0, 9.0, 'pick node\nby attrs', fontsize=6.5, ha='center',
            color='#777')
    ax.text(5.0, 4.5, 'depends on\nother pods', fontsize=6.5, ha='center',
            color='#777')

    # --- summary strip ---
    draw_box(ax, 5, 1.6, 9.0, 1.5,
             'nodeSelector ⊂ nodeAffinity   |   podAffinity / podAntiAffinity',
             'required... = hard rule (Pending if unsatisfiable)   '
             'preferred... = soft score (weight 1-100)',
             face='#fdf3d7', edge='#c9a227', fs=8.5)


# ---------------------------------------------------------------------------
# Panel 2: topologySpreadConstraints maxSkew=1
# ---------------------------------------------------------------------------
def panel_spread(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('topologySpreadConstraints: maxSkew=1 by hostname\n(whenUnsatisfiable: DoNotSchedule)',
                 fontsize=11, fontweight='bold')

    node_w, node_h = 2.8, 2.3
    node_y = 7.4

    # --- Row A: balanced 2/1/1 (allowed) ---
    ax.text(0.3, 9.5, 'Balanced 2/1/1 — OK (skew = 2-1 = 1 <= maxSkew)',
            fontsize=8, color=C_GREEN, fontweight='bold', va='center')
    counts_ok = [2, 1, 1]
    for i, cnt in enumerate(counts_ok):
        x = 0.7 + i * 3.1
        box = FancyBboxPatch((x, node_y - node_h / 2), node_w, node_h,
                             boxstyle='round,pad=0.02',
                             facecolor=C_NODE_BG, edgecolor='#8899bb',
                             linewidth=1.3, zorder=2)
        ax.add_patch(box)
        ax.text(x + node_w / 2, node_y + node_h / 2 - 0.32,
                f'node-{i + 1}', fontsize=8, fontweight='bold',
                ha='center', color='#445', zorder=3)
        for j in range(cnt):
            draw_pod(ax, x + 0.75 + j * 1.3, node_y - 0.55)
        ax.text(x + node_w / 2, node_y - node_h / 2 + 0.3,
                f'{cnt} pod(s)', fontsize=6.5, ha='center', color='#666')

    # --- Row B: skewed 3/1/0 (violates) ---
    y2 = 3.9
    ax.text(0.3, 5.35, 'Skewed 3/1/0 — rejected (skew = 3-0 = 3 > maxSkew)',
            fontsize=8, color=C_RED, fontweight='bold', va='center')
    counts_bad = [3, 1, 0]
    for i, cnt in enumerate(counts_bad):
        x = 0.7 + i * 3.1
        box = FancyBboxPatch((x, y2 - node_h / 2), node_w, node_h,
                             boxstyle='round,pad=0.02',
                             facecolor=C_NODE_BG, edgecolor='#8899bb',
                             linewidth=1.3, zorder=2)
        ax.add_patch(box)
        ax.text(x + node_w / 2, y2 + node_h / 2 - 0.32,
                f'node-{i + 1}', fontsize=8, fontweight='bold',
                ha='center', color='#445', zorder=3)
        for j in range(cnt):
            px = x + 0.55 + j * 0.95
            draw_pod(ax, px, y2 - 0.5, face='#e8a0a0', edge='#999')
        ax.text(x + node_w / 2, y2 - node_h / 2 + 0.3,
                f'{cnt} pod(s)', fontsize=6.5, ha='center', color='#666')
    # new pod wants to land on node-1 -> violation mark
    # (画在 node-1 下方, 避免与第 3 个红色 Pod 重叠)
    draw_pod(ax, 1.7, 2.25, face=C_POD_NEW, label='new', edge=C_RED)
    ax.text(3.1, 2.25, 'new pod cannot\ngo to node-1', fontsize=6.5,
            ha='left', va='center', color=C_RED)

    # --- Decision flow strip ---
    draw_box(ax, 5, 0.9, 9.2, 1.3,
             'Scheduling decision: count pods per topology domain -> '
             'min domain 0, max domain 2',
             'place where skew stays <= 1 (node-3); '
             'if impossible -> Pending (FailedScheduling)',
             face='#fdf3d7', edge='#c9a227', fs=7.5)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_tools(axes[0])
    panel_spread(axes[1])
    fig.suptitle('Kubernetes Affinity & Topology Spread Scheduling',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
