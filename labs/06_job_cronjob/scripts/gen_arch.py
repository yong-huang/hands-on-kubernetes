"""Job & CronJob 可视化: 工作负载对比 (Job/CronJob/Deployment) + 执行流程 (completions x parallelism, backoff, concurrencyPolicy)"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'job_cronjob_arch.png')

# 配色 (seaborn 风格系列色)
C_JOB = '#4c72b0'      # Job: 蓝
C_CRON = '#55a868'     # CronJob: 绿
C_DEPLOY = '#dd8452'   # Deployment: 橙
C_FAIL = '#c44e52'     # failure / backoff: 红
C_POD_OK = '#8cd98c'   # successful pod
C_POD_RUN = '#f4c542'  # running pod
C_POD_DEAD = '#e8a0a0' # failed pod
C_TEXT = '#333333'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333',
             fs=9.5, subfs=7.5):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.14, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.18, sub, ha='center', va='center',
                fontsize=subfs, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.6, style='-|>', cs=None):
    """Draw an arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


def draw_pod(ax, x, y, state='ok', label='Pod', w=0.84, h=0.5):
    """Draw a small pod box; state in {'ok','run','dead'}."""
    colors = {'ok': C_POD_OK, 'run': C_POD_RUN, 'dead': C_POD_DEAD}
    edge = '#999' if state == 'dead' else '#333'
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=colors[state], edgecolor=edge,
                         linewidth=1.2, zorder=3,
                         linestyle='--' if state == 'dead' else '-')
    ax.add_patch(box)
    txt = {'dead': 'x', 'run': '...'}.get(state, '')
    ax.text(x, y, f'{label}{txt}', ha='center', va='center',
            fontsize=6.5, color=C_TEXT, zorder=4)


