#!/usr/bin/env bash
# 项目 30 综合限时排障 · 判分脚本
# 用法: bash verify-30.sh [context]     # 默认 kind-cka-netpol
# 判分: 5 项各 1 分，全部通过输出 5/5（无 NP 执行能力的集群 F5 恒失败属正常）
set -u
CTX="${1:-kind-cka-netpol}"
kubectl config use-context "$CTX" >/dev/null
PASS=0

S=$(kubectl -n shop get pod -l app=web -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c Running)
if [ "${S:-0}" -ge 1 ]; then echo "✅ F1 shop/web 镜像已修复"; PASS=$((PASS+1)); else echo "❌ F1 shop/web 仍有 pod 非 Running"; fi

EP=$(kubectl -n shop get ep api-svc -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
CLI=$(kubectl -n shop get pod -l app=client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$EP" ] && [ -n "$CLI" ] && kubectl -n shop exec "$CLI" -- wget -qO- -T 3 http://api-svc 2>/dev/null | grep -q api-ok; then
  echo "✅ F2 api-svc 端点与流量恢复"; PASS=$((PASS+1))
else echo "❌ F2 api-svc 仍不可达"; fi

R=$(kubectl -n shop get pod -l app=probe -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
if [ "$R" = "true" ]; then echo "✅ F3 probe 探针通过且 Ready"; PASS=$((PASS+1)); else echo "❌ F3 probe 仍未 Ready"; fi

B=$(kubectl -n shop get pvc data-claim -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$B" = "Bound" ]; then echo "✅ F4 data-claim 已 Bound"; PASS=$((PASS+1)); else echo "❌ F4 data-claim 仍 Pending"; fi

if kubectl -n pay get pod -l app=client -o name 2>/dev/null | grep -q . && \
   kubectl -n pay exec $(kubectl -n pay get pod -l app=client -o jsonpath='{.items[0].metadata.name}') -- wget -qO- -T 3 http://cache-svc 2>/dev/null | grep -q cache-ok; then
  echo "✅ F5 pay/cache 流量恢复"; PASS=$((PASS+1))
else echo "❌ F5 pay/cache 仍不通"; fi

echo ""
echo "得分: $PASS/5"
[ "$PASS" -eq 5 ] && echo "🏆 全部修复！" || echo "还有 $((5-PASS)) 处未修复，继续。"
exit $((5-PASS))
