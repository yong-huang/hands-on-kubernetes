"""Service 架构可视化：三种 Service 类型流量路径 + kube-proxy/Endpoints/ClusterDNS"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

# seaborn 风格系列色
C_BLUE = '#4c72b0'    # 客户端 / 外部
C_GREEN = '#55a868'   # Service 层
C_RED = '#c44e52'     # Pod
C_PURPLE = '#8172b2'  # 控制面 / 组件
C_ORANGE = '#cc8963'  # 节点
C_GRAY = '#8c8c8c'


def box(ax, x, y, w, h, text, color, fontsize=9, text_color='white'):
    """画一个圆角矩形节点"""
    rect = mpatches.FancyBboxPatch((x, y), w, h,
                                   boxstyle="round,pad=0.15",
                                   facecolor=color, edgecolor='white', linewidth=1.5)
    ax.add_patch(rect)
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center',
            fontsize=fontsize, color=text_color, fontweight='bold')


def arrow(ax, x1, y1, x2, y2, color=C_GRAY, label=None, lw=1.8, style='-|>'):
    """画一条带箭头的连线，可带标签"""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle=style, color=color, lw=lw))
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 0.25, label,
                ha='center', va='bottom', fontsize=8, color=color)


def panel_services(ax):
    """面板 1：ClusterIP / NodePort / LoadBalancer 流量路径对比"""
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Kubernetes Service Types: Traffic Paths', fontsize=14, fontweight='bold')

    rows = [
        (7.2, 'ClusterIP', ['Client (in-cluster)'], 'Service VIP :80', 'pods'),
        (4.2, 'NodePort', ['Outside Client'], 'NodeIP :30080 -> Service VIP :80', 'pods'),
        (1.2, 'LoadBalancer', ['Outside Client'], 'Cloud LB -> NodeIP :31xxx -> VIP :80', 'pods'),
    ]

    for y, name, clients, middle, _ in rows:
        # 类型标签
        ax.text(0.3, y + 1.15, name, fontsize=11, fontweight='bold', color='#333333')
        # 客户端
        box(ax, 0.3, y, 2.2, 0.9, clients[0], C_BLUE)
        # 中间层（Service / LB）
        parts = middle.split('->')
        if len(parts) == 1:
            # ClusterIP：直接到 Service VIP
            box(ax, 4.2, y, 3.0, 0.9, parts[0].strip(), C_GREEN)
            arrow(ax, 2.5, y + 0.45, 4.2, y + 0.45, C_GRAY)
            svc_x = 7.2
        else:
            # NodePort / LB：中间多一跳
            box(ax, 4.0, y, 3.2, 0.9, parts[0].strip(), C_ORANGE)
            box(ax, 8.2, y, 3.4, 0.9, parts[1].strip(), C_GREEN)
            arrow(ax, 2.5, y + 0.45, 4.0, y + 0.45, C_GRAY)
            arrow(ax, 7.2, y + 0.45, 8.2, y + 0.45, C_GRAY)
            svc_x = 11.6
        # 三个 Pod
        for i, py in enumerate([y + 1.05, y + 0.45, y - 0.15]):
            box(ax, svc_x, py - 0.28, 1.5, 0.56, f'Pod {i + 1}', C_RED, fontsize=7.5)
            arrow(ax, svc_x - 0.9 if svc_x == 7.2 else svc_x - 0.9,
                  y + 0.45, svc_x, py, C_GRAY, lw=1.0)


def panel_internals(ax):
    """面板 2：kube-proxy + iptables、Endpoints、ClusterDNS 内部机制"""
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Under the Hood: kube-proxy, Endpoints & ClusterDNS', fontsize=14, fontweight='bold')

    # 左侧：Pod 访问 Service VIP
    box(ax, 0.3, 7.6, 2.4, 0.9, 'Client Pod', C_BLUE)
    box(ax, 0.6, 5.6, 1.8, 0.9, 'Service\nVIP :80', C_GREEN, fontsize=8.5)
    arrow(ax, 1.5, 7.6, 1.5, 6.5, C_GRAY, 'DNS resolve')

    # ClusterDNS
    box(ax, 3.2, 7.6, 2.4, 0.9, 'ClusterDNS\n(kube-dns)', C_PURPLE, fontsize=8.5)
    arrow(ax, 2.7, 8.05, 3.2, 8.05, C_GRAY, 'svc name -> VIP', style='<|-|>')

    # 中间：kube-proxy / iptables
    box(ax, 3.5, 4.9, 3.2, 2.2,
        'kube-proxy\n(iptables / ipvs)\nDNAT: VIP -> PodIP', C_ORANGE, fontsize=9)
    arrow(ax, 2.4, 6.05, 3.5, 6.05, C_RED, 'packet to VIP')

    # Endpoints 维护链路
    box(ax, 3.2, 2.6, 3.8, 1.0, 'Endpoints Controller\nwatches Pod labels', C_PURPLE, fontsize=8)
    arrow(ax, 5.1, 3.6, 5.1, 4.9, C_GRAY, 'sync rules')

    # 右侧：真实 Pod IP 列表
    ax.text(8.2, 6.55, 'Endpoints = ready Pod IPs', fontsize=9, color='#333333',
            fontweight='bold')
    for i, (py, label) in enumerate([(5.7, '10.244.1.5:80'), (4.7, '10.244.2.8:80'),
                                     (3.7, '10.244.3.2:80')]):
        box(ax, 8.2, py, 2.2, 0.62, label, C_RED, fontsize=8)
    arrow(ax, 6.7, 6.05, 8.2, 6.05, C_RED, 'load balance')

    # Headless 说明框
    hl = mpatches.FancyBboxPatch((11.0, 3.2), 2.7, 3.6,
                                 boxstyle="round,pad=0.2",
                                 facecolor='#f5f0f6', edgecolor=C_PURPLE, linewidth=1.5)
    ax.add_patch(hl)
    ax.text(12.35, 6.35, 'Headless Service', ha='center', fontsize=9.5,
            fontweight='bold', color=C_PURPLE)
    ax.text(12.35, 4.6, 'clusterIP: None\nno VIP, no DNAT\nDNS returns\nall Pod IPs\ndirectly',
            ha='center', va='center', fontsize=8, color='#444444')
    arrow(ax, 10.4, 6.0, 11.0, 5.2, C_PURPLE, lw=1.4)

    # NodePort 性能提示
    ax.text(7.0, 1.0, 'iptables mode: O(n) rule matching, linear scan at scale  ->  ipvs mode for large clusters',
            ha='center', fontsize=8.5, style='italic', color=C_GRAY)


def main():
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 11))
    fig.suptitle('Kubernetes Service Architecture (04_service)', fontsize=15, y=0.98)

    panel_services(ax1)
    panel_internals(ax2)

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out = os.path.join(SCRIPT_DIR, '..', 'images', 'service_arch.png')
    fig.savefig(out, dpi=150)
    print(f"Saved: {out}")


if __name__ == '__main__':
    main()
