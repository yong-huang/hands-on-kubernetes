#!/usr/bin/env bash
# 项目 22 判分脚本：四大故障态全部修复为 Running/Ready 计 1 分
NS=broken; PASS=0
for p in bad-image bad-cmd stuck-pending oom-loop; do
  S=$(kubectl -n $NS get pod $p -o jsonpath='{.status.phase}' 2>/dev/null)
  R=$(kubectl -n $NS get pod $p -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$S" = "Running" ] && [ "$R" = "true" ]; then echo "✅ $p"; PASS=$((PASS+1)); else echo "❌ $p ($S)"; fi
done
echo "得分: $PASS/4"; [ $PASS -eq 4 ]
