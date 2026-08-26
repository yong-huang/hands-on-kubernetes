"""kind local Kubernetes setup architecture visualization"""

import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))


def box(ax, x, y, w, h, text, color, fontsize=9, bold=True, alpha=0.15):
    b = FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                       boxstyle="round,pad=0.08",
                       facecolor=color, alpha=alpha,
                       edgecolor=color, lw=2)
    ax.add_patch(b)
    ax.text(x, y, text, ha="center", va="center",
            fontsize=fontsize, fontweight="bold" if bold else "normal",
            color=color)


def arrow(ax, x1, y1, x2, y2, color="#666", label=None, rad=0.0):
    a = FancyArrowPatch((x1, y1), (x2, y2),
                        arrowstyle="->", color=color, lw=1.8,
                        connectionstyle=f"arc3,rad={rad}")
    ax.add_patch(a)
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx + 0.15, my + 0.25, label, fontsize=7.5, color=color)


def main():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 7.5))
    fig.suptitle("Local Kubernetes Setup with kind",
                 fontsize=14, fontweight="bold")

    # ---- Panel 1: kind architecture ----
    ax1.set_xlim(0, 10)
    ax1.set_ylim(0, 10)
    ax1.set_title("kind Architecture (Docker-in-Docker)", fontsize=12, fontweight="bold")
    ax1.axis("off")

    # kubectl (client side)
    box(ax1, 1.5, 5.0, 2.4, 1.1, "kubectl", "#4C72B0")
    ax1.text(1.5, 3.9, "context:\nkind-k8s-learn", ha="center",
             fontsize=7.5, color="#4C72B0", style="italic")

    # Host machine boundary containing Docker + kind nodes
    host = FancyBboxPatch((3.6, 0.7), 6.0, 8.6,
                          boxstyle="round,pad=0.15",
                          facecolor="#f5f5f5", edgecolor="#999", lw=1.5, linestyle="--")
    ax1.add_patch(host)
    ax1.text(6.6, 8.85, "Host machine -- Docker", ha="center",
             fontsize=10, fontweight="bold", color="#666")

    # Node containers
    box(ax1, 6.6, 7.3, 4.6, 1.15,
        "control-plane container\n(apiserver, etcd, scheduler)", "#C44E52")
    box(ax1, 5.3, 4.7, 2.6, 1.15, "worker-1\n(kubelet, CNI)", "#55A868")
    box(ax1, 8.0, 4.7, 2.6, 1.15, "worker-2\n(kubelet, CNI)", "#55A868")

    # Pods inside workers
    ax1.text(5.3, 3.55, "Pods (nginx...)", ha="center", fontsize=7.5, color="#55A868")
    ax1.text(8.0, 3.55, "Pods", ha="center", fontsize=7.5, color="#55A868")

    # Arrows
    arrow(ax1, 2.75, 5.0, 4.2, 6.9, "#4C72B0", "kubectl apply")
    arrow(ax1, 6.6, 6.7, 6.0, 5.35, "#C44E52", "schedule")
    arrow(ax1, 6.9, 6.7, 7.7, 5.35, "#C44E52")
    arrow(ax1, 5.3, 4.1, 5.3, 3.9, "#55A868")
    arrow(ax1, 8.0, 4.1, 8.0, 3.9, "#55A868")

    ax1.text(5.0, 1.6, "Each 'node' is a regular Docker container;\n"
                       "inside it runs a real Kubernetes (kubeadm) node",
             ha="center", fontsize=9, color="#666", style="italic")

    # ---- Panel 2: setup flow ----
    ax2.set_xlim(0, 10)
    ax2.set_ylim(0, 10)
    ax2.set_title("setup.sh Flow", fontsize=12, fontweight="bold")
    ax2.axis("off")

    steps = [
        ("1. check deps", "#4C72B0",
         "docker / kubectl / kind installed?\ndocker daemon running?"),
        ("2. gen kind-config.yaml", "#DD8452",
         "heredoc writes cluster spec:\n1 control-plane + 2 worker nodes"),
        ("3. kind create cluster", "#55A868",
         "pull node images, start containers,\nkubeadm init, install CNI,\nset kubectl context (wait 120s)"),
        ("4. verify", "#8172B2",
         "kubectl get nodes -- Ready\nkubectl cluster-info\nkubectl wait --for=condition=Ready"),
        ("5. deploy test workload", "#C44E52",
         "kubectl create deployment nginx\nkubectl expose --NodePort\nrollout status -> pods,svc"),
    ]
    for i, (title, color, desc) in enumerate(steps):
        y = 8.6 - i * 1.95
        box(ax2, 5, y, 8.8, 1.5, "", color, alpha=0.08)
        ax2.text(5, y + 0.42, title, ha="center", fontsize=10,
                 fontweight="bold", color=color)
        ax2.text(5, y - 0.25, desc, ha="center", fontsize=8, color="#444")
        if i < len(steps) - 1:
            arrow(ax2, 5, y - 0.8, 5, y - 1.15, color)

    fig.tight_layout()
    path = os.path.join(SCRIPT_DIR, '..', 'images', 'setup_arch.png')
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {path}")


if __name__ == "__main__":
    main()
