"""DNS 服务发现可视化：解析流程 + CoreDNS 插件链 + FQDN 结构 + 三种记录对比"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

# seaborn 风格系列色
C_BLUE = '#4c72b0'    # 客户端 / 应用
C_GREEN = '#55a868'   # Service 层
C_RED = '#c44e52'     # Pod
C_PURPLE = '#8172b2'  # CoreDNS / DNS 组件
C_ORANGE = '#cc8963'  # 节点 / 配置
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
          dy=0.15, cs=None):
    """画一条带箭头的连线，可带标签"""
    props = dict(arrowstyle=style, color=color, lw=lw)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props)
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + dy, label,
                ha='center', va='bottom', fontsize=8, color=color)


def panel_flow(ax):
    """面板 1：DNS 解析流程 (app -> resolv.conf -> CoreDNS -> A records) + FQDN 解剖"""
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('In-Cluster DNS Resolution Flow', fontsize=14, fontweight='bold')

    # 应用发起解析
    box(ax, 0.3, 7.0, 2.5, 1.0, 'App Pod\ngetent hosts web', C_BLUE, fontsize=8.5)
    # resolv.conf
    box(ax, 0.3, 4.4, 2.5, 1.8,
        '/etc/resolv.conf\nnameserver 10.96.0.10\nsearch <ns>.svc.cluster.local\n  svc.cluster.local cluster.local\noptions ndots:5',
        C_ORANGE, fontsize=6.8)
    arrow(ax, 1.55, 7.0, 1.55, 6.2, C_GRAY, lw=1.4)
    ax.text(1.65, 6.6, 'expands short name', ha='left', va='center',
            fontsize=7.5, color=C_GRAY)

    # CoreDNS
    box(ax, 3.9, 5.0, 2.8, 1.9,
        'CoreDNS\n(kube-dns Service)\n--- Corefile ---\nkubernetes\nforward . 8.8.8.8\nhosts / cache',
        C_PURPLE, fontsize=8)
    arrow(ax, 2.8, 5.3, 3.9, 5.9, C_GRAY, 'UDP :53 query', dy=0.1)

    # 外部 DNS 兜底
    box(ax, 3.9, 2.8, 2.8, 0.9, 'Upstream DNS\n(cluster-external names)', C_GRAY, fontsize=7.5)
    arrow(ax, 5.3, 5.0, 5.3, 3.7, C_GRAY, 'forward miss', dy=0.05)

    # 解析结果
    box(ax, 8.0, 5.4, 2.6, 1.4, 'Answer: A records\nweb -> 10.96.0.35\n(VIP)', C_GREEN, fontsize=8)
    arrow(ax, 6.7, 6.6, 8.0, 6.2, C_GREEN, 'response', dy=0.1)
    # 回到应用 (弧线从 CoreDNS 上方绕过)
    arrow(ax, 8.0, 5.6, 2.8, 7.2, C_GRAY, lw=1.2, dy=0.05, cs='arc3,rad=0.4')

    # FQDN 解剖图
    ax.text(7.0, 9.5, 'FQDN Anatomy', fontsize=11, fontweight='bold',
            color='#333333', ha='center')
    segs = [('web', C_GREEN), ('default', C_ORANGE), ('svc', C_PURPLE),
            ('cluster.local', C_BLUE)]
    labels = ['service\nname', 'namespace', 'service\nsegment', 'cluster\ndomain']
    x = 3.4
    for (name, color), lab in zip(segs, labels):
        box(ax, x, 7.7, 1.7 if name == 'cluster.local' else 1.3, 0.7,
            name, color, fontsize=8.5)
        ax.text(x + (1.7 if name == 'cluster.local' else 1.3) / 2, 8.75, lab,
                ha='center', fontsize=6.8, color=C_GRAY)
        if name != 'cluster.local':
            ax.text(x + (1.3 if name != 'cluster.local' else 1.7) + 0.08, 8.05, '.',
                    fontsize=12, color='#333333', fontweight='bold')
        x += (1.7 if name == 'cluster.local' else 1.3) + 0.16
    ax.text(9.2, 7.35, 'pod record adds one more label: web-0.web-h.default.svc.cluster.local',
            fontsize=7.5, style='italic', color=C_GRAY, ha='center')

    # ndots 提示
    ax.text(11.6, 4.6, 'ndots:5 pitfall\n"api.github.com" has 2 dots < 5\n-> search domains tried first\n-> extra queries per lookup',
            ha='center', va='center', fontsize=7.8, color='#444444',
            bbox=dict(boxstyle='round,pad=0.4', facecolor='#fdf3ec',
                      edgecolor=C_ORANGE, linewidth=1.2))


def panel_compare(ax):
    """面板 2：ClusterIP vs Headless vs Pod 记录 + search 域展开顺序"""
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Three Record Types & Search Domain Expansion', fontsize=14,
                 fontweight='bold')

    # 三种记录对比
    rows = [
        (7.4, 'ClusterIP Service', 'nslookup web',
         'A  web  ->  10.96.0.35 (single VIP)', C_GREEN),
        (5.4, 'Headless (clusterIP: None)', 'nslookup web-h',
         'A  web-h  ->  10.244.1.5 , 10.244.2.8 (all Pod IPs)', C_RED),
        (3.4, 'Pod record', 'nslookup web-0.web-h',
         'A  web-0.web-h  ->  10.244.1.5 (single Pod IP)', C_PURPLE),
    ]
    for y, title, cmd, result, color in rows:
        ax.text(0.3, y + 1.05, title, fontsize=10, fontweight='bold', color='#333333')
        box(ax, 0.3, y, 3.0, 0.8, cmd, C_BLUE, fontsize=8)
        box(ax, 4.0, y, 5.4, 0.8, result, color, fontsize=8)
        arrow(ax, 3.3, y + 0.4, 4.0, y + 0.4, C_GRAY)

    ax.text(11.5, 6.3, 'Headless use cases:\n- StatefulSet peers\n  (MySQL, Cassandra)\n- Client-side LB (gRPC)\n- service mesh sidecars',
            ha='center', va='center', fontsize=7.8, color='#444444',
            bbox=dict(boxstyle='round,pad=0.4', facecolor='#f5f0f6',
                      edgecolor=C_PURPLE, linewidth=1.2))

    # search 域展开顺序
    ax.text(0.3, 2.55, 'Search domain expansion for short name "web" (ndots:5)',
            fontsize=9.5, fontweight='bold', color='#333333')
    steps = [
        '1. web.default.svc.cluster.local  <- HIT',
        '2. web.svc.cluster.local          (miss)',
        '3. web.cluster.local              (miss)',
        '4. web                            (as absolute, miss)',
    ]
    for i, s in enumerate(steps):
        color = C_GREEN if 'HIT' in s else C_GRAY
        box(ax, 0.3 + (i % 2) * 6.4, 1.6 - (i // 2) * 0.85, 6.0, 0.65,
            s, color, fontsize=7.8)
    box(ax, 13.0, 1.6, 0.8, 0.65, '...', C_GRAY, fontsize=9)

    ax.text(7.0, 0.15, 'FQDN with trailing dot ("web.default.svc.cluster.local.") skips expansion entirely',
            ha='center', fontsize=8.5, style='italic', color=C_GRAY)


def main():
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 11))
    fig.suptitle('Kubernetes DNS & Service Discovery (14_dns_discovery)',
                 fontsize=15, y=0.98)

    panel_flow(ax1)
    panel_compare(ax2)

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out = os.path.join(SCRIPT_DIR, '..', 'images', 'dns_discovery_arch.png')
    fig.savefig(out, dpi=150)
    print(f"Saved: {out}")


if __name__ == '__main__':
    main()
