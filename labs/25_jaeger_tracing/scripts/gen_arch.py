#!/usr/bin/env python3
"""分布式追踪可视化: trace/span 瀑布模型 + context 传播与采样"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(SCRIPT_DIR, '..'))

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"]
plt.rcParams["axes.unicode_minus"] = False

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
fig.suptitle("分布式追踪: Trace/Span 模型 与 Jaeger 数据流", fontsize=16, fontweight="bold")

# ============================ Panel 1: Trace 瀑布图 ============================
ax1.set_title("一次请求的 Trace 瀑布图 (总耗时 182ms)", fontsize=13)
spans = [
    ("svc-front  GET /", 0.0, 182, 0, "#1f77b4"),
    ("svc-order  POST /order", 12, 150, 1, "#2ca02c"),
    ("auth-check", 14, 18, 2, "#8c564b"),
    ("svc-payment  /pay", 60, 95, 2, "#ff7f0e"),
    ("db INSERT", 100, 40, 3, "#9467bd"),
    ("emit event", 145, 6, 3, "#7f7f7f"),
]
for name, start, dur, depth, c in spans:
    y = len(spans) - 1 - spans.index((name, start, dur, depth, c))
    ax1.barh(y, dur, left=start, height=0.62, color=c, alpha=0.88, ec="black")
    ax1.text(start + dur + 3, y, f"{dur}ms", va="center", fontsize=9)
    ax1.text(1, y, "  " * depth + name, va="center", ha="left", fontsize=9.5)
for i in range(len(spans) - 1):
    pass
# parent-child 连线
links = [(5, 4), (4, 2), (4, 3), (3, 1)]
for pa, ch in links:
    ya = len(spans) - 1 - pa; yc = len(spans) - 1 - ch
    x_end = spans[pa][1] + spans[pa][2]
    ax1.plot([spans[ch][1], spans[ch][1]], [ya - 0.31, yc + 0.31],
             color="#555", lw=1, ls=":")
ax1.set_xlabel("时间 (ms)")
ax1.set_yticks([])
ax1.grid(axis="x", alpha=0.25)
ax1.text(95, -0.9, "span 嵌套 = 调用栈; 宽度 = 自身耗时; 缩进深度 = 调用层级",
         fontsize=9.5, color="gray")
ax1.set_xlim(0, 260); ax1.set_ylim(-1.4, len(spans))

# ============================ Panel 2: 数据流与传播 ============================
ax2.set_title("Jaeger 链路数据流: W3C traceparent 头透传是关键", fontsize=13)
boxes = [
    (1.7, 8.4, "client (front 内置流量线程)\n发起请求生成 trace-id", "#aec7e8"),
    (5.0, 8.4, "svc-front\nOTel agent 建 span", "#1f77b4"),
    (8.3, 8.4, "svc-order -> svc-payment\n逐跳透传 header 建 span", "#2ca02c"),
    (8.3, 5.2, "OTLP gRPC :4317\n批量异步上报", "#ff7f0e"),
    (5.0, 5.2, "Jaeger Collector\n校验/入库", "#d62728"),
    (1.7, 5.2, "存储 (内存/ES)\n按 trace-id 索引", "#9467bd"),
    (1.7, 2.2, "Jaeger Query UI :16686\n按 service/耗时检索瀑布图", "#f5a623"),
]
for cx, cy, txt, c in boxes:
    ax2.add_patch(mpatches.FancyBboxPatch((cx - 1.45, cy - 0.65), 2.9, 1.3,
                  boxstyle="round,pad=0.08", fc=c, ec="black", alpha=0.92))
    tcol = "black" if c == "#f5a623" else "white"
    ax2.text(cx, cy, txt, ha="center", va="center", fontsize=8.6, color=tcol)
flow = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)]
for a, b in flow:
    x1, y1 = boxes[a][0], boxes[a][1]
    x2, y2 = boxes[b][0], boxes[b][1]
    if a == 2 and b == 3: x1, y1, x2, y2 = 8.3, 7.75, 8.3, 5.85
    elif a == 1 and b == 2: x1, y1, x2, y2 = 3.15, 8.4, 6.85, 8.4
    elif a == 0 and b == 1: x1, y1, x2, y2 = 1.7, 7.75, 3.55, 8.15
        # 斜向
    ax2.annotate("", xy=(x2, y2), xytext=(x1, y1),
                 arrowprops=dict(arrowstyle="-|>", lw=1.5,
                                 connectionstyle="arc3,rad=0"))
ax2.text(5.0, 6.85, "HTTP header:\n00-<trace-id>-<span-id>-01",
         ha="center", fontsize=9, family="monospace", color="#333",
         bbox=dict(boxstyle="round", fc="#fff8e1", ec="#f5a623"))
ax2.annotate("", xy=(6.85, 7.9), xytext=(5.6, 7.35),
             arrowprops=dict(arrowstyle="-|>", lw=1.2, ls="--"))

ax2.add_patch(mpatches.FancyBboxPatch((4.0, 0.4), 5.6, 1.3,
              boxstyle="round,pad=0.08", fc="#f5f5f5", ec="#999"))
ax2.text(6.8, 1.05, "自动埋点: OTel Operator 注入 python agent (init 容器), 注解\ninstrumentation.opentelemetry.io/inject-python; 本实验全量采样, 生产常用 1~10%",
         ha="center", va="center", fontsize=8.8)

ax2.set_xlim(-0.2, 10); ax2.set_ylim(0.2, 9.4); ax2.axis("off")

plt.tight_layout(rect=[0, 0, 1, 0.94])
plt.savefig('images/jaeger_tracing_arch.png', dpi=150, bbox_inches="tight")
print("saved jaeger_tracing_arch.png")
