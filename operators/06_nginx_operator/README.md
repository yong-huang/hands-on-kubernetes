# Nginx 反向代理 Operator（项目 6）

> 声明式 Nginx 配置：一个 `NginxProxy` CR 定义 upstreams 和 locations，
> Controller 渲染 nginx.conf 写入 ConfigMap 并挂载到 nginx Deployment——
> 改 CR = 改 Nginx 配置，无需手动编辑文件或重启。

## 1. 架构总览

![Nginx flow](images/nginx_flow.svg)

## 2. 快速开始

```bash
make install && make run
kubectl apply -f config/samples/web_v1_nginxproxy.yaml
kubectl get nginxproxy,cm,deploy,svc -l app.kubernetes.io/name=reverse-proxy
```

## 3. 文件结构

标准 kubebuilder 工程 + images/ 三件套。
