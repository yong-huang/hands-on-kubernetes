#!/usr/bin/env python3
"""镜像安全可视化: 供应链签名/扫描流水线 + Kyverno 准入决策流"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("镜像安全与漏洞扫描: 供应链流水线 与 准入拦截", fontsize=16, fontweight="bold")

# ============================ Panel 1: 供应链流水线 ============================
ax1.set_title("镜像供应链: 构建到运行的安全卡点", fontsize=13)
stages = [
    (0.6, "CI 构建", "#aec7e8", ["Dockerfile 多阶段构建", "最小基础镜像 distroless"]),
    (2.5, "Trivy 扫描", "#ff7f0e", ["CI 内 pre-scan", "阻断 Critical CVE"]),
    (4.4, "Cosign 签名", "#2ca02c", ["keyless / KMS 密钥", "attest SBOM 附件"]),
    (6.3, "私有 Registry", "#9467bd", ["不可变 tag", "保留扫描元数据"]),
]
for x, name, c, items in stages:
    ax1.add_patch(mpatches.FancyBboxPatch((x - 0.85, 7.3), 1.7, 1.9,
                  boxstyle="round,pad=0.08", fc=c, ec="black", alpha=0.88))
    ax1.text(x, 8.75, name, ha="center", fontsize=11, fontweight="bold", color="white")
    ax1.text(x, 7.95, "\n".join(items), ha="center", va="center", fontsize=7.8, color="white")
for i in range(3):
    x1 = stages[i][0] + 0.9
    ax1.annotate("", xy=(stages[i + 1][0] - 0.9, 8.25), xytext=(x1, 8.25),
                 arrowprops=dict(arrowstyle="-|>", lw=1.6))

# 运行侧: 准入 + 运行时
ax1.add_patch(mpatches.FancyBboxPatch((0.6 - 0.85, 4.6), 8.05, 1.7,
              boxstyle="round,pad=0.08", fc="#1f77b4", ec="black"))
ax1.text(4.6, 5.95, "Kubernetes 准入层 (Kyverno)", ha="center",
         fontsize=12, fontweight="bold", color="white")
ax1.text(4.6, 5.15, "verifyImages: cosign 公钥验签   |   deny-critical: 结合漏洞报告拦截",
         ha="center", va="center", fontsize=8.5, color="white")
ax1.annotate("", xy=(4.6, 6.35), xytext=(4.6, 7.25),
             arrowprops=dict(arrowstyle="-|>", lw=1.6))
ax1.add_patch(mpatches.FancyBboxPatch((2.9, 2.4), 3.4, 1.3,
              boxstyle="round,pad=0.08", fc="#d62728", ec="black", alpha=0.9))
ax1.text(4.6, 3.05, "Pod 运行\n(仅已签名且无高危漏洞的镜像)",
         ha="center", va="center", fontsize=9.5, color="white")
ax1.annotate("", xy=(4.6, 3.75), xytext=(4.6, 4.55),
             arrowprops=dict(arrowstyle="-|>", lw=1.6))

# 运行时闭环
ax1.add_patch(mpatches.FancyBboxPatch((0.6, 0.4), 8.05, 1.2,
              boxstyle="round,pad=0.08", fc="#8c564b", alpha=0.85))
ax1.text(4.6, 1.0, "Trivy Operator 常驻集群: 持续重扫在跑镜像 -> VulnerabilityReport CRD -> 联动策略/告警",
         ha="center", va="center", fontsize=8.8, color="white")

ax1.set_xlim(-0.5, 9.6); ax1.set_ylim(0, 9.6); ax1.axis("off")

# ============================ Panel 2: 准入决策 ============================
ax2.set_title("Kyverno verifyImages 准入决策", fontsize=13)
flow = [
    (2.6, 8.7, "Pod 创建请求\nimage: registry.example.com/*", "#aec7e8"),
    (2.6, 7.0, "匹配 verify-image-signatures 规则", "#1f77b4"),
    (2.6, 5.3, "cosign verify\n(用 ClusterPolicy 内置公钥)", "#2ca02c"),
]
for cx, cy, txt, c in flow:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 1.9, cy - 0.65), 3.8, 1.3,
                  boxstyle="round,pad=0.08", fc=c, ec="black"))
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=9.5,
             color="white" if c != "#aec7e8" else "black")
for y in (8.05, 6.35):
    ax2.annotate("", xy=(2.6, y), xytext=(2.6, y + 0.7),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5))

res = [
    (0.85, 3.2, "签名无效", "#d62728", "拒绝\nEvent 记录 PolicyViolation"),
    (2.6, 3.2, "签名有效", "#2ca02c", "进入下一规则"),
    (4.35, 3.2, "无签名", "#e6b800", "拒绝\n(Enforce 模式)"),
]
for cx, cy, head, c, body in res:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 0.72, cy - 0.55), 1.44, 1.1,
                  boxstyle="round,pad=0.06", fc=c, ec="black", alpha=0.9))
    ax2.text(cx, cy + 0.22, head, ha="center", fontsize=9.5, color="white", fontweight="bold")
    ax2.text(cx, cy - 0.25, body, ha="center", va="center", fontsize=7.2, color="white")
for cx in (0.85, 2.6, 4.35):
    rad = {"0.85": "-0.4", "2.6": "0", "4.35": "0.4"}[str(cx)]
    ax2.annotate("", xy=(cx, 3.8), xytext=(2.6, 4.6),
                 arrowprops=dict(arrowstyle="-|>", lw=1.3, connectionstyle=f"arc3,rad={rad}"))

ax2.add_patch(mpatches.FancyBboxPatch((0.5, 0.6), 4.7, 1.5,
              boxstyle="round,pad=0.1", fc="#f5f5f5", ec="#1f77b4", ls="--"))
ax2.text(2.85, 1.75, "灰度上线建议", ha="center", fontsize=10, fontweight="bold")
ax2.text(2.85, 1.0, "validationFailureAction:\n  Audit (观察) -> Enforce (强制)\nexclude: kube-system 等系统命名空间",
         ha="center", va="center", fontsize=8)

ax2.set_xlim(0, 5.6); ax2.set_ylim(0, 9.6); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/image_security_arch.png', dpi=150, bbox_inches="tight")
print("saved image_security_arch.png")
