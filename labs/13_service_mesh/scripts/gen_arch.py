"""Service Mesh 架构可视化：Sidecar 模型 + Istio 金丝雀路由"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

# seaborn 风格系列色
C_BLUE = '#4c72b0'    # 客户端 / 外部
C_GREEN = '#55a868'   # Service / 路由层
C_RED = '#c44e52'     # Pod / 版本
C_PURPLE = '#8172b2'  # 控制面 istiod
C_ORANGE = '#cc8963'  # envoy sidecar
C_GRAY = '#8c8c8c'


def box(ax, x, y, w, h, text, color, fontsize=9, text_color='white'):
    """画一个圆角矩形节点"""
    rect = mpatches.FancyBboxPatch((x, y), w, h,
                                   boxstyle="round,pad=0.15",
                                   facecolor=color, edgecolor='white', linewidth=1.5)
    ax.add_patch(rect)
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center',
            fontsize=fontsize, color=text_color, fontweight='bold')


def arrow(ax, x1, y1, x2, y2, color=C_GRAY, label=None, lw=1.8, style='-|>',
          label_dy=0.25, cs=None, label_fs=8):
    """画一条带箭头的连线，可带标签"""
    props = dict(arrowstyle=style, color=color, lw=lw)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props)
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + label_dy, label,
                ha='center', va='bottom', fontsize=label_fs, color=color)


def dashed_rect(ax, x, y, w, h, title):
    """画一个 Pod 外框（虚线）+ 标题"""
    rect = mpatches.FancyBboxPatch((x, y), w, h,
                                   boxstyle="round,pad=0.18",
                                   facecolor='none', edgecolor=C_GRAY,
                                   linewidth=1.5, linestyle='--')
    ax.add_patch(rect)
    ax.text(x + w / 2, y + h - 0.32, title, ha='center', va='center',
            fontsize=9, fontweight='bold', color='#333333')


def panel_sidecar(ax):
    """面板 1：Sidecar 模型 —— 数据面拦截 + 控制面推送"""
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Sidecar Model: Envoy Intercepts Traffic, istiod Pushes Config',
                 fontsize=13, fontweight='bold')

    # 控制面 istiod
    box(ax, 5.2, 8.3, 3.6, 1.2, 'istiod (control plane)\nwatch APIs -> push config',
        C_PURPLE, fontsize=9)

    # 业务 Pod：应用容器 + envoy sidecar
    dashed_rect(ax, 3.6, 3.2, 6.6, 4.2, 'Pod (injected: 2/2 containers)')
    box(ax, 4.0, 3.7, 2.4, 2.4, 'app container\n(canary-web\nbusybox httpd)', C_RED, fontsize=9)
    box(ax, 7.4, 3.7, 2.4, 2.4, 'envoy sidecar\n(istio-proxy)\nin/out bound\ninterception', C_ORANGE, fontsize=9)

    # istiod -> sidecar 配置推送（虚线）
    arrow(ax, 6.4, 8.3, 7.9, 6.3, C_PURPLE, 'xDS push', lw=1.5, style='-|>')
    ax.plot([6.4, 7.9], [8.3, 6.3], color=C_PURPLE, lw=1.5, linestyle='--')

    # 客户端 -> envoy -> 上游 Service (req 弧线从 app 容器上方绕过, 落在 envoy 顶边)
    box(ax, 0.3, 4.4, 2.2, 1.0, 'Client Pod', C_BLUE)
    arrow(ax, 2.5, 4.9, 7.8, 6.1, C_GRAY, lw=1.8, cs='arc3,rad=-0.45')
    ax.text(3.1, 5.0, 'req', fontsize=8, ha='center', color=C_GRAY)
    # sidecar 与 app 之间的本地回环
    arrow(ax, 7.4, 5.5, 6.4, 5.5, C_ORANGE, 'lo', lw=1.4, label_fs=7)
    arrow(ax, 6.4, 4.5, 7.4, 4.5, C_ORANGE, 'resp', lw=1.4, label_fs=7)

    # envoy -> 上游 Pod 的 envoy（service-to-service）
    dashed_rect(ax, 11.4, 3.5, 2.4, 3.4, 'upstream Pod')
    box(ax, 11.7, 5.2, 1.8, 1.0, 'envoy', C_ORANGE, fontsize=8.5)
    box(ax, 11.7, 3.8, 1.8, 1.0, 'app', C_RED, fontsize=8.5)
    arrow(ax, 9.8, 4.9, 11.4, 5.7, C_GREEN, 'route\n90/10', lw=1.8)
    arrow(ax, 11.4, 4.4, 9.8, 4.2, C_GRAY, lw=1.4, style='-|>', label_dy=-0.9)

    # 底部说明
    ax.text(7.0, 1.5, 'injection = MutatingWebhook rewrites Pod spec at creation time:\n'
                      'adds istio-proxy container + iptables rules redirect all traffic through envoy',
            ha='center', fontsize=9, style='italic', color=C_GRAY)
    ax.text(7.0, 0.35, 'K8s Service still exists (name -> Pod set), but load balancing is taken over by sidecars',
            ha='center', fontsize=8.5, color='#555555')


def panel_canary(ax):
    """面板 2：金丝雀路由 —— 权重 / 镜像 / header，以及 Ingress vs Mesh"""
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Canary Routing: VirtualService Weights, Mirror, Ingress vs Mesh',
                 fontsize=13, fontweight='bold')

    # ---- 左半：VirtualService 权重分流 ----
    ax.text(3.4, 9.3, 'weight-based canary', fontsize=10, fontweight='bold',
            ha='center', color='#333333')
    box(ax, 0.3, 7.6, 2.0, 0.9, 'requests', C_BLUE, fontsize=8.5)
    box(ax, 2.6, 7.6, 2.4, 0.9, 'VirtualService\nhost: canary-web', C_GREEN, fontsize=8)
    # DestinationRule / subset
    box(ax, 2.6, 6.0, 2.4, 1.0, 'DestinationRule\nsubsets: v1, v2', C_PURPLE, fontsize=8)
    arrow(ax, 3.8, 7.6, 3.8, 7.0, C_GRAY, lw=1.4, style='<|-|>')
    ax.text(3.8, 7.3, 'define subsets', ha='center', va='center', fontsize=7.5,
            color=C_GRAY, bbox=dict(fc='white', ec='none', pad=1.2), zorder=5)

    # v1 (90%) 大盒子
    dashed_rect(ax, 0.6, 2.4, 2.9, 2.6, 'subset v1 (stable)')
    box(ax, 1.0, 2.8, 2.1, 1.5, 'web-v1\n2 replicas\n"web-v1"', C_RED, fontsize=8.5)
    # v2 (10%) 小盒子
    dashed_rect(ax, 4.0, 2.4, 2.9, 2.6, 'subset v2 (canary)')
    box(ax, 4.4, 2.8, 2.1, 1.5, 'web-v2\n2 replicas\n"web-v2"', C_ORANGE, fontsize=8.5)

    arrow(ax, 3.3, 7.6, 2.2, 5.4, C_GREEN, 'weight 90', lw=2.4, label_dy=0.5)
    arrow(ax, 4.3, 7.6, 5.2, 5.4, C_GREEN, 'weight 10', lw=1.4, label_dy=0.5)

    # 镜像说明
    mirror = mpatches.FancyBboxPatch((0.6, 0.3), 6.3, 1.6,
                                     boxstyle="round,pad=0.2",
                                     facecolor='#f0f5f0', edgecolor=C_GREEN, linewidth=1.5)
    ax.add_patch(mirror)
    ax.text(3.75, 1.1, 'mirror: route 100% -> v1, copy traffic to v2\n'
                       '(responses from v2 are dropped; zero user risk)',
            ha='center', va='center', fontsize=8.5, color='#2f6b3a')
    ax.text(3.75, 5.3, 'header match: x-canary=true -> v2',
            ha='center', fontsize=8.5, style='italic', color=C_GRAY)

    # ---- 右半：Ingress vs Mesh 对比 ----
    ax.plot([7.4, 7.4], [0.3, 9.4], color='#cccccc', lw=1, linestyle=':')
    ax.text(10.8, 9.3, 'Ingress vs Mesh', fontsize=10, fontweight='bold',
            ha='center', color='#333333')

    # Ingress：只在边缘
    ax.text(8.0, 8.35, 'Ingress = L7 at the edge only', fontsize=9,
            color='#333333', fontweight='bold')
    box(ax, 8.0, 7.0, 1.7, 0.8, 'outside', C_BLUE, fontsize=8)
    box(ax, 10.1, 7.0, 1.9, 0.8, 'Ingress\n(L7 edge)', C_GREEN, fontsize=8)
    box(ax, 12.4, 7.0, 1.4, 0.8, 'svc', C_RED, fontsize=8)
    arrow(ax, 9.7, 7.4, 10.1, 7.4, C_GRAY, lw=1.4)
    arrow(ax, 12.0, 7.4, 12.4, 7.4, C_GRAY, lw=1.4)
    ax.text(11.0, 6.35, 'inside cluster: plain kube-proxy again,\n'
                        'no retries / mTLS / fine routing',
            ha='center', fontsize=8, color='#777777')

    # Mesh：每一跳都有治理
    ax.text(8.0, 4.9, 'Mesh = every hop (service-to-service)', fontsize=9,
            color='#333333', fontweight='bold')
    box(ax, 8.0, 3.4, 1.7, 0.8, 'svc A', C_BLUE, fontsize=8)
    box(ax, 10.1, 3.4, 1.9, 0.8, 'envoy\nevery pod', C_ORANGE, fontsize=8)
    box(ax, 12.4, 3.4, 1.4, 0.8, 'svc B', C_RED, fontsize=8)
    arrow(ax, 9.7, 3.8, 10.1, 3.8, C_GRAY, 'mTLS', lw=1.4)
    arrow(ax, 12.0, 3.8, 12.4, 3.8, C_GRAY, 'retry', lw=1.4)
    ax.text(11.0, 2.75, 'retries, timeouts, mTLS, fault injection,\n'
                        'traffic splitting between any two services',
            ha='center', fontsize=8, color='#777777')

    ax.text(11.0, 1.0, 'both can coexist:\nIngress/Gateway at edge, mesh inside',
            ha='center', fontsize=8.5, style='italic', color=C_GRAY)


def main():
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 11))
    fig.suptitle('Service Mesh / Istio Canary Release (13_service_mesh)',
                 fontsize=15, y=0.98)

    panel_sidecar(ax1)
    panel_canary(ax2)

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out = os.path.join(SCRIPT_DIR, '..', 'images', 'service_mesh_arch.png')
    fig.savefig(out, dpi=150)
    print(f"Saved: {out}")


if __name__ == '__main__':
    main()
