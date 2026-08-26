"""K8s ConfigMap/Secret visualization: injection methods, hot reload, base64 flow."""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

# Series colors (seaborn-muted-like palette)
C_CONFIGMAP = '#4c72b0'   # blue  - ConfigMap path
C_SECRET = '#c44e52'      # red   - Secret path
C_NEUTRAL = '#55a868'     # green - general/OK
C_WARN = '#dd8452'        # orange - warning / caveat
C_BOX = '#f0f0f0'
C_TEXT = '#333333'


def box(ax, x, y, w, h, text, fc=C_BOX, ec='#666', fs=9, bold=False, tc=C_TEXT):
    """Rounded box centered at (x, y) with text."""
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                                boxstyle='round,pad=0.02',
                                facecolor=fc, edgecolor=ec, linewidth=1.4, zorder=3))
    ax.text(x, y, text, ha='center', va='center', fontsize=fs, zorder=4,
            fontweight='bold' if bold else 'normal', color=tc)


def arrow(ax, x1, y1, x2, y2, color='#555', lw=1.6, style='-|>', cs=None):
    """Straight (or curved) arrow between two points."""
    props = dict(arrowstyle=style, color=color, lw=lw, shrinkA=2, shrinkB=2)
    if cs:
        props['connectionstyle'] = cs
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), zorder=2, **props))


