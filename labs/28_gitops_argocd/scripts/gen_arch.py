"""GitOps 可视化: GitOps 闭环 (Git -> ArgoCD -> Cluster, selfHeal 纠偏) + Pull vs Push CD 对比 + app-of-apps"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'gitops_arch.png')

# 配色 (seaborn 风格系列色)
C_BLUE = '#4c72b0'    # Git / desired state: 蓝
C_GREEN = '#55a868'   # Cluster / actual state: 绿
C_ORANGE = '#dd8452'  # ArgoCD / drift: 橙
C_RED = '#c44e52'     # manual change / push CD: 红
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333',
             title_fs=9.5, sub_fs=7.5):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.16, title, ha='center', va='center',
                fontsize=title_fs, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.2, sub, ha='center', va='center',
                fontsize=sub_fs, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=title_fs, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None,
          ls='-'):
    """Draw an arrow between two points, optionally curved / dashed."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2,
                 linestyle=ls)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


def label(ax, x, y, text, color='#555', fs=7.5, ha='center', style='normal',
          bold=False):
    ax.text(x, y, text, fontsize=fs, color=color, ha=ha, style=style,
            fontweight='bold' if bold else 'normal', zorder=5)


# ---------------------------------------------------------------------------
# Panel 1: the GitOps reconciliation loop
# ---------------------------------------------------------------------------
def panel_loop(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('GitOps loop: Git is the single source of truth',
                 fontsize=11, fontweight='bold')

    # Developer
    draw_box(ax, 5, 9.0, 3.6, 1.2, 'Developer', 'git commit / git revert',
             face='#e8eef7', edge=C_BLUE)
    arrow(ax, 3.7, 8.6, 2.35, 7.25, color=C_BLUE)
    label(ax, 3.0, 8.05, 'push', color=C_BLUE, fs=7.5, ha='right')

    # Git repo (desired state)
    draw_box(ax, 1.7, 6.4, 2.9, 1.6, 'Git Repo', 'desired state\n(YAML manifests)',
             face=C_BLUE, edge='#2d4a75')
    # ArgoCD in the middle
    draw_box(ax, 5, 6.4, 2.2, 1.6, 'ArgoCD', 'watch + diff\n+ sync',
             face=C_ORANGE, edge='#a05a2c')
    # Cluster (actual state)
    draw_box(ax, 8.3, 6.4, 3.0, 1.6, 'Cluster', 'actual state\n(Deployments, Pods...)',
             face=C_GREEN, edge='#2f6b3c')

    # ArgoCD polls Git for changes
    arrow(ax, 3.25, 6.9, 3.8, 6.9, color=C_ORANGE)
    label(ax, 3.55, 7.45, 'poll ~3 min', color=C_ORANGE, fs=7)

    # ArgoCD applies to the cluster
    arrow(ax, 6.2, 6.9, 6.75, 6.9, color=C_GREEN)
    label(ax, 6.5, 7.45, 'apply', color=C_GREEN, fs=7)

    # observe actual state (feedback): compare live state vs Git
    arrow(ax, 6.7, 5.45, 3.3, 5.45, color='#888', ls='--', style='<|-|>')
    label(ax, 2.75, 4.95, 'compare live state vs Git', color='#666',
          fs=7.5, ha='left')

    # Drift: manual kubectl change gets reverted (selfHeal)
    draw_box(ax, 5, 3.6, 4.4, 1.15, 'kubectl scale --replicas=5',
             'manual change = drift', face='#f5d0d0', edge=C_RED)
    arrow(ax, 7.3, 4.2, 8.0, 5.6, color=C_RED, cs='arc3,rad=-0.25')
    label(ax, 8.75, 4.6, 'someone edits\nthe cluster', color=C_RED, fs=7)

    arrow(ax, 5, 4.2, 5, 5.15, color=C_ORANGE, ls='--')
    label(ax, 5.2, 4.75, 'selfHeal reverts it back to Git', color=C_ORANGE,
          fs=7.5, ha='left')

    # Bottom note
    draw_box(ax, 5, 1.4, 8.4, 1.3,
             'Declarative + versioned + auto-remediating',
             'rollback = git revert   |   audit = git log   |   prune = delete in Git',
             face='#fdf3d7', edge='#c9a227')


# ---------------------------------------------------------------------------
# Panel 2: Pull (GitOps) vs Push (traditional CI/CD) + app-of-apps
# ---------------------------------------------------------------------------
def panel_pull_push(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Pull vs Push delivery, and the app-of-apps pattern',
                 fontsize=11, fontweight='bold')

    # ---- Push model (left half) ----
    draw_box(ax, 2.5, 8.3, 4.0, 1.15, 'Push: traditional CI/CD',
             'CI holds cluster credentials', face='#f5d0d0', edge=C_RED)
    for i, (title, sub) in enumerate([
            ('CI', 'build + test'), ('kubectl', 'from outside'), ('Cluster', '')]):
        y = 6.6 - i * 1.5
        face = C_GREEN if i == 2 else '#eeeeee'
        draw_box(ax, 2.5, y, 2.6, 1.05, title, sub, face=face,
                 edge='#2f6b3c' if i == 2 else '#999')
        if i > 0:
            arrow(ax, 2.5, y + 0.95, 2.5, y + 0.55, color=C_RED)
    label(ax, 2.5, 1.6, 'creds leak risk, drift never detected',
          color=C_RED, fs=7.5)

    # ---- Pull model (right half) ----
    draw_box(ax, 7.5, 8.3, 4.0, 1.15, 'Pull: GitOps (ArgoCD)',
             'agent inside the cluster', face='#d4ecc9', edge=C_GREEN)
    for i, (title, sub) in enumerate([
            ('Git', 'desired state'), ('ArgoCD', 'in-cluster'), ('Cluster', '')]):
        y = 6.6 - i * 1.5
        face = C_BLUE if i == 0 else (C_ORANGE if i == 1 else C_GREEN)
        draw_box(ax, 7.5, y, 2.6, 1.05, title, sub, face=face, edge='#555')
        if i > 0:
            arrow(ax, 7.5, y + 0.95, 7.5, y + 0.55, color=C_GREEN)
    label(ax, 7.5, 1.6, 'no creds outside, selfHeal fixes drift',
          color=C_GREEN, fs=7.5)

    # separator
    ax.plot([5, 5], [1.0, 8.9], color='#ccc', lw=1, linestyle=':', zorder=1)


def panel_app_of_apps(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('app-of-apps: one root Application manages the rest',
                 fontsize=11, fontweight='bold')

    # Root application
    draw_box(ax, 5, 8.3, 3.6, 1.2, 'root Application',
             'path: apps/ (child YAMLs)', face=C_BLUE, edge='#2d4a75')

    # Child applications
    for i, (x, name, ns) in enumerate([(2.0, 'guestbook', 'ns guestbook'),
                                       (5.0, 'api-gateway', 'ns infra'),
                                       (8.0, 'monitoring', 'ns mon')]):
        draw_box(ax, x, 5.6, 2.7, 1.15, name, ns,
                 face='#e8eef7', edge=C_BLUE)
        arrow(ax, 5, 7.7, x, 6.2, color=C_BLUE)
        # each child deploys workloads
        arrow(ax, x, 5.0, x, 3.62, color=C_GREEN)
        for j, dx in enumerate([-0.55, 0, 0.55]):
            box = FancyBboxPatch((x + dx - 0.24, 3.3 - 0.24), 0.48, 0.48,
                                 boxstyle='round,pad=0.02',
                                 facecolor=C_GREEN, edgecolor='#2f6b3c',
                                 linewidth=1.0, zorder=3)
            ax.add_patch(box)
        label(ax, x, 2.6, 'workloads', color=C_GREEN, fs=7)

    label(ax, 5, 1.5,
          'add an app = commit one YAML to apps/  |  remove = delete the file (prune)',
          color='#555', fs=8)
    label(ax, 5, 0.9, 'the whole platform bootstraps from a single root',
          color='#888', fs=7.5, style='italic')


def main():
    fig = plt.figure(figsize=(13.5, 10.2))
    gs = fig.add_gridspec(2, 2, height_ratios=[1, 1], hspace=0.25, wspace=0.1)
    ax1 = fig.add_subplot(gs[0, :])
    ax2 = fig.add_subplot(gs[1, 0])
    ax3 = fig.add_subplot(gs[1, 1])

    panel_loop(ax1)
    panel_pull_push(ax2)
    panel_app_of_apps(ax3)

    fig.suptitle('GitOps with ArgoCD: Reconciliation Loop & Delivery Models',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
