"""遥测初始化（项目 7）：traces → Jaeger，metrics → /metrics 供 Prometheus 抓取"""
import logging
import os

log = logging.getLogger("otel")


def setup_telemetry(service_name: str, app=None):
    """traces 必成；metrics/ASGI 挂载失败不致命。返回 (tracer, shutdown)"""
    from opentelemetry import trace
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

    resource = Resource.create({"service.name": service_name})
    tp = TracerProvider(resource=resource)
    endpoint = os.getenv("OTEL_TRACE_ADDR", "jaeger.observability.svc:4317")
    try:
        tp.add_span_processor(BatchSpanProcessor(
            OTLPSpanExporter(endpoint=endpoint, insecure=True)))
        trace.set_tracer_provider(tp)
    except Exception as e:  # noqa: BLE001 - 观测不可用不能拖垮业务
        log.warning("trace init failed: %s", e)

    install_metrics(app)
    return trace.get_tracer(service_name)


def install_metrics(app):
    """RED 指标用 prometheus_client 直装（比 otel metrics SDK 稳），指标名与
    Go 侧 otelhttp 的 semconv 对齐，Grafana 一套查询通吃"""
    if app is None:
        return
    try:
        import time as _t
        from prometheus_client import Histogram, make_asgi_app
        # Histogram 自带 _count/_bucket/_sum，一套指标撑起 RED 三张图
        LAT = Histogram("http_server_duration_milliseconds", "latency",
                        ["method", "path", "status"])

        @app.middleware("http")
        async def _metrics_mw(request, call_next):
            start = _t.perf_counter()
            try:
                resp = await call_next(request)
                status = resp.status_code
                return resp
            finally:
                dur = (_t.perf_counter() - start) * 1000
                path = request.scope.get("route").path if request.scope.get("route") else request.url.path
                LAT.labels(request.method, path, str(status)).observe(dur)

        app.mount("/metrics", make_asgi_app())
        log.info("prometheus metrics mounted at /metrics")
    except Exception as e:  # noqa: BLE001
        log.warning("metrics init failed: %s", e)