# ---------------------------------------------------------------------------
# Panel 1: Job vs CronJob vs Deployment comparison
# ---------------------------------------------------------------------------
def panel_compare(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('One-shot vs Scheduled vs Long-running workloads',
                 fontsize=11, fontweight='bold')

    # Header row
    headers = [('Job', 'run to completion', C_JOB, 3.0),
               ('CronJob', 'schedule -> Job', C_CRON, 5.6),
               ('Deployment', 'run forever', C_DEPLOY, 8.2)]
    for title, sub, color, x in headers:
        draw_box(ax, x, 8.7, 2.5, 1.1, title, sub, face=color, edge='#333',
                 fs=10)

    # Comparison rows (label on the left, values under each column)
    rows = [
        ('Goal', 'exit 0 = success', 'recurring tasks', 'always available'),
        ('Lifetime', 'terminates', 'Job per tick', 'never ends'),
        ('Pod restart', 'retry w/ backoff', 'delegates to Job', 'reschedule'),
        ('Typical use', 'batch, convert', 'backup, report', 'web, api'),
    ]
    y = 6.9
    for label, a, b, c in rows:
        ax.text(0.1, y, label, fontsize=8, fontweight='bold', color='#555',
                va='center', ha='left')
        for text, (_, _, color, x) in zip((a, b, c), headers):
            box = FancyBboxPatch((x - 1.25, y - 0.45), 2.5, 0.9,
                                 boxstyle='round,pad=0.02',
                                 facecolor='#f4f6f8', edgecolor=color,
                                 linewidth=1.1, zorder=3)
            ax.add_patch(box)
            ax.text(x, y, text, ha='center', va='center', fontsize=7.5,
                    color=C_TEXT, zorder=4)
        y -= 1.35

    # Ownership chain
    arrow(ax, 5.0, 2.75, 5.0, 2.2, color='#888', lw=1.2)
    draw_box(ax, 5, 1.4, 8.4, 1.3,
             'CronJob -> Job -> Pod  (ownership chain)',
             'Deployment -> ReplicaSet -> Pod  |  a Job that finished stays for logs/history',
             face='#e8eef7', edge='#8899bb')


# ---------------------------------------------------------------------------
# Panel 2: execution flow - completions x parallelism, backoff, concurrencyPolicy
# ---------------------------------------------------------------------------
def panel_flow(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Job execution: batching, backoff & CronJob scheduling',
                 fontsize=11, fontweight='bold')

    # --- Left top: completions x parallelism batching ---
    ax.text(0.2, 9.5, 'completions=6, parallelism=2  (3 batches)',
            fontsize=8.5, fontweight='bold', color=C_JOB, ha='left')
    batches = [
        (['ok', 'ok'], 'batch 1'),
        (['ok', 'run'], 'batch 2'),
        (['run', ''], 'batch 3'),
    ]
    y = 8.4
    for states, name in batches:
        ax.text(0.3, y, name, fontsize=7, color='#555', va='center')
        x = 1.7
        for s in states:
            if s:
                draw_pod(ax, x, y, state=s, label='', w=0.7, h=0.5)
            x += 0.9
        y -= 0.85
    ax.text(0.2, 5.55,
            'SUCCESSFUL pods count toward completions;\nfailed ones are replaced until backoffLimit',
            fontsize=6.5, color='#555', ha='left', va='top')

    # --- Left bottom: backoff retry loop ---
    draw_box(ax, 1.9, 3.6, 3.0, 1.0, 'Pod failed (exit != 0)',
             face='#f5d0d0', edge=C_FAIL)
    arrow(ax, 1.9, 3.1, 1.9, 2.5, color=C_FAIL)
    draw_box(ax, 1.9, 2.0, 3.0, 1.0, 'backoff: 10s, 20s, 40s...',
             'Never: new Pod / OnFailure: restart',
             face='#fdf3d7', edge='#c9a227', fs=8, subfs=6.5)
    # retry loop: from backoff box back up to the failed-pod box
    arrow(ax, 3.5, 2.0, 3.5, 3.6, color='#aaa', lw=1.2, cs='arc3,rad=-0.5')
    ax.text(4.45, 2.8, 'retry', fontsize=6.5, color='#777')
    draw_box(ax, 1.9, 0.6, 3.6, 0.8, 'backoffLimit exceeded -> Job FAILED',
             face='#f5d0d0', edge=C_FAIL, fs=7.5)
    arrow(ax, 1.9, 1.5, 1.9, 1.0, color=C_FAIL)

    # --- Right: CronJob schedule -> concurrency policy branches ---
    draw_box(ax, 7.3, 8.7, 3.0, 1.0, 'CronJob',
             'schedule: "0 * * * *"', face=C_CRON, edge='#333')
    arrow(ax, 7.3, 8.2, 7.3, 7.6, color='#666')

    # Missed schedule note
    draw_box(ax, 7.3, 7.1, 3.2, 0.85, 'tick fires -> create Job',
             'if missed > startingDeadlineSeconds: skip',
             face='#d4ecc9', edge='#3f7a4f', fs=7.5, subfs=6)

    # Branches for previous job still running
    ax.text(7.3, 6.15, 'previous Job still running?', fontsize=7,
            color='#555', ha='center', style='italic')
    policies = [
        ('Allow (default)', 'run concurrently', C_POD_RUN, 5.5),
        ('Forbid', 'skip this tick', '#f5d0d0', 7.3),
        ('Replace', 'kill old, new', '#d4ecc9', 9.1),
    ]
    for title, sub, face, x in policies:
        draw_box(ax, x, 5.2, 1.75, 0.95, title, sub, face=face, edge='#555',
                 fs=7.5, subfs=6)
        arrow(ax, 7.3, 5.9, x, 5.72, color='#999', lw=1.1)

    # History limits
    draw_box(ax, 7.3, 3.3, 4.6, 1.2,
             'finished Jobs are kept for history',
             'successfulJobsHistoryLimit=3, failedJobsHistoryLimit=1\n(then auto-deleted; suspend=true stops scheduling)',
             face='#e8eef7', edge='#8899bb', fs=7.5, subfs=6.5)
    arrow(ax, 7.3, 4.6, 7.3, 3.95, color='#888', lw=1.2)

    # restartPolicy note
    draw_box(ax, 7.3, 1.5, 4.6, 1.2,
             'restartPolicy in Job: Never vs OnFailure',
             'Never: failed Pod stays, a NEW Pod is created\nOnFailure: SAME Pod restarts its container',
             face='#fdf3d7', edge='#c9a227', fs=7.5, subfs=6.5)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_compare(axes[0])
    panel_flow(axes[1])
    fig.suptitle('Kubernetes Job & CronJob: Workload Comparison & Execution Flow',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
