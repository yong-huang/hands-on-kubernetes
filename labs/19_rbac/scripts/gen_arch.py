#!/usr/bin/env python3
"""RBAC 可视化: 权限模型四件套 + 请求鉴权流程, 生成 rbac_arch.png"""
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

BLUE, GREEN, ORANGE, RED, GRAY, PURPLE = "#4C78A8", "#54A24B", "#EE7A2D", "#E45756", "#999999", "#9D7BB0"

def box(ax, x, y, w, h, title, lines, fc, title_fs=10, fs=8.5):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.012",
                                fc=fc, ec="black", lw=1.1, alpha=0.85))
    ax.text(x + w/2, y + h - 0.055, title, ha="center", va="top",
            fontsize=title_fs, fontweight="bold")
    for i, ln in enumerate(lines):
        ax.text(x + w/2, y + h - 0.13 - i*0.055, ln, ha="center", va="top", fontsize=fs)

def arrow(ax, x1, y1, x2, y2, label="", color="black", style="-|>", lw=1.6, off=0.02):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style,
                                 mutation_scale=14, lw=lw, color=color))
    if label:
        ax.text((x1+x2)/2, (y1+y2)/2 + off, label, ha="center", fontsize=7.8,
                color=color, bbox=dict(fc="white", ec="none", pad=0.6))

# ============================ 图 1: RBAC 模型 ============================
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 7.2))

ax1.set_xlim(0, 1); ax1.set_ylim(0, 1); ax1.axis("off")
ax1.set_title("RBAC 模型: Subject → Binding → Role → Rules", fontsize=13, fontweight="bold")

# 左列: Subject
box(ax1, 0.03, 0.70, 0.26, 0.22, "Subject (身份)", ["ServiceAccount (进程)", "User (人)", "Group (组)"], BLUE)
# 中列: Binding
box(ax1, 0.37, 0.70, 0.26, 0.22, "RoleBinding", ["ns 级绑定", "subjects[] + roleRef"], GREEN)
# 右列: Role
box(ax1, 0.71, 0.70, 0.26, 0.22, "Role", ["规则集合", "(ns 内生效)"], ORANGE)

arrow(ax1, 0.29, 0.81, 0.37, 0.81, "subjects")
arrow(ax1, 0.63, 0.81, 0.71, 0.81, "roleRef")

# rules 展开
box(ax1, 0.71, 0.34, 0.26, 0.24, "rules[]", ["apiGroups: [\"\", apps]", "resources: [pods, pods/log,", "              deployments]", "verbs: [get list watch]"], ORANGE, fs=7.5)
arrow(ax1, 0.84, 0.70, 0.84, 0.58)

# 下方两列: namespaced vs cluster-scoped 对比
box(ax1, 0.03, 0.30, 0.45, 0.30, "namespaced 组合 (本项目)", [
    "RoleBinding (ns X) + Role (ns X)",
    "→ 权限仅 ns X 生效",
    "RoleBinding (ns X) + ClusterRole",
    "→ 规则复用, 仍仅 ns X 生效 (推荐)"], GREEN, fs=8)
box(ax1, 0.52, 0.30, 0.45, 0.30, "cluster-scoped 组合", [
    "ClusterRoleBinding + ClusterRole",
    "→ 权限在所有 ns 生效!",
    "适合: 集群管理员 / 监控组件",
    "慎用, 违反最小权限常见翻车点"], RED, fs=8)
arrow(ax1, 0.25, 0.70, 0.25, 0.60, "", GRAY, lw=1.2)
arrow(ax1, 0.75, 0.70, 0.75, 0.60, "", GRAY, lw=1.2)

box(ax1, 0.03, 0.04, 0.94, 0.20, "default-deny 语义", [
    "没有匹配 Subject 的 Binding / Binding 的 Role 里没有对应 rule -> 一律 Forbidden",
    "授权=白名单累加: 多个 Binding 权限取并集, RBAC 只能\"加\"不能\"减\"",
    "roleRef 创建后不可修改; subresource (pods/log) 必须在 resources 里单独授权"], GRAY, fs=8.5)

# ============================ 图 2: 请求鉴权流程 ============================
ax2.set_xlim(0, 1); ax2.set_ylim(0, 1); ax2.axis("off")
ax2.set_title("一次 kubectl 请求的鉴权流程", fontsize=13, fontweight="bold")

box(ax2, 0.02, 0.72, 0.20, 0.16, "kubectl", ["--as=system:serviceaccount", ":rbac-demo:dev-viewer", "get pods"], BLUE, fs=7.5)
box(ax2, 0.28, 0.66, 0.24, 0.28, "apiserver", ["① 认证 authn", "  身份是谁? (Token/证书)", "② 授权 authz (RBAC)", "  允许吗? 遍历 Binding", "③ 准入 admission", "  合规吗? (限值/策略)"], GREEN, fs=8)
box(ax2, 0.58, 0.72, 0.14, 0.16, "etcd", ["仅准入后写入"], GRAY)

arrow(ax2, 0.22, 0.80, 0.28, 0.80, "携带凭据")
arrow(ax2, 0.52, 0.80, 0.58, 0.80, "读写")

box(ax2, 0.02, 0.40, 0.34, 0.18, "kubectl auth can-i", ["自查工具 (SelfSubjectAccessReview)", "can-i get pods --as=<sa>", "返回 yes / no", "= 提前预演第②步, 不产生副作用"], PURPLE, fs=8)
arrow(ax2, 0.19, 0.58, 0.30, 0.66, "同样走完整鉴权链", PURPLE, lw=1.4)

box(ax2, 0.44, 0.40, 0.28, 0.18, "拒绝时返回", ["Error: Forbidden", "User \"...dev-viewer\" cannot", "get resource \"secrets\" in", "API group \"\" in ns \"rbac-demo\""], RED, fs=7.6)
arrow(ax2, 0.52, 0.66, 0.56, 0.58, "403", RED, lw=1.4)

box(ax2, 0.02, 0.06, 0.70, 0.24, "最小权限原则 (Least Privilege)", [
    "只授确实需要的 verbs/resources, ns 级 Role 优先于 ClusterRoleBinding",
    "CI 用只读 SA; 部署/管理分离成不同 SA; 内置 view/edit/admin 先复用再自写",
    "RBAC 管\"能不能调 API\"; Pod 安全 (PSA) 管容器权限, NetworkPolicy 管网络可达",
    "—— 三者互补, 作用层次不同"], ORANGE, fs=8.5)

plt.tight_layout()
plt.savefig('images/rbac_arch.png', dpi=150, bbox_inches="tight")
print("saved: rbac_arch.png")
