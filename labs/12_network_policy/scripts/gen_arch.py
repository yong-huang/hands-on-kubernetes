"""NetworkPolicy visualization: policy model (podSelector + ingress rules) & before/after isolation"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))
OUT_PATH = os.path.join(SCRIPT_DIR, '..', 'images', 'network_policy_arch.png')

# Color palette (seaborn-style series colors)
C_POLICY = '#4c72b0'    # NetworkPolicy object: blue
C_ALLOW = '#55a868'     # allowed traffic: green
C_DENY = '#c44e52'      # blocked traffic: red
C_TARGET = '#8cd98c'    # selected/protected pod
C_EVIL = '#f4c542'      # untrusted client
C_DNS = '#8172b3'       # kube-dns
C_TEXT = '#333333'
C_BG = '#e8eef7'


def draw_box(ax, x, y, w, h, title, sub='', face='white', edge='#333', fs=9.5):
    """Draw a rounded box centered at (x, y) with a title and optional subtitle."""
    box = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                         boxstyle='round,pad=0.02',
                         facecolor=face, edgecolor=edge, linewidth=1.5, zorder=3)
    ax.add_patch(box)
    if sub:
        ax.text(x, y + h * 0.16, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)
        ax.text(x, y - h * 0.18, sub, ha='center', va='center',
                fontsize=7, color='#555', zorder=4)
    else:
        ax.text(x, y, title, ha='center', va='center',
                fontsize=fs, fontweight='bold', color=C_TEXT, zorder=4)


def arrow(ax, x1, y1, x2, y2, color='#666', lw=1.8, style='-|>', cs=None):
    """Draw an arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=3, shrinkB=3)
    if cs:
        props['connectionstyle'] = cs
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=props, zorder=2)


def draw_x(ax, x, y, color=C_DENY, s=28):
    """Draw a big red X (blocked)."""
    ax.text(x, y, 'X', ha='center', va='center', fontsize=s,
            fontweight='bold', color=color, zorder=5)