# ===========================================================================
# Panel 1: injection methods (env vs volume) + hot reload behavior
# ===========================================================================
def panel1(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('ConfigMap / Secret: 4 Injection Methods & Hot Reload',
                 fontsize=13, fontweight='bold', pad=14)

    # Left sources
    box(ax, 1.5, 7.5, 2.4, 1.1, 'ConfigMap\napp-config', fc='#dce6f2',
        ec=C_CONFIGMAP, bold=True)
    box(ax, 1.5, 3.0, 2.4, 1.1, 'Secret\ndb-secret', fc='#f5dcdc',
        ec=C_SECRET, bold=True)

    # Middle: two injection styles
    box(ax, 5.2, 8.5, 3.2, 1.0, '① env / valueFrom\n(single key -> env var)',
        ec=C_CONFIGMAP, fs=9)
    box(ax, 5.2, 6.2, 3.2, 1.0, '② volume mount\n(each key -> file)',
        ec=C_CONFIGMAP, fs=9)
    box(ax, 5.2, 4.0, 3.2, 1.0, '③ secretKeyRef\n(env var, auto decoded)',
        ec=C_SECRET, fs=9)
    box(ax, 5.2, 1.7, 3.2, 1.0, '④ secret volume\n(/etc/secret, mode 0400)',
        ec=C_SECRET, fs=9)

    # Right: Pod container
    ax.add_patch(FancyBboxPatch((7.9, 0.9), 1.8, 7.9,
                                boxstyle='round,pad=0.04',
                                facecolor='#eef7ee', edgecolor=C_NEUTRAL,
                                linewidth=2, linestyle='--', zorder=1))
    ax.text(8.8, 9.1, 'Pod container', ha='center', fontsize=10,
            fontweight='bold', color=C_NEUTRAL)

    arrow(ax, 2.7, 7.9, 3.6, 8.5, C_CONFIGMAP)
    arrow(ax, 2.7, 7.1, 3.6, 6.2, C_CONFIGMAP)
    arrow(ax, 2.7, 3.4, 3.6, 4.0, C_SECRET)
    arrow(ax, 2.7, 2.6, 3.6, 1.7, C_SECRET)
    arrow(ax, 6.8, 8.5, 8.0, 7.6, C_CONFIGMAP)
    arrow(ax, 6.8, 6.2, 8.0, 5.4, C_CONFIGMAP)
    arrow(ax, 6.8, 4.0, 8.0, 3.2, C_SECRET)
    arrow(ax, 6.8, 1.7, 8.0, 1.6, C_SECRET)

    # Hot reload annotation block
    ax.add_patch(FancyBboxPatch((0.4, 0.15), 6.6, 1.15,
                                boxstyle='round,pad=0.03',
                                facecolor='#fdf3e7', edgecolor=C_WARN,
                                linewidth=1.4, zorder=3))
    ax.text(3.7, 0.72,
            'Hot reload:  volume mount  ->  synced in ~1 min (kubelet)\n'
            '             env var      ->  NEVER updated (needs pod restart)\n'
            '             subPath      ->  NEVER synced (even as volume!)',
            ha='center', va='center', fontsize=8.4, color=C_TEXT, zorder=4)


# ===========================================================================
# Panel 2: Secret base64 flow + 12-factor config separation
# ===========================================================================
def panel2(ax):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis('off')
    ax.set_title('Secret: base64 Encoding Flow & 12-Factor Config Separation',
                 fontsize=13, fontweight='bold', pad=14)

    # --- Left half: base64 flow ---
    ax.text(2.6, 9.2, 'base64 flow (encoding, NOT encryption!)',
            ha='center', fontsize=10, fontweight='bold', color=C_SECRET)
    box(ax, 2.6, 7.8, 3.6, 1.0, 'stringData (plaintext)\nDB_PASSWORD: "P@ss..."',
        fc='#f5dcdc', ec=C_SECRET, fs=8.5)
    box(ax, 2.6, 5.6, 3.6, 1.0, 'API Server\nbase64-encode automatically',
        fc=C_BOX, ec='#666', fs=8.5)
    box(ax, 2.6, 3.4, 3.6, 1.0, 'etcd stores\n"UEBzc3cwcmQtMTIz"',
        fc='#e8e8e8', ec='#666', fs=8.5)
    box(ax, 2.6, 1.2, 3.6, 1.0, 'Consumer sees plaintext\n(env var / file content)',
        fc='#eef7ee', ec=C_NEUTRAL, fs=8.5)
    arrow(ax, 2.6, 7.3, 2.6, 6.1, C_SECRET)
    arrow(ax, 2.6, 5.1, 2.6, 3.9, C_SECRET)
    arrow(ax, 2.6, 2.9, 2.6, 1.7, C_NEUTRAL)
    ax.text(0.7, 4.5, 'decode = trivial:\nanyone with read access\nsees the value!',
            fontsize=7.8, color=C_WARN, style='italic', ha='left')

    # Divider
    ax.plot([5.15, 5.15], [0.4, 9.4], color='#bbb', lw=1, linestyle='--')

    # --- Right half: 12-factor separation ---
    ax.text(7.6, 9.2, '12-factor: config separated from code',
            ha='center', fontsize=10, fontweight='bold', color=C_CONFIGMAP)
    box(ax, 7.6, 7.6, 3.4, 1.1, 'Same image\n(dev / staging / prod)', fc='#dce6f2',
        ec=C_CONFIGMAP, fs=9, bold=True)
    arrow(ax, 7.6, 7.0, 7.6, 5.9, C_CONFIGMAP)
    box(ax, 7.6, 5.3, 3.4, 1.0, 'Different configs\n(ConfigMap per env)', fc=C_BOX,
        ec=C_CONFIGMAP, fs=9)
    ax.text(7.6, 3.9, 'image  X  config  =  deployments\n\nno rebuild needed\n'
                      'to change a knob;\nsecrets never baked\ninto image layers',
            ha='center', va='center', fontsize=8.6, color=C_TEXT)
    ax.text(7.6, 1.5, 'Config in env vars\n= 12-factor style',
            ha='center', fontsize=8.2, color=C_NEUTRAL, style='italic')


fig, axes = plt.subplots(2, 1, figsize=(11, 12.5))
panel1(axes[0])
panel2(axes[1])
fig.tight_layout(pad=3.0)
out = os.path.join(SCRIPT_DIR, '..', 'images', 'cm_secret_arch.png')
fig.savefig(out, dpi=150, bbox_inches='tight', facecolor='white')
print(f'saved: {out}')
