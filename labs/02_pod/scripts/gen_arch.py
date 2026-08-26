"""Pod 架构可视化：内部结构（pause + 多容器 + 共享卷）与生命周期状态流转"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

# 系列配色（与仓库其他 viz.py 保持一致的柔和风格）
C_POD = '#4C72B0'       # Pod 边框 / 主色
C_MAIN = '#C44E52'      # 主容器
C_SIDECAR = '#55A868'   # sidecar 容器
C_INIT = '#8172B2'      # initContainer
C_PAUSE = '#CCB974'     # pause 容器
C_VOL = '#64B5CD'       # 共享卷
C_OK = '#55A868'        # 正常状态
C_BAD = '#C44E52'       # 异常状态
C_TEXT = '#333333'


def box(ax, x, y, w, h, text, fc, fontsize=9, ec='white', text_color='white'):
    """画一个圆角框 + 居中文字"""
    patch = FancyBboxPatch((x, y), w, h,
                           boxstyle='round,pad=0.02,rounding_size=0.08',
                           linewidth=1.5, edgecolor=ec, facecolor=fc)
    ax.add_patch(patch)
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center',
            fontsize=fontsize, color=text_color, weight='bold')
    return patch


def arrow(ax, x1, y1, x2, y2, color=C_TEXT, style='-|>', lw=1.6, rad=0.0, ls='-'):
    """画一条带箭头的连线（rad>0 时为弧线）"""
    ar = FancyArrowPatch((x1, y1), (x2, y2),
                         arrowstyle=style, mutation_scale=14,
                         linewidth=lw, color=color, linestyle=ls,
                         connectionstyle=f'arc3,rad={rad}')
    ax.add_patch(ar)


def draw_arch(ax):
    """Panel 1: Pod 内部结构 —— pause 容器 + 多容器 sidecar 模式 + 共享卷"""
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Pod Internal Structure (Sidecar Pattern)', fontsize=13, weight='bold', pad=12)

    # Pod 外框
    pod = FancyBboxPatch((0.4, 0.6), 9.2, 8.8,
                         boxstyle='round,pad=0.05,rounding_size=0.15',
                         linewidth=2.5, edgecolor=C_POD, facecolor='#EAF0F9')
    ax.add_patch(pod)
    ax.text(5.0, 9.0, 'Pod  (shared network namespace: same IP, same port space)',
            ha='center', fontsize=10.5, color=C_POD, weight='bold')

    # pause 容器：持有 namespace，其他容器加入它
    box(ax, 3.5, 7.4, 3.0, 1.0,
        'pause container\n(holds net/IPC ns, PID 1)', C_PAUSE, fontsize=8.5)
    ax.text(7.3, 7.9, '<- infra container,\n    others join its namespaces',
            fontsize=7.5, color=C_TEXT, va='center')

    # 两个业务容器
    box(ax, 1.0, 4.2, 3.4, 2.2,
        'Main container\nnginx:1.27\nwrites /var/log/nginx', C_MAIN, fontsize=9)
    box(ax, 5.6, 4.2, 3.4, 2.2,
        'Sidecar container\nbusybox log-tailer\nreads /var/log/nginx', C_SIDECAR, fontsize=9)

    # 共享卷 emptyDir
    box(ax, 2.6, 1.2, 4.8, 1.5,
        'Shared Volume  (emptyDir)\n/var/log/nginx', C_VOL, fontsize=9)

    # 挂载箭头
    arrow(ax, 2.7, 4.2, 3.8, 2.7, color=C_MAIN)
    arrow(ax, 7.3, 4.2, 6.2, 2.7, color=C_SIDECAR)
    ax.text(1.1, 3.3, 'mount', fontsize=7.5, color=C_MAIN, rotation=55)
    ax.text(8.5, 3.3, 'mount', fontsize=7.5, color=C_SIDECAR, rotation=-55)

    # 容器到 pause 的关系
    arrow(ax, 2.7, 6.4, 4.0, 7.4, color=C_PAUSE, ls='--', rad=0.15)
    arrow(ax, 7.3, 6.4, 6.0, 7.4, color=C_PAUSE, ls='--', rad=-0.15)

    # 说明
    ax.text(5.0, 0.25,
            'Containers in a Pod: co-scheduled, co-located on one node, share IP & volumes, '
            'reach each other via localhost',
            ha='center', fontsize=8, color=C_TEXT, style='italic')


def draw_lifecycle(ax):
    """Panel 2: Pod 生命周期状态流转"""
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Pod Lifecycle State Transitions', fontsize=13, weight='bold', pad=12)

    # 主链路：Pending -> ContainerCreating -> Running
    box(ax, 0.3, 6.6, 2.1, 1.3, 'Pending', C_POD, fontsize=10)
    box(ax, 2.9, 6.6, 2.6, 1.3, 'Container\nCreating', C_POD, fontsize=9.5)
    box(ax, 5.9, 6.6, 1.9, 1.3, 'Running', C_OK, fontsize=10)

    # 终态
    box(ax, 3.2, 2.8, 2.4, 1.2, 'Succeeded', C_OK, fontsize=9.5)
    box(ax, 6.2, 2.8, 2.0, 1.2, 'Failed', C_BAD, fontsize=9.5)
    box(ax, 6.0, 8.6, 3.4, 1.1, 'CrashLoopBackOff', C_BAD, fontsize=9.5)

    # 主链路箭头
    arrow(ax, 2.4, 7.25, 2.9, 7.25)
    ax.text(2.65, 7.55, 'scheduled', fontsize=7, ha='center', color=C_TEXT)
    arrow(ax, 5.5, 7.25, 5.9, 7.25)
    ax.text(5.7, 7.55, 'pull image,\ncreate ctnr', fontsize=6.5, ha='center', color=C_TEXT)

    # Running 的出口
    arrow(ax, 6.8, 6.6, 5.6, 4.0, color=C_OK)
    ax.text(5.4, 5.5, 'exit 0', fontsize=7.5, color=C_OK)
    arrow(ax, 7.3, 6.6, 7.6, 4.0, color=C_BAD)
    ax.text(7.9, 5.4, 'exit != 0', fontsize=7.5, color=C_BAD)

    # CrashLoopBackOff：反复崩溃，指数退避重启
    arrow(ax, 7.7, 8.6, 7.2, 7.9, color=C_BAD, rad=-0.3)
    ax.text(8.15, 8.2, 'restart with\nbackoff (10s,20s,40s...)', fontsize=7, color=C_BAD, ha='center')
    arrow(ax, 6.6, 8.6, 6.7, 7.9, color=C_OK, rad=0.25)
    ax.text(6.35, 8.3, 'recovers', fontsize=7, color=C_OK, ha='center')

    # 探针对 Running 状态的影响
    box(ax, 0.4, 3.9, 2.4, 1.1, 'liveness fail\n-> restart', C_INIT, fontsize=8)
    box(ax, 0.4, 2.3, 2.4, 1.1, 'readiness fail\n-> no traffic', C_INIT, fontsize=8)
    arrow(ax, 1.6, 5.0, 5.9, 7.0, color=C_INIT, ls='--', rad=0.2)
    arrow(ax, 1.6, 3.4, 5.9, 6.9, color=C_INIT, ls=':', rad=0.35)

    # 初始化
    box(ax, 0.3, 8.7, 2.3, 1.0, 'InitContainer\nphase', C_VOL, fontsize=8.5)
    arrow(ax, 1.5, 8.7, 1.3, 7.9, color=C_VOL)
    ax.text(2.6, 8.3, 'all init containers\nexit 0 first', fontsize=7, color=C_VOL)

    ax.text(5.0, 0.4,
            'Pending(waiting) -> ContainerCreating -> Running -> Succeeded/Failed;  '
            'CrashLoopBackOff = repeated crash + backoff restart',
            ha='center', fontsize=8, color=C_TEXT, style='italic')


def main():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 7.5))
    draw_arch(ax1)
    draw_lifecycle(ax2)
    fig.tight_layout()
    out = os.path.join(SCRIPT_DIR, '..', 'images', 'pod_arch.png')
    fig.savefig(out, dpi=150, bbox_inches='tight')
    print(f'Saved: {out}')


if __name__ == '__main__':
    main()
