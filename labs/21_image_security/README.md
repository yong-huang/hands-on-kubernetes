# 21 · 镜像安全与漏洞扫描：Trivy、Cosign 与 Kyverno 三层防线

> 容器逃逸、供应链投毒是 K8s 生产环境最常见的攻击面。本实验搭建三层防线：**Trivy Operator 持续扫描**在跑镜像并生成 `VulnerabilityReport` CRD；**Cosign** 给镜像签名保证来源可信；**Kyverno 准入策略**在 Pod 创建时验签 + 拦截含 Critical 漏洞的镜像——目标是让"带高危漏洞的镜像无法部署"成为集群的默认行为而非事后补救。

## What

| 防线 | 工具 | 时机 | 作用 |
|------|------|------|------|
| 漏洞扫描 | Trivy Operator | 持续（watch 运行中镜像） | 生成 VulnerabilityReport CRD |
| 来源可信 | Cosign | 构建后 | 给镜像签名，防止被篡改 |
| 准入拦截 | Kyverno | Pod 创建时 | verifyImages 验签 + deny 拦 Critical 漏洞镜像 |

一句话心智模型：**扫描管"已知漏洞"、签名管"内容没被篡改"、准入管"不合格的进不来"**——三者合起来把镜像供应链的卡点从"人肉检查"变成集群默认行为。

## Why

镜像是从 registry 拉的一坨不透明字节：基础层里藏着哪个 CVE、构建过程中有没有被塞私货，运行起来之前无从知晓。等漏洞进了集群再"发现-修复-重发"，攻击窗口已经打开。把检查前移到准入路径（有漏洞/没签名就拒绝创建）、再配合持续重扫盯住"部署后新曝光的 CVE"，才能把供应链风险收敛成可观测、可强制的工作流。

## How

```bash
cd labs/21_image_security
./image_security.sh scan     # 安装 Trivy Operator，等待 VulnerabilityReport 生成
./image_security.sh policy   # 以 Audit 模式安装 Kyverno 拦截策略，观察违规面
./image_security.sh deny     # patch 切到 Enforce，演示 nginx:1.14.x 被准入拒绝
./image_security.sh clean
```

安装 Trivy Operator：

```bash
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --set trivy.ignoreUnfixed=true \
  --set trivy.dbRegistry=<DB_REGISTRY>   # 见下方"国内网络"说明
```

扫描产物是标准化 CRD，数据结构即接口：

```yaml
report.summary: {criticalCount: 3, highCount: 11, ...}
report.vulnerabilities[0]: {vulnerabilityID: CVE-2019-9511, fixedVersion: "1.25.3"}
```

Kyverno 验签与拦截策略（`manifests/image_security.yaml`）：

```yaml
verifyImages:
  - imageReferences: ["registry.example.com/*"]
    attestors:
      - entries:
          - keys: {publicKeys: ...}
```

```yaml
validate:
  foreach:
    - list: "request.object.spec.containers"
      deny:
        conditions:
          any:
            - key: "{{ regex_match('^nginx:1\\.14\\..*', element.image) }}"
              operator: Equals
              value: true
exclude:
  any:
    - namespaces: ["kube-system", "kyverno", "trivy-system"]
```

**灰度路径**：拦截策略（`block-critical-vuln-images`）以 `validationFailureAction: Audit` 安装，先以 Audit 模式观察，`deny` 步骤再 `kubectl patch` 切到 Enforce，现场演示 `nginx:1.14.x` 新 Pod 被准入拒绝。

**国内网络注意**：trivy 首次扫描需从 `ghcr.io` 下载 ~110MB 漏洞库，若节点直连 ghcr/mirror.gcr 均超时，scan 步骤会一直"尚无报告"。可用 helm values 换 DB 源（`trivy.dbRegistry` / `trivy.dbRepository`，如自建白名单镜像或 `oras` 抽取后推私有仓库）；都不具备时，policy/deny 步骤（Kyverno 拦截演示）不依赖漏洞库，仍可完整演示。

## Deep Dive

**报告即资源**：Trivy Operator 以 DaemonSet/Deployment 形式常驻，自动发现工作负载镜像并离线比对 CVE 库，产物不是日志而是 CRD 对象。扫描结果标准化后，消费方不再局限于人看仪表板：Grafana 可以画趋势、Kyverno/Gatekeeper 可以引用字段做策略判定、CI 可以 `kubectl get vulnerabilityreport -o json | jq` 做门禁。`ignoreUnfixed=true` 过滤掉没有修复版本的 CVE——报告的价值在于"可行动"，列出永远修不了的洞只会造成告警疲劳。

**验签发生在 webhook 准入路径**：与扫描不同，签名校验在 Pod 创建请求被拦截时执行——用 ClusterPolicy 内置公钥执行 cosign verify，无签名或签名无效直接拒绝（Enforce 模式下）。这保证了"镜像从构建到运行没有被篡改过"，弥补了扫描只管已知漏洞、不管恶意内容的盲区。

**本实验拦截策略的边界（诚实说明）**：`block-critical-vuln-images` 按**镜像 tag** 拦截（tag 即已知漏洞版本的指纹，模拟"依据报告拦截"）；生产环境应改为真正依据 trivy-operator 生成的 `VulnerabilityReport` 数据做门禁（如 policy-reporter 联动，或在 CI 查询报告后再放行部署）。

**Kyverno 策略写法的坑**：不要用 `"!*nginx:1.14.*"` 这类取反通配——Kyverno pattern 不支持该语法；deny 规则 + JMESPath 条件（`regex_match`）才是正确写法。直接对全集群开 Enforce 会误伤系统组件（它们常拉取未签名的基础设施镜像），所以策略必须带 namespace exclude，并先 `Audit` 收集违规面、确认豁免清单后再切换强制模式。

**持续重扫闭环**：Trivy Operator watch 运行中镜像生成 VulnerabilityReport，报告字段再回流给策略引用——"部署后"的安全状态也持续可观测（新 CVE 曝光后，报告自动更新，策略下次判定即生效）。

## Q&A

**Q1: 拦截为什么还要前移到 CI？**
准入拦截拦的是"进了集群的坏镜像"，返工成本已经产生。CI 里跑 `trivy image --exit-code 1 --severity CRITICAL` 把拦截提前到镜像推送之前——坏镜像根本到不了 registry，省去"进了集群再被拒"的整套排查。准入层仍要保留，防的是绕过 CI 的直接部署。

**Q2: 签名和 SBOM 能怎么加固？**
SBOM 附件：cosign attest 把 SBOM 签进镜像，审计时可证明"部署的就是扫过的那份"；keyless 签名：用 OIDC 短期证书替代长期密钥，避免私钥管理负担。两者的共同目标是让"证明"本身也变得可验证、可审计。

**Q3: 这些安全策略本身怎么管理？**
策略即代码：Kyverno policies 放 Git 仓库走 PR 审批 + ArgoCD 同步（见 lab 28），安全策略也 GitOps 化——策略变更可评审、可回滚、可审计，和业务代码同一套纪律。