# ---------------------------------------------------------------------------
# Panel 1: policy model - podSelector picks WHO is isolated, ingress rules
#           describe WHO is allowed in; default-deny = policy with no rules
# ---------------------------------------------------------------------------
def panel_model(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('NetworkPolicy model: podSelector picks WHO is isolated',
                 fontsize=11, fontweight='bold')

    # The NetworkPolicy object (left): spec split into its two key parts
    draw_box(ax, 2.4, 8.6, 4.2, 1.3, 'NetworkPolicy spec',
             'policyTypes: [Ingress, Egress]', face=C_POLICY, edge='#2d4a75')

    # podSelector branch
    draw_box(ax, 2.4, 6.3, 4.2, 1.1, 'podSelector: app=backend',
             'applies the policy to these pods', face=C_BG, edge='#8899bb')
    arrow(ax, 2.4, 7.95, 2.4, 6.9, color=C_POLICY)

    # ingress branch
    draw_box(ax, 2.4, 3.9, 4.2, 1.5, 'ingress: [rules]',
             'from: podSelector / namespaceSelector / ipBlock\nports: [TCP 80]',
             face='#d4ecc9', edge=C_ALLOW, fs=9)
    arrow(ax, 2.4, 5.7, 2.4, 4.7, color=C_ALLOW)

    # Target pods (right): selected by podSelector
    draw_box(ax, 7.6, 6.3, 3.6, 1.2, 'Pods: app=backend',
             'isolated (policy targets them)', face=C_TARGET, edge='#3d7a3d')
    arrow(ax, 4.6, 6.3, 5.8, 6.3, color=C_POLICY, style='-|>')
    ax.text(5.2, 6.65, 'selects', fontsize=7.5, ha='center', color=C_POLICY)

    # Source pods (right): filtered by "from"
    draw_box(ax, 6.4, 3.0, 2.0, 1.1, 'app=frontend', 'allowed in',
             face='white', edge=C_ALLOW)
    draw_box(ax, 8.9, 3.0, 2.0, 1.1, 'other pods', 'NOT allowed',
             face='#f7e6e6', edge=C_DENY)
    arrow(ax, 4.6, 3.9, 6.4, 3.1, color=C_ALLOW)
    arrow(ax, 4.6, 3.9, 8.9, 3.1, color=C_DENY, style='-|>')
    arrow(ax, 7.4, 3.0, 7.6, 5.7, color=C_ALLOW, cs='arc3,rad=-0.25')
    draw_x(ax, 8.9, 4.4)

    # Default-deny concept box
    draw_box(ax, 5, 1.0, 8.6, 1.4,
             'Default-deny pattern: podSelector:{} + policyTypes:[Ingress] + no rules',
             'no policy = allow all  |  a policy of that type with no matching rule = deny all',
             face='#fdf3d7', edge='#c9a227', fs=8.5)


# ---------------------------------------------------------------------------
# Panel 2: before vs after isolation (frontend allowed, evil blocked, DNS ok)
# ---------------------------------------------------------------------------
def panel_isolation(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Before / after applying default-deny + allow policy',
                 fontsize=11, fontweight='bold')

    # Backend (shared target)
    draw_box(ax, 5, 8.5, 3.2, 1.2, 'Service: backend (:80)',
             'pods app=backend in ns demo-netpol', face=C_TARGET, edge='#3d7a3d')

    # Left half: BEFORE
    ax.text(2.6, 6.9, 'BEFORE: no policy', fontsize=9.5,
            fontweight='bold', ha='center', color='#555')
    draw_box(ax, 2.6, 5.4, 2.4, 1.0, 'frontend', 'app=frontend',
             face='white', edge=C_ALLOW)
    draw_box(ax, 2.6, 3.2, 2.4, 1.0, 'evil pod', 'no label',
             face='#fdf3d7', edge=C_EVIL)
    arrow(ax, 3.8, 5.7, 4.2, 8.0, color=C_ALLOW, cs='arc3,rad=0.2')
    arrow(ax, 3.8, 3.5, 4.2, 8.0, color=C_EVIL, cs='arc3,rad=0.45')
    ax.text(2.6, 1.9, 'both reach backend: cluster-default\nis allow-all, no isolation',
            fontsize=7.5, ha='center', color='#555')

    # Divider
    ax.plot([5, 5], [1.4, 9.3], color='#bbb', lw=1, linestyle='--', zorder=1)

    # Right half: AFTER
    ax.text(7.5, 6.9, 'AFTER: default-deny + allow-frontend',
            fontsize=9.5, fontweight='bold', ha='center', color=C_POLICY)
    draw_box(ax, 6.4, 5.4, 2.2, 1.0, 'frontend', 'allowed (rule match)',
             face='white', edge=C_ALLOW)
    draw_box(ax, 8.7, 5.4, 2.2, 1.0, 'evil pod', 'blocked (no match)',
             face='#f7e6e6', edge=C_DENY)
    arrow(ax, 6.9, 5.9, 5.9, 8.0, color=C_ALLOW)
    arrow(ax, 8.4, 5.7, 6.2, 8.1, color=C_DENY, cs='arc3,rad=-0.2')
    draw_x(ax, 6.9, 7.15)

    # DNS exception
    draw_box(ax, 7.6, 2.9, 3.4, 1.1, 'kube-dns :53',
             'UDP+TCP must stay reachable', face='#e6e0f2', edge=C_DNS)
    arrow(ax, 7.6, 3.5, 7.6, 4.9, color=C_DNS, lw=1.4, cs='arc3,rad=0.0')
    ax.text(7.6, 1.9, 'classic pitfall: egress deny breaks DNS,\nalways add an allow-dns rule',
            fontsize=7.5, ha='center', color=C_DNS)

    # Footer note
    draw_box(ax, 5, 0.6, 8.8, 1.05,
             'NetworkPolicy is enforced by the CNI plugin (Calico/Cilium), not the API server',
             'kind default CNI (kindnet) accepts policies but enforces nothing',
             face='#f5d0d0', edge=C_DENY, fs=8.5)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 6.8))
    panel_model(axes[0])
    panel_isolation(axes[1])
    fig.suptitle('Kubernetes NetworkPolicy: Policy Model & Default-Deny Isolation',
                 fontsize=13, fontweight='bold', y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(OUT_PATH, dpi=150, bbox_inches='tight')
    print(f'saved: {OUT_PATH}')


if __name__ == '__main__':
    main()
