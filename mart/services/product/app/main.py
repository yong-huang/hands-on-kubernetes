"""mini-mart 商品服务（项目 2：+gRPC / +改价 / +故障注入）。

- HTTP(8000)：商品查询、PUT 改价（验收用）、/fault 故障注入（超时/熔断验收用）
- gRPC(50051)：mart.v1.ProductService/GetProduct，订单服务的查价通道
- /fault?delay=2s 的注入对 HTTP 和 gRPC 同时生效——一次注入，两条链路都能验
"""
import asyncio
import logging
import os
import sys
import time

# protoc 生成的桩用绝对包名 `from mart.v1 import ...`，而桩文件在本目录下，
# 把本目录加进 sys.path 才能命中（容器里 cwd=/app，本文件在 /app/app/）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from contextlib import asynccontextmanager

import grpc
import uvicorn
from fastapi import FastAPI, HTTPException
from grpc_reflection.v1alpha import reflection
from pydantic import BaseModel

from mart.v1 import product_pb2, product_pb2_grpc
from configwatch import HotConfig, FileSecretWatcher
from otel_setup import setup_telemetry

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("product")

APP_VERSION = os.getenv("APP_VERSION", "dev")
STARTED_AT = time.time()

PRODUCTS = {
    "p1": {"id": "p1", "name": "机械键盘", "price_cents": 39900},
    "p2": {"id": "p2", "name": "无线鼠标", "price_cents": 19900},
    "p3": {"id": "p3", "name": "显示器支架", "price_cents": 25900},
}

# 故障注入开关（运行时由 /fault 修改）：delay 延迟、mode500 瞬时错误（项目 4 熔断验收用）
FAULT = {"delay_s": 0.0, "mode500": False}

_ready = False


async def maybe_fault():
    """所有业务入口先过这里：注入的延迟/错误对 HTTP 与 gRPC 一视同仁。
    用 asyncio.sleep 而非 time.sleep：请求挂起但事件循环不堵，探针保持存活"""
    if FAULT["mode500"]:
        raise HTTPException(status_code=500, detail="injected fault: mode=500")
    if FAULT["delay_s"] > 0:
        log.warning("fault injection: sleeping %.1fs", FAULT["delay_s"])
        await asyncio.sleep(FAULT["delay_s"])


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _ready
    _ready = True
    log.info("product service %s ready (pid=%d)", APP_VERSION, os.getpid())
    yield
    _ready = False
    log.info("shutting down: readiness off, draining in-flight requests")


app = FastAPI(title="mini-mart product", version=APP_VERSION, lifespan=lifespan)

# 项目 7：FastAPI 自动埋点（server span + W3C 头解析）+ Prometheus /metrics
from opentelemetry import trace as otel_trace
tracer = setup_telemetry("product", app)
try:
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    FastAPIInstrumentor.instrument_app(app, tracer_provider=otel_trace.get_tracer_provider())
except Exception as e:  # noqa: BLE001
    log.warning("fastapi instrumentation skipped: %s", e)


class PriceUpdate(BaseModel):
    price_cents: int


@app.get("/products")
async def list_products():
    await maybe_fault()
    return {"items": list(PRODUCTS.values())}


@app.get("/products/{pid}")
async def get_product(pid: str):
    await maybe_fault()
    product = PRODUCTS.get(pid)
    if product is None:
        raise HTTPException(status_code=404, detail=f"product {pid} not found")
    return product


@app.put("/products/{pid}")
async def update_price(pid: str, body: PriceUpdate):
    """改价接口：验收②靠它验证订单价格是 gRPC 实时查的，不是写死的"""
    if pid not in PRODUCTS:
        raise HTTPException(status_code=404, detail=f"product {pid} not found")
    PRODUCTS[pid]["price_cents"] = body.price_cents
    log.info("price updated: %s -> %d cents", pid, body.price_cents)
    return PRODUCTS[pid]


@app.get("/fault")
async def fault(mode: str = "0", delay: str = "0"):
    """故障注入端点：mode=500 瞬时错误；delay=2s 注入延迟；mode=0&delay=0 清除"""
    FAULT["mode500"] = (mode == "500")
    FAULT["delay_s"] = float(delay.rstrip("s")) if delay else 0.0
    return {"fault": FAULT}


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "uptime_s": round(time.time() - STARTED_AT, 1)}


