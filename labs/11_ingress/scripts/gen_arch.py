"""Ingress architecture visualization"""

import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

for _f in ["PingFang SC", "Heiti SC", "STHeiti", "SimHei"]:
    if any(_f in f.name for f in fm.fontManager.ttflist):
        plt.rcParams["font.sans-serif"] = [_f, "DejaVu Sans"]
        plt.rcParams["axes.unicode_minus"] = False
        break

C1, C2, C3, C4 = "#4C72B0", "#55A868", "#DD8452", "#C44E52"


def box(ax, x, y, w, h, text, color, fontsize=9, bold=True, alpha=0.15):
    ax.add_patch(FancyBboxPatch((x - w/2, y - h/2), w, h,
                                boxstyle="round,pad=0.08",
                                facecolor=color, alpha=alpha,
                                edgecolor=color, lw=2))
    ax.text(x, y, text, ha="center", va="center", fontsize=fontsize,
            fontweight="bold" if bold else "normal", color=color)


def arrow(ax, x1, y1, x2, y2, color="#666", label=None, rad=0.0):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="->",
                                 color=color, lw=1.8,
                                 connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((x1+x2)/2 + 0.15, (y1+y2)/2 + 0.25, label,
                fontsize=7.5, color=color)


def main():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 7.5))
    fig.suptitle("Ingress -- L7 Routing in Kubernetes",
                 fontsize=14, fontweight="bold")

    # ---- Panel 1: traffic flow ----
    ax1.set_xlim(0, 10); ax1.set_ylim(0, 10)
    ax1.set_title("Traffic Flow", fontsize=12, fontweight="bold")
    ax1.axis("off")

    box(ax1, 5, 9.0, 3.0, 1.0, "Client\ncurl -H 'Host: a.com'", C1)
    box(ax1, 5, 6.8, 4.2, 1.2, "Ingress Controller (nginx)\nDeployment + Service (LB)", C3)
    box(ax1, 2.2, 4.4, 3.4, 1.1, "Ingress resource\nrouting rules", C2, fontsize=8)
    box(ax1, 7.8, 4.4, 3.2, 1.1, "config generation\n(nginx.conf)", C2, fontsize=8)
    box(ax1, 2.2, 2.0, 3.0, 1.0, "Service web-a\n-> Pods", C4, fontsize=8)
    box(ax1, 7.8, 2.0, 3.0, 1.0, "Service web-b\n-> Pods", C4, fontsize=8)

    arrow(ax1, 5, 8.5, 5, 7.4, C1, "HTTP + Host header")
    arrow(ax1, 3.4, 6.5, 2.5, 5.0, C3)
    arrow(ax1, 6.6, 6.5, 7.5, 5.0, C3, "watch")
    arrow(ax1, 2.2, 3.85, 2.2, 2.5, C3, "host=a.com")
    arrow(ax1, 7.8, 3.85, 7.8, 2.5, C3, "host=b.com")
    ax1.text(5, 0.6, "Ingress = rules only; Controller does the work\n"
                     "Controller watches Ingress objects, reloads nginx.conf",
             ha="center", fontsize=8.5, color="#666", style="italic")

    # ---- Panel 2: routing decision + compare ----
    ax2.set_xlim(0, 10); ax2.set_ylim(0, 10)
    ax2.set_title("Routing Rules & Alternatives", fontsize=12, fontweight="bold")
    ax2.axis("off")

    ax2.text(5, 9.2, "Request: Host + Path", ha="center", fontsize=10,
             fontweight="bold", color=C1)
    box(ax2, 2.5, 7.6, 4.0, 1.0, "host: a.example.com\n-> web-a", C2, fontsize=8)
    box(ax2, 7.5, 7.6, 4.0, 1.0, "host: b.example.com\n-> web-b", C3, fontsize=8)
    box(ax2, 2.5, 5.6, 4.0, 1.0, "path: example.com/a\n-> web-a", C2, fontsize=8)
    box(ax2, 7.5, 5.6, 4.0, 1.0, "path: example.com/b\n-> web-b", C3, fontsize=8)
    arrow(ax2, 5, 8.8, 3.2, 8.1, C1)
    arrow(ax2, 5, 8.8, 6.8, 8.1, C1)
    arrow(ax2, 5, 4.9, 3.2, 6.1, C1, rad=-0.2)
    arrow(ax2, 5, 4.9, 6.8, 6.1, C1, rad=0.2)

    # exposure comparison
    rows = [
        ("Service ClusterIP", "cluster-internal only", "#8172B2"),
        ("Service NodePort", "any node :30000-32767,\nport memorization pain", "#DD8452"),
        ("Service LoadBalancer", "1 LB per service,\ncloud cost, L4 only", "#C44E52"),
        ("Ingress", "one entry, L7 host/path\nrouting, TLS terminate", "#55A868"),
    ]
    for i, (name, desc, color) in enumerate(rows):
        y = 3.4 - i * 0.95
        box(ax2, 2.6, y, 3.6, 0.75, name, color, fontsize=8, alpha=0.12)
        ax2.text(4.7, y, desc, ha="left", va="center", fontsize=7.5, color="#444")

    fig.tight_layout()
    path = os.path.join(SCRIPT_DIR, '..', 'images', 'ingress_arch.png')
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {path}")


if __name__ == "__main__":
    main()
