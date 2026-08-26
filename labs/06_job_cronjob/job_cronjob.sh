#!/usr/bin/env bash
# =============================================================================
# Kubernetes Job & CronJob 全流程演示脚本
# 覆盖: 一次性 Job -> 并行 Job(work queue) -> CronJob 手动触发 -> 失败排查 -> 清理
# 用法: ./job_cronjob.sh [step]
#   不带参数则依次执行全部步骤; 传 step 名(如 cronjob)只执行该步骤
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"   # 切到实验根目录, 使 manifests/ 相对路径生效

# ----------------------------- 全局配置 -----------------------------
NAMESPACE="default"              # 演示用的 namespace
ONE_SHOT="pi"                    # 一次性 Job 名称
PARALLEL="work-queue"            # 并行 Job 名称
CRON="db-backup"                 # CronJob 名称

# 打印步骤标题
step() { echo; echo "=====> [$1] $2"; }

# ----------------------------- 1. 一次性 Job -----------------------------
do_apply() {
    step "apply" "创建一次性 Job (perl 计算 pi, completions=1)"
    kubectl apply -f manifests/job_cronjob.yaml            # 声明式应用全部资源

    step "apply" "等待 Job 跑完 (kubectl wait 阻塞到 Complete)"
    kubectl wait --for=condition=complete "job/${ONE_SHOT}" \
        --timeout=120s -n "${NAMESPACE}"

    step "apply" "查看 Job 状态: COMPLETIONS 列 = 已成功数/总数"
    kubectl get jobs -n "${NAMESPACE}"

    step "apply" "查看计算结果 (Pod 日志, exit 0 => Pod 不再重启)"
    kubectl logs "job/${ONE_SHOT}" -n "${NAMESPACE}" | head -c 80; echo "..."
}

# ----------------------------- 2. 并行 Job (work queue) -----------------------------
do_parallel() {
    step "parallel" "观察 work-queue: completions=6, parallelism=2 (每批 2 个并行)"
    kubectl get pods -l "app=${PARALLEL}" -n "${NAMESPACE}" -w &
    watch_pid=$!                                 # 后台 watch, 稍后 kill 掉
    sleep 45; kill "${watch_pid}" 2> /dev/null || true

    step "parallel" "等待 6 个 Pod 全部成功 (分 3 批跑完)"
    kubectl wait --for=condition=complete "job/${PARALLEL}" \
        --timeout=180s -n "${NAMESPACE}"
    kubectl get jobs "${PARALLEL}" -n "${NAMESPACE}"   # COMPLETIONS 6/6
}

# ----------------------------- 3. CronJob 与手动触发 -----------------------------
do_cronjob() {
    step "cronjob" "查看 CronJob: SCHEDULE 列为 cron 表达式, SUSPEND=false"
    kubectl get cronjobs "${CRON}" -n "${NAMESPACE}"

    step "cronjob" "手动触发一次 (不等下一个整点, 从 CronJob 模板创建 Job)"
    kubectl create job "db-backup-manual" --from="cronjob/${CRON}" \
        -n "${NAMESPACE}"

    step "cronjob" "查看手动 Job 与其 Pod (会带 controller-uid 标签归属 CronJob)"
    kubectl wait --for=condition=complete "job/db-backup-manual" \
        --timeout=120s -n "${NAMESPACE}"
    kubectl get jobs -n "${NAMESPACE}"
    kubectl logs "job/db-backup-manual" -n "${NAMESPACE}"
}

# ----------------------------- 4. 失败与历史记录 -----------------------------
do_failure() {
    step "failure" "模拟失败: 跑一个必失败的 Job (exit 1)"
    kubectl delete job bad-job -n "${NAMESPACE}" --ignore-not-found
    kubectl create job bad-job --image=busybox:1.36 -n "${NAMESPACE}" \
        -- /bin/sh -c 'echo boom; exit 1'

    step "failure" "观察 backoff 重试: 新 Pod 按指数退避不断重建"
    sleep 30
    kubectl get pods -l "job-name=bad-job" -n "${NAMESPACE}"

    step "failure" "describe 失败 Pod: Events 里能看到退避重启与失败计数"
    pod=$(kubectl get pods -l "job-name=bad-job" -n "${NAMESPACE}" \
        -o jsonpath='{.items[0].metadata.name}')
    kubectl describe pod "${pod}" -n "${NAMESPACE}" | tail -20

    step "failure" "删除失败 Job, 再看 CronJob 保留的历史记录"
    kubectl delete job bad-job -n "${NAMESPACE}"
    kubectl get jobs -l "app=${CRON}" -n "${NAMESPACE}"
}

# ----------------------------- 5. 暂停与清理 -----------------------------
do_suspend() {
    step "suspend" "暂停 CronJob 调度 (suspend=true, 已在跑的 Job 不受影响)"
    kubectl patch cronjob "${CRON}" -p '{"spec":{"suspend":true}}' \
        -n "${NAMESPACE}"
    kubectl get cronjob "${CRON}" -n "${NAMESPACE}"   # SUSPEND 列变 true
}

do_clean() {
    step "clean" "删除本演示创建的所有资源 (忽略不存在的)"
    kubectl delete -f manifests/job_cronjob.yaml --ignore-not-found
    kubectl delete job db-backup-manual bad-job \
        -n "${NAMESPACE}" --ignore-not-found
    kubectl get jobs,cronjobs -n "${NAMESPACE}" || true
}

# ----------------------------- 入口: 按参数分发 -----------------------------
main() {
    local target="${1:-all}"
    case "${target}" in
        apply)    do_apply ;;
        parallel) do_parallel ;;
        cronjob)  do_cronjob ;;
        failure)  do_failure ;;
        suspend)  do_suspend ;;
        clean)    do_clean ;;
        all)
            do_apply; do_parallel; do_cronjob; do_failure; do_suspend; do_clean
            ;;
        *)
            echo "未知步骤: ${target}" >&2
            echo "可用: apply | parallel | cronjob | failure | suspend | clean | all" >&2
            exit 1
            ;;
    esac
}

main "$@"
