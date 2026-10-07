# CKA 开工包 · 项目 30：🏋️ 综合故障注入限时排障

> 对应清单：`docs/cka.md` 项目 30 ｜ 环境：cka-netpol 靶场（Calico 真执行 NP）｜ 实测日期：2026-10-07
> **域 5 收官战**：五个故障 = 项目 14/21/22/11/16/24 的综合复刻。工具已沉淀，一键开战。

## 🧰 开战流程（60 分钟限时）

```bash
# 1. 注入（约 2 分钟，结束后计时开始）
bash docs/cka-drills/scripts/chaos-30.sh          # 默认 kind-cka-netpol
# 2. 闭卷排障（不许看下面答案！get pods/events/describe/netpol 全靠条件反射）
# 3. 随时判分（重复跑无副作用）
bash docs/cka-drills/scripts/verify-30.sh
# 目标: 60 分钟内 5/5；每故障 12 分钟封顶，卡住先跳
```

## 🗺️ 五故障图谱（修复后对照，先别看！）

| # | 命名空间 | 故障 | 复刻自 | 最小修法 |
|:--|:---|:---|:---|:---|
| F1 | shop/web | 镜像 tag 不存在 → ImagePullBackOff | 22 | `set image deploy/web busybox=busybox:1.36`（容器名=镜像名！） |
| F2 | shop/api-svc | svc selector 改坏 → ep 空 | 14 | patch selector 回 `app=api`（题目若禁改 deploy 就改 svc） |
| F3 | shop/probe | 双探针指向不存在的 /ready → 404 循环重启 | 11 | patch 双探针 path 到真实存在的 `/` |
| F4 | shop/data-claim | storageClassName=faast 不存在 → PVC/Pod 双 Pending | 21 | **PVC spec immutable → 删了重建**（不带 SC 名走默认） |
| F5 | pay/cache | NP 放行端口写成 9999（实际 8080） | 16/24 | patch NP 端口（json patch replace）或加规则 |

## 🧪 实测记录（2026-10-07）

- 注入后判分 **0/5**（F1 ErrImagePull / F2 ep 空 / F3 CrashLoop+NotReady / F4 双 Pending / F5 wget timeout），全部生效。
- 限时修复后 **5/5**。真实耗时节奏：F1/F2/F5 均一次命中，F4 因 immutable patch 被拒多花一轮，F5 第一次 patch 端口后仍不通——排查出**注入脚本自身把 client 的白名单标签漏了**（第二故障），贴标签后过。
- **工具开发期的三个坑（已在脚本修正）**：
  1. `kubectl set probe` 在部分 kubectl 版本没有 `--readiness` flag → 注入探针一律用 patch template（注意容器名=镜像名 busybox）；
  2. verify 里用 `kubectl run --rm -i` 临时 Pod 测连通**不稳定**（启动竞态）→ 固定 client Pod + exec 最可靠；
  3. 故障注入脚本本身也可能有 bug——verify 不过先怀疑现场再怀疑工具，与考场"先查环境再查答案"同理。

## ⚠️ 考场时间策略（60 分钟版）

1. 开场 3 分钟 `kubectl get pod -A` + `get events -A --sort-by=.lastTimestamp` 全景扫描，把 5 个故障按"一眼可修"排序。
2. 每题 12 分钟封顶，卡住标记跳过——F1/F2 这类秒修先拿分。
3. 修一处跑一次 verify 对应项（判分脚本无副作用，可反复跑）。
4. 全部修完留 5 分钟复查：`get pod -A` 无异常态、`verify` 5/5。

## 🧹 重练

```bash
bash docs/cka-drills/scripts/chaos-30.sh   # 幂等：每次注入前自动清空 shop/pay
```
