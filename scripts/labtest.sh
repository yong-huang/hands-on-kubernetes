#!/usr/bin/env bash
# labs 全量回归 runner：逐个跑 32 个实验脚本，超时保护 + 汇总
# 用法: ./scripts/labtest.sh [NN ...]   （缺省全部）
set -uo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/mart/kubeconfig-kind}"
OUT=/tmp/labtest
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"

# macOS 无 timeout 命令；perl alarm 会在 exec 后失效，改用后台+轮询强杀
run_timeout() {
    local tmo="$1"; shift
    "$@" &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$tmo" ]; do
        sleep 5; waited=$((waited+5))
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo "  [runner] 超时 ${tmo}s，强杀进程树" >&2
        pkill -9 -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        return 124
    fi
    wait "$pid"
}

wait_api() {  # 集群 API 预检：宿主机 API 会周期性抽风，最长等 15 分钟
    local i=0
    until kubectl --request-timeout=10s get nodes >/dev/null 2>&1; do
        i=$((i+15)); [ "$i" -ge 900 ] && return 1
        echo "  [runner] API 不可达，${i}s..." >&2
        sleep 15
    done
    return 0
}

run_lab() {  # $1=NN $2=脚本相对路径 $3=超时秒 $4=入口参数
    local nn="$1" script="$2" tmo="${3:-600}" entry="${4:-}"
    echo "[$(date +%H:%M:%S)] LAB $nn ($entry, timeout=${tmo}s)" >&2
    wait_api || { echo "FAIL $nn (API 持续不可达)" >> "$SUMMARY"; return 0; }
    if run_timeout "$tmo" bash "$script" $entry >"$OUT/$nn.log" 2>&1; then
        echo "PASS $nn" >> "$SUMMARY"
        return 0
    fi
    # 失败重试一次：可能是撞上宿主机 API 抽风窗口
    echo "  [runner] $nn 失败，等待 API 稳定后重试一次" >&2
    wait_api || { echo "FAIL $nn (exit=$?, 重试前 API 不可达)" >> "$SUMMARY"; return 0; }
    if run_timeout "$tmo" bash "$script" $entry >"$OUT/$nn.retry.log" 2>&1; then
        echo "PASS $nn (重试)" >> "$SUMMARY"
    else
        echo "FAIL $nn (exit=$?, 重试后仍失败)" >> "$SUMMARY"
    fi
}

# 特殊：01 会重建集群，跳过 up，只做健康核查
check_01() {
    wait_api || { echo "FAIL 01 (集群不可用)" >> "$SUMMARY"; return; }
    if kubectl get nodes 2>/dev/null | grep -q Ready; then
        echo "PASS 01 (跳过重建集群，仅健康核查)" >> "$SUMMARY"
    else
        echo "FAIL 01 (集群不可用)" >> "$SUMMARY"
    fi
}

check_01
for d in labs/*/; do
    nn=$(basename "$d" | cut -d_ -f1)
    [ "$nn" = "01" ] && continue
    script=$(ls "$d"*.sh 2>/dev/null | head -1)
    [ -z "$script" ] && { echo "SKIP $nn (无脚本)" >> "$SUMMARY"; continue; }
    case "$nn" in
        13|18|22|23|24|25|27|28|30) tmo=1800 ;;
        *) tmo=900 ;;
    esac
    # 入口约定：动词型脚本传 all；命名空间型线性脚本不传参（默认 default ns）
    case "$nn" in
        13|21|22|23|24|25|26|27|28|29|30|31) entry=all ;;
        *) entry="" ;;
    esac
    run_lab "$nn" "$script" "$tmo" $entry
    # 每个 lab 后确认集群仍健康（被某 lab 打挂就停下报错）
    if ! wait_api; then
        echo "ABORT $nn 之后集群不可用（等 15 分钟未恢复）" >> "$SUMMARY"
        break
    fi
done

echo "========== labs 回归汇总 =========="
cat "$SUMMARY"
