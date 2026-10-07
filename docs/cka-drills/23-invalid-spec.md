# CKA 开工包 · 项目 23：无效 Pod spec 排错

> 对应清单：`docs/cka.md` 项目 23 ｜ 环境：kind 集群 `k8s-learn` ｜ 实测日期：2026-10-06
> 先闭卷自做，再对照。

## 📝 题面（考场原题风格）

> `Task:` The manifest at `/root/bad-pod.yaml` fails to apply with multiple
> validation errors. Fix all errors so the pod applies and runs.
> Do not rewrite the manifest from scratch. (Weight: 4%)
>
> 目标用时：8 分钟

## 🧪 实测：报错优先级（三层揭开，2026-10-06）

清单含三处错误：缺 `metadata.name`、字段拼错 `images:`、`containerPort: "80"`（字符串）。
**报错不是一次性全出的，按优先级逐层揭开**：

```
第 1 层（缺 name，遮住一切）:
  error: ... "resource name may not be empty"
  ← kubectl apply 先按 name 去 GET 现有对象，name 为空直接失败

第 2 层（补上 name 后，类型错误优先于未知字段）:
  Error from server (BadRequest): json: cannot unmarshal string into
  Go struct field ContainerPort.spec.containers.ports.containerPort of type int32
  ← yaml→json 类型转换在 strict 字段校验之前

第 3 层（类型修完后）:
  strict decoding error: unknown field "images"   ← 字段拼错这时才报
```

修复动作（最小改动，呼应 do not rewrite）：

```bash
# ① metadata.name: bad-pod      （补）
# ② images: → image:            （sed 改字段名）
# ③ containerPort: "80" → 80    （去引号）
kubectl apply -f /root/bad-pod.yaml   # pod/bad-pod created
kubectl wait --for=condition=Ready pod/bad-pod --timeout=120s
```

## ⚠️ 五大丢分点

1. **缺 name 会遮住其他所有错误**：先补 name 再看下一层报错，别以为"就一个错"。
2. **类型错误读法**：`cannot unmarshal string into Go struct field X of type int32` —— 报错里的 Go 结构路径就是出错字段的 yaml 路径（`.spec.containers.ports.containerPort`），直接照着改。
3. **常见类型坑清单**：containerPort/端口号（int）、replicas（int）、`privileged: "true"`（bool 字符串，Norway 问题同源，见项目 12）。
4. **strict 校验是默认**：现代 kubectl apply 对未知字段直接报错（老版本只警告）；`--validate=false` 能跳过但考场别用——题目要的就是你读懂校验。
5. **`--dry-run=server` 的正确用法**：它做全量服务端校验，但**同样按优先级短路**——不是"一把列出所有错"，是"安全地试一遍"；修一层跑一次，循环推进。

## 🧹 重练

```bash
# 重建三错清单（缺 name / images 拼错 / 端口字符串），闭卷逐层修复
kubectl delete ns broken --now   # 用完删 namespace
```
