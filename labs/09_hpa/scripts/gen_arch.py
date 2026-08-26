"""HPA 可视化: 控制环 (metrics-server -> HPA -> Deployment -> Pods) + 负载时间线 (扩快缩慢)"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'hpa_arch.png')

# 配色 (seaborn 风格系列色)
C_HPA = '#4c72b0'      # HPA controller: 蓝
C_DEPLOY = '#55a868'   # Deployment: 绿
C_METRICS = '#dd8452'  # metrics-server: 橙
C_SCALE_DOWN = '#c44e52'  # scale-down zone: 红
C_POD = '#8cd98c'      # pod
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


# ---------------------------------------------------------------------------
# Panel 1: HPA control loop
# ---------------------------------------------------------------------------
def panel_loop(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('HPA control loop (reconcile every 15s)',
                 fontsize=11, fontweight='bold')

    # metrics pipeline (top)
    draw_box(ax, 1.9, 8.9, 3.0, 1.15, 'kubelet cAdvisor', 'per-pod usage',
             face='#f7e3d4', edge=C_METRICS)
    draw_box(ax, 6.0, 8.9, 3.2, 1.15, 'metrics-server',
             'Metrics API (cpu/memory)', face='#f7e3d4', edge=C_METRICS)
    arrow(ax, 3.45, 8.9, 4.35, 8.9, color=C_METRICS)
    ax.text(3.9, 9.25, 'scrape', fontsize=7, color=C_METRICS, ha='center')

    # HPA controller (middle) with the core formula
    draw_box(ax, 5.0, 5.9, 6.4, 1.9, 'HPA controller',
             'desired = ceil( currentReplicas x currentUtil / targetUtil )',
             face=C_HPA, edge='#2d4a75')
    arrow(ax, 6.0, 8.3, 5.5, 6.9, color=C_METRICS)
    ax.text(7.05, 7.55, 'read metrics', fontsize=7.5, color=C_METRICS)

    # Deployment (bottom-left)
    draw_box(ax, 2.6, 3.4, 3.4, 1.15, 'Deployment',
             'spec.replicas = desired', face=C_DEPLOY, edge='#3d7a4c')
    arrow(ax, 3.6, 5.15, 3.0, 4.0, color=C_DEPLOY)
    ax.text(3.6, 4.6, 'scale', fontsize=7.5, color=C_DEPLOY)

    # pods (bottom-right)
    for x in [6.2, 7.4, 8.6, 9.5]:
        box = FancyBboxPatch((x - 0.42, 3.15), 0.84, 0.5,
                             boxstyle='round,pad=0.02',
                             facecolor=C_POD, edgecolor='#333',
                             linewidth=1.2, zorder=3)
        ax.add_patch(box)
        label = 'x' if x == 9.5 else ''
        ax.text(x, 3.4, f'Pod{label}', ha='center', va='center',
                fontsize=7, color=C_TEXT, zorder=4)
    arrow(ax, 4.3, 3.4, 5.65, 3.4, color='#666')
    ax.text(5.0, 3.75, 'create/delete', fontsize=7.5, color='#555', ha='center')
    ax.text(8.0, 2.55, 'x = pod removed when scaling in', fontsize=7.5,
            color=C_SCALE_DOWN, ha='center', style='italic')

    # feedback loop (pods -> metrics)
    arrow(ax, 9.5, 3.8, 9.5, 8.3, color='#999', lw=1.2, style='-|>',
          cs='arc3,rad=0.35')
    ax.text(9.85, 6.0, 'new usage\n(feedback)', fontsize=7, color='#888',
            ha='center', rotation=90)

    # example note
    draw_box(ax, 5.0, 0.9, 8.6, 1.2,
             'example: 2 pods x 90% CPU, target 50%  ->  ceil(2 x 90/50) = 4 replicas',
             'util % = actual usage / resources.requests  (requests must be set!)',
             face='#fdf3d7', edge='#c9a227')


# ---------------------------------------------------------------------------
# Panel 2: load timeline - replicas vs CPU utilization (up fast, down slow)
# ---------------------------------------------------------------------------
def panel_timeline(ax):
    ax.set_xlim(0, 40)
    ax.set_ylim(0, 110)
    ax.set_title('Replica count vs CPU utilization over time\n(upscale fast, downscale slow: 300s stabilization window)',
                 fontsize=11, fontweight='bold')
    ax.set_xlabel('time (minutes)', fontsize=9)
    ax.set_ylabel('CPU utilization % (target=50) / replicas x10', fontsize=9)

    t = [0, 4, 4.5, 8, 8.5, 10, 10.5, 12, 12.5, 14, 14.5, 16, 16.5,
         18, 18.5, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40]

    # CPU utilization: idle ~15%, load arrives at t=4 (spikes to 95%), each scale
    # step brings it back toward 50; load removed at t=20 -> drops to 0
    cpu = [15, 15, 95, 70, 90, 60, 80, 55, 75, 55, 65, 55, 60, 55, 58, 50,
           5, 2, 2, 2, 2, 2, 2, 2, 2, 2]
    # replicas: step up quickly during load, then step down slowly after t=20
    # (+5min stabilization => first scale-down at t=25)
    reps = [1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 7,
            7, 7, 7, 7, 5, 5, 4, 4, 3, 3]

    ax.fill_between(t, cpu, color=C_METRICS, alpha=0.25, zorder=1)
    ax.plot(t, cpu, color=C_METRICS, lw=2, label='CPU utilization %')
    ax.plot(t, [r * 10 for r in reps], color=C_HPA, lw=2.2, drawstyle='steps-post',
            label='replicas (x10)')
    ax.axhline(50, color='#c9a227', lw=1.2, ls='--', label='target utilization (50%)')

    # annotations
    ax.annotate('load starts', xy=(4.3, 95), xytext=(1.2, 100),
                fontsize=8, color=C_SCALE_DOWN,
                arrowprops=dict(arrowstyle='->', color=C_SCALE_DOWN, lw=1.2))
    ax.annotate('load removed (t=20)', xy=(20.3, 5), xytext=(16.5, 30),
                fontsize=8, color=C_SCALE_DOWN,
                arrowprops=dict(arrowstyle='->', color=C_SCALE_DOWN, lw=1.2))
    # stabilization window shading: t=20..25 CPU already low but replicas stay 7
    ax.axvspan(20, 25, color=C_SCALE_DOWN, alpha=0.12, zorder=0)
    ax.annotate('stabilization window 300s\n(no scale-down yet)',
                xy=(22.5, 60), fontsize=8, color=C_SCALE_DOWN, ha='center')
    ax.annotate('scale-up: fast\n(+100% / 15s)', xy=(8.5, 80), xytext=(6.2, 45),
                fontsize=8, color=C_HPA,
                arrowprops=dict(arrowstyle='->', color=C_HPA, lw=1.2))
    ax.annotate('scale-down: slow\n(-25% / 15s)', xy=(31, 40), xytext=(32.5, 65),
                fontsize=8, color=C_HPA,
                arrowprops=dict(arrowstyle='->', color=C_HPA, lw=1.2))

    ax.legend(loc='upper left', fontsize=8, framealpha=0.9)
    ax.grid(alpha=0.25, lw=0.6)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(14, 6.6))
    panel_loop(axes[0])
    panel_timeline(axes[1])
    fig.suptitle('Kubernetes HPA: Control Loop & Scaling Behavior',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.94])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
