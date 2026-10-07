# CKA 开工包 · 项目 29：日志、事件与资源监控排障

> 对应清单：`docs/cka.md` 项目 29 ｜ 环境：kind 集群 `k8s-learn`（**metrics-server 已预装**，helm 重装反而报 APIService 所有权错——先查再装！）｜ 实测日期：2026-10-07
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` Pod `flaky` in namespace `apps` has restarted 3 times. Determine the
> cause of the restarts using logs and events, and write your conclusion to
> `/root/report.md`. Also identify the pod consuming the most CPU in the
> cluster. (Weight: 5%)
>
> 目标用时：10 分钟

## ✅ 实测：OOM 证据链四件套（2026-10-07）

```bash
# 构造：Always 策略 + 4Mi limit + dd 8M → 必 OOM 循环
kubectl -n apps create deployment flaky2 --image=busybox:1.36 -- sh -c "dd if=/dev/zero of=/dev/null bs=8M"
kubectl -n apps set resources deploy/flaky2 --limits=memory=4Mi
sleep 45
kubectl -n apps get pod -l app=flaky2     # OOMKilled RESTARTS:3 ✅

# 证据①：重启计数
kubectl -n apps get pod $P --no-headers    # RESTARTS 上涨（实测 3）
# 证据②：exit code 137（describe 的 Last State 段）
kubectl -n apps describe pod $P | grep -E "Last State:|Reason:|Exit Code:"
#   Reason: OOMKilled   Exit Code: 137
# 证据③：logs --previous（崩溃前 stdout）
kubectl -n apps logs $P --previous
# 证据④：事件流
kubectl -n apps describe pod $P | grep -A5 Events
# 考场动作：结论落盘
echo "flaky restarted due to OOMKilled (exit 137); limit 4Mi too low" > /root/report.md
```

## 🧪 实测发现的三个细节

1. **`--previous` 需要 restartPolicy: Always**：裸 Pod（`kubectl run --restart=Never`）OOM 后停在 OOMKilled 不重启，**没有"上一轮"**，`logs --previous` 直接报 `previous terminated container not found`——此时当前容器（terminated）的 `logs` 不带 previous 就能取。要演示 RESTARTS 上涨必须用 Deployment/Job。
2. **`--previous` 可能为空**：崩溃前进程没写过 stdout/stderr 时（如 dd 被静默杀），containerd 无日志可取，报 `unable to retrieve container logs for containerd://...`——不是命令错了，改用 describe 的 exit code 证据。
3. **metrics-server 先查后装**：`kubectl top pod -A` 能出数据就别装；helm 重装报 `APIService v1beta1.metrics.k8s.io ... ownership metadata` 错（已存在的对象无 helm 接管注解）——考场环境全部预装，本题不需要装。

## 🧰 考场命令速查

```bash
kubectl logs <pod> [-c <ctr>] [--previous] [--tail=N]        # 应用日志
kubectl describe pod <pod> | grep -A10 Events                # 事件（Events 段）
kubectl get events -A --sort-by=.lastTimestamp | tail        # 全集群事件按时间
kubectl top pod -A --sort-by=cpu | head                      # 最耗 CPU（实测 flaky 1000m 榜首）
kubectl top node                                             # 节点水位
crictl ps -a / crictl logs <cid>                             # 节点级容器排查（killercoda 场景）
exit code: 137=OOM(SIGKILL) 143=SIGTERM 1=应用自身错误        # 速记
```

## ⚠️ 五大丢分点

1. **结论不落盘**：题目让写 `/root/report.md` 就必须写文件，判分脚本 cat 文件——只说在嘴上=0 分。
2. **证据链不闭环**：RESTARTS 计数 + Last State exit code + 日志，三取二才算"确定了原因"。
3. **top 没数据就慌**：metrics-server 起动要 1-2 分钟，考场预装通常就绪；若真没数据，`describe node` 的 Allocated resources 段是备胎。
4. **sort-by 字段名**：`--sort-by=.lastTimestamp`（带点）、CPU 用 `--sort-by=cpu`——写错静默不排序。
5. **把 events 当唯一真相**：事件 1 小时过期，老问题查事件可能什么都查不到——`describe` 拿当前状态 + 日志补时间线。

## 🧹 重练

```bash
kubectl -n apps delete deploy flaky2 --now
```