@app.get("/readyz")
async def readyz():
    if not _ready:
        raise HTTPException(status_code=503, detail="not ready")
    return {"status": "ready", "version": APP_VERSION}


@app.get("/version")
async def version():
    return {"version": APP_VERSION, "pod": os.getenv("HOSTNAME", "unknown")}


# ---- 项目 3：热加载的运行时配置与轮换的密钥 ----

DB = {"password": ""}


def apply_config(cfg):
    """配置变更的落地动作之一：日志级别实时生效（验收①的断言对象）。
    只调自己的 logger——root 打到 DEBUG 会让 grpc._cython 对每次事件循环
    poll 都打日志，日志洪水直接把 Pod 内存顶爆（本项目踩过的真坑）"""
    level = str(cfg.get("log_level", "INFO")).upper()
    logging.getLogger("product").setLevel(level)
    for noisy in ("grpc", "watchdog", "asyncio"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def on_password_changed(_pw):
    # 真实场景这里会用新密码重建连接池；模拟场景记状态即可
    DB["password"] = _pw


CONFIG = HotConfig(
    os.getenv("CONFIG_PATH", "/etc/mart/config.json"),
    default={"log_level": "INFO", "max_qps": 100},
    on_change=apply_config,
)
apply_config(CONFIG.snapshot())
SECRET = FileSecretWatcher(os.getenv("SECRET_PATH", "/etc/mart/secrets/db_password"), on_password_changed)
on_password_changed(SECRET.value())


@app.get("/config")
async def current_config():
    """当前生效配置 + 密钥指纹：验收轮询这个接口判断热加载是否生效"""
    return {
        "config": CONFIG.snapshot(),
        "db_password_len": len(DB["password"]),
        "pod": os.getenv("HOSTNAME", "unknown"),
    }


# ---- 排查工具（DEBUG_MEM=1 时启用）：返回 tracemalloc 分配 Top 榜 ----
if os.getenv("DEBUG_MEM") == "1":
    import tracemalloc
    tracemalloc.start(10)

    @app.get("/debug/top")
    async def debug_top():
        snap = tracemalloc.take_snapshot()
        stats = snap.statistics("lineno")[:10]
        return {"top": [str(s) for s in stats]}


# ---- gRPC：与 HTTP 共享同一份 PRODUCTS 和故障开关 ----

class ProductServicer(product_pb2_grpc.ProductServiceServicer):

    async def GetProduct(self, request, context):
        # gRPC aio 无现成拦截器时手动提取：metadata -> W3C carrier，串进同一条 trace
        from opentelemetry import propagate
        metadata = dict(context.invocation_metadata() or ())
        parent_ctx = propagate.extract(metadata)
        with tracer.start_as_current_span("product.GetProduct",
                                          context=parent_ctx,
                                          attributes={"product.id": request.product_id}):
            if FAULT["mode500"]:
                await context.abort(grpc.StatusCode.INTERNAL, "injected fault: mode=500")
            await maybe_fault()
            p = PRODUCTS.get(request.product_id)
            if p is None:
                await context.abort(grpc.StatusCode.NOT_FOUND, f"product {request.product_id} not found")
            return product_pb2.GetProductResponse(
                product=product_pb2.Product(
                    product_id=p["id"], name=p["name"], price_cents=p["price_cents"],
                )
            )


async def serve():
    # gRPC server 先起，uvicorn 后台接管信号；uvicorn 收 SIGTERM 排空后返回，
    # 再给 gRPC 10s grace 停掉在途 RPC
    grpc_server = grpc.aio.server()
    product_pb2_grpc.add_ProductServiceServicer_to_server(ProductServicer(), grpc_server)
    grpc_server.add_insecure_port("[::]:50051")
    reflection.enable_server_reflection(
        (product_pb2.DESCRIPTOR.services_by_name["ProductService"].full_name,
         reflection.SERVICE_NAME),
        grpc_server,
    )
    await grpc_server.start()
    log.info("grpc server listening on 50051")

    uvi = uvicorn.Config(app, host="0.0.0.0", port=8000, log_level="warning")
    server = uvicorn.Server(uvi)
    await server.serve()
    await grpc_server.stop(grace=10)
    log.info("grpc server stopped")


if __name__ == "__main__":
    asyncio.run(serve())
