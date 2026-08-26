#!/usr/bin/env python3
"""Vault 动态凭证注入可视化: 传统静态 Secret vs CSI 动态注入 对比 + 租约生命周期"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("Secrets 管理: Vault 动态凭证 vs 静态 K8s Secret", fontsize=16, fontweight="bold")

# ============================ Panel 1: 两条路径对比 ============================
ax1.set_title("静态 Secret(反面教材) vs Vault 动态注入", fontsize=13)
# 左列: 静态
ax1.add_patch(mpatches.FancyBboxPatch((0.4, 7.6), 3.4, 1.2,
              boxstyle="round,pad=0.08", fc="#d62728", ec="black"))
ax1.text(2.1, 8.2, "kubectl create secret\n明文写进 Git / CI", ha="center",
         va="center", fontsize=9.5, color="white")
ax1.add_patch(mpatches.FancyBboxPatch((0.4, 5.4), 3.4, 1.2,
              boxstyle="round,pad=0.08", fc="#e6884d", ec="black"))
ax1.text(2.1, 6.0, "存进 etcd\n(备份/审计/泄漏面大)", ha="center",
         va="center", fontsize=9.5, color="white")
for y in (7.55, 5.35):
    ax1.annotate("", xy=(2.1, y), xytext=(2.1, y + 0.6),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5, color="#d62728"))
ax1.text(2.1, 4.4, "永不轮换 / 离职不回收\n密码出现在无数备份里",
         ha="center", fontsize=9, color="#d62728")

# 右列: Vault CSI
vault_steps = [
    (5.9, "Pod 挂载 CSI 卷\n引用 SecretProviderClass", "#aec7e8"),
    (4.35, "CSI Driver 用 SA Token\n向 Vault 做 K8s Auth 换 token", "#1f77b4"),
    (2.8, "Vault 数据库引擎\n动态生成临时凭证(TTL 1h)", "#2ca02c"),
    (1.25, "凭证以文件挂入容器\n+ 同步为原生 Secret", "#9467bd"),
]
for cy, txt, c in vault_steps:
    ax1.add_patch(mpatches.FancyBboxPatch((4.6, cy - 0.55), 4.9, 1.15,
                  boxstyle="round,pad=0.07", fc=c, ec="black"))
    ax1.text(7.05, cy, txt, ha="center", va="center", fontsize=9,
             color="white" if c != "#aec7e8" else "black")
for i in range(3):
    y1 = vault_steps[i][0] - 0.6
    ax1.annotate("", xy=(7.05, y1 - 0.85), xytext=(7.05, y1),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5))
ax1.text(7.05, 0.45, "Pod 销毁 -> 租约自动吊销 -> 凭证从数据库消失",
         ha="center", fontsize=9, color="#2ca02c")

ax1.plot([4.25, 4.25], [0, 9.4], ls="--", color="gray", lw=1)
ax1.set_xlim(0, 10); ax1.set_ylim(0, 9.4); ax1.axis("off")

# ============================ Panel 2: 租约生命周期 ============================
ax2.set_title("动态凭证租约生命周期 (database/creds/*)", fontsize=13)
timeline = [
    (0.5, 8.6, "Pod 申请挂载", "#aec7e8"),
    (3.2, 8.6, "Vault 创建租约\n生成 user_xxx / pwd_yyy", "#2ca02c"),
    (6.6, 8.6, "TTL 到期前\nrenew_period 自动续租", "#ff7f0e"),
    (8.8, 8.6, "max_ttl 强制过期\n或 Pod 删除 -> revoke", "#d62728"),
]
for cx, cy, txt, c in timeline:
    w = 1.9 if cx != 3.2 else 2.6
    ax2.add_patch(mpatches.FancyBboxPatch((cx - w / 2 if cx != 3.2 else 3.2 - 1.3, cy - 0.65),
                  w, 1.3, boxstyle="round,pad=0.08", fc=c, ec="black", alpha=0.92))
    ax2.text(cx if cx != 3.2 else 3.2, cy, txt, ha="center", va="center",
             fontsize=8.8, color="white")
ax2.annotate("", xy=(3.2, 8.6), xytext=(1.5, 8.6), arrowprops=dict(arrowstyle="-|>", lw=1.6))
ax2.annotate("", xy=(5.3, 8.6), xytext=(4.5, 8.6), arrowprops=dict(arrowstyle="-|>", lw=1.6))
ax2.annotate("", xy=(7.85, 8.6), xytext=(6.6, 8.6), arrowprops=dict(arrowstyle="-|>", lw=1.6))

# 轮换效果示意: 用户名随 Pod 重建变化
rows = [("pod-a", 3, "db_user_7f2a"), ("pod-b (重建)", 2, "db_user_c91d"),
        ("pod-c (再重建)", 1, "db_user_04be")]
ax2.text(1.1, 5.6, "每次重建拿到的是不同凭证:", fontsize=10, fontweight="bold")
for name, y, cred in rows:
    ax2.add_patch(mpatches.FancyBboxPatch((0.7, y * 1.35 - 0.05), 8.0, 0.95,
                  boxstyle="round,pad=0.06", fc="#f5f5f5", ec="#999"))
    ax2.text(1.0, y * 1.35 + 0.42, f"{name}", fontsize=9.5)
    ax2.text(4.6, y * 1.35 + 0.42, cred, fontsize=9.5, family="monospace")
    ax2.text(8.0, y * 1.35 + 0.42, "旧租约已吊销", fontsize=8.5, color="#2ca02c")

ax2.text(5.0, 0.55, "安全收益: 泄漏的只是一组已过期的临时账号 —— 攻击者拿它连不上数据库",
         ha="center", fontsize=10, color="#d62728", fontweight="bold")
ax2.set_xlim(0, 10); ax2.set_ylim(0, 9.6); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/vault_secrets_arch.png', dpi=150, bbox_inches="tight")
print("saved vault_secrets_arch.png")
