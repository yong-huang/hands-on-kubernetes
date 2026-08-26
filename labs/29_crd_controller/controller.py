#!/usr/bin/env python3
"""
Database CRD 的最小可用 Controller (kubernetes python client)

Reconcile 循环: 对比 期望状态(spec) 与 实际状态(集群里有什么)
  1. 读 Database CR
  2. 不存在 headless Service -> 创建 (STS 的 serviceName 指向它)
  3. 不存在 StatefulSet      -> 创建 (engine/version/replicas 渲染镜像)
  4. 就绪后回写 status        -> phase=Running, endpoint=svc dns
任何时刻重新运行都会收敛到同一结果 —— 幂等是 controller 的灵魂。
"""

import os
import sys
import time

try:
    import kubernetes as k8s
except ImportError:
    sys.exit("pip install kubernetes")

GROUP, VERSION, PLURAL = "demo.example.com", "v1alpha1", "databases"
NS = os.getenv("WATCH_NAMESPACE", "crd-demo")
LOG = lambda msg: print(f"[controller] {msg}", flush=True)


# ------------------------------------------------------------------
# K8s API 客户端初始化(集群内 SA 或本地 kubeconfig 二选一)
# ------------------------------------------------------------------

def init_clients():
    try:
        k8s.config.load_incluster_config()
        LOG("loaded in-cluster config")
    except k8s.config.ConfigException:
        k8s.config.load_kube_config()
        LOG("loaded kubeconfig")
    return (k8s.client.CustomObjectsApi(), k8s.client.CoreV1Api(),
            k8s.client.AppsV1Api())


CO, CORE, APPS = init_clients()


# ------------------------------------------------------------------
# 期望状态渲染: CR spec -> 具体资源清单
# ------------------------------------------------------------------

def svc_manifest(db_name: str) -> dict:
    """headless Service: STS 的 serviceName 必须指向一个真实存在的 Service,
    Pod DNS (pod-0.<svc>) 和 status.endpoint 才可解析"""
    return {
        "apiVersion": "v1", "kind": "Service",
        "metadata": {"name": db_name, "namespace": NS},
        "spec": {"clusterIP": "None",          # headless: DNS 直接解析到 Pod IP
                 "selector": {"db": db_name}},
    }


def sts_manifest(cr: dict) -> dict:
    name = cr["metadata"]["name"]
    spec = cr["spec"]
    image = {"postgres": "postgres", "mysql": "mysql"}[spec["engine"]]
    # 引擎差异: 端口 / 数据目录 / root 密码环境变量各不相同
    per_engine = {
        "postgres": {"port": 5432, "data_dir": "/var/lib/postgresql/data",
                     "password_env": "POSTGRES_PASSWORD"},
        "mysql":    {"port": 3306, "data_dir": "/var/lib/mysql",
                     "password_env": "MYSQL_ROOT_PASSWORD"},
    }[spec["engine"]]
    return {
        "apiVersion": "apps/v1", "kind": "StatefulSet",
        "metadata": {"name": name, "namespace": NS},
        "spec": {
            "serviceName": name,
            "replicas": spec.get("replicas", 1),
            "selector": {"matchLabels": {"db": name}},
            "template": {
                "metadata": {"labels": {"db": name}},
                "spec": {"containers": [{
                    "name": spec["engine"],
                    "image": f"{image}:{spec.get('version', '16')}",
                    "ports": [{"containerPort": per_engine["port"]}],
                    "volumeMounts": [{"name": "data",
                                      "mountPath": per_engine["data_dir"]}],
                    "env": [{"name": per_engine["password_env"],
                             "value": "changeme"}],
                }]},
            },
            "volumeClaimTemplates": [{     # 数据卷由 STS 的 VCT 自管, 无需单独建 PVC
                "metadata": {"name": "data"},
                "spec": {"accessModes": ["ReadWriteOnce"],
                         "resources": {"requests":
                                       {"storage": spec["size"]}}},
            }],
        },
    }


# ------------------------------------------------------------------
# 调谐器: 让现实向声明靠拢 (幂等!)
# ------------------------------------------------------------------

def patch_status(name: str, status: dict) -> None:
    CO.patch_namespaced_custom_object_status(
        GROUP, VERSION, NS, PLURAL, name, {"status": status})


def reconcile(name: str) -> None:
    cr = CO.get_namespaced_custom_object(GROUP, VERSION, NS,
                                         PLURAL, name)
    LOG(f"reconcile {name}: engine={cr['spec']['engine']} "
        f"size={cr['spec']['size']}")

    # 1) 确保 headless Service 存在 (STS 的 serviceName 依赖它, 幂等创建)
    try:
        CORE.read_namespaced_service(name, NS)
    except k8s.client.ApiException as e:
        if e.status == 404:
            CORE.create_namespaced_service(
                NS, body=svc_manifest(name))
            LOG(f"created headless Service {name}")

    # 2) 确保工作负载存在且规格匹配
    want = sts_manifest(cr)
    try:
        have = APPS.read_namespaced_stateful_set(name, NS)
        drift = (have.spec.replicas != want["spec"]["replicas"] or
                 not have.spec.template.spec.containers[0].image.endswith(
                     cr["spec"].get("version", "")))
        if drift:                                   # 有漂移 -> 更新
            APPS.patch_namespaced_stateful_set(name, NS, body=want)
            LOG(f"patched StatefulSet {name} (drift detected)")
    except k8s.client.ApiException as e:
        if e.status == 404:                          # 不存在 -> 创建
            APPS.create_namespaced_stateful_set(NS, body=want)
            LOG(f"created StatefulSet {name}")

    # 3) 回写状态
    try:
        ready = APPS.read_namespaced_stateful_set_status(name, NS)
        n_ready = ready.status.ready_replicas or 0
        phase = ("Running" if n_ready == want["spec"]["replicas"]
                 else "Provisioning")
        patch_status(name, {
            "phase": phase,
            "endpoint": f"{name}.{NS}.svc.cluster.local",
            "conditions": [{"type": "Ready",
                            "status": "True" if phase == "Running" else "False"}],
        })
        LOG(f"status: phase={phase} ready={n_ready}")
    except k8s.client.ApiException:
        pass


# ------------------------------------------------------------------
# 主循环: 生产中用 informer/watch 增量驱动; 这里轮询足够说明原理
# ------------------------------------------------------------------

def main():
    LOG(f"watching Databases in ns={NS}")
    while True:
        try:
            for item in CO.list_namespaced_custom_object(
                    GROUP, VERSION, NS, PLURAL)["items"]:
                reconcile(item["metadata"]["name"])
        except k8s.client.ApiException as e:
            LOG(f"api error (CRD 未部署?): {e.status}")
        time.sleep(10)


if __name__ == "__main__":
    main()
