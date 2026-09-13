"""mini-mart 库存服务（项目 6）：独立数据库，Saga 的参与方。

- POST /reserve {order_id, product_id, quantity}  锁库存（Saga 正向步骤）
- POST /release/{order_id}                        释放（Saga 补偿步骤）
- 两者都按 order_id 幂等：Saga 重试/响应丢失场景不会重复扣或重复放
"""
import logging
import os
import sys
import time

# 让同目录的工具模块（otel_setup 等）在 python -m app.main 下可导入
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from otel_setup import setup_telemetry

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("inventory")

APP_VERSION = os.getenv("APP_VERSION", "dev")
DSN = os.getenv("INV_DB_DSN", "postgresql://inv_user:invpw@postgres.mart.svc:5432/invdb")

# 故障注入： Saga 时序验收用
FAULT = {"delay_s": 0.0}

_ready = False


def db():
    # 短连接：学习项目够用；生产应连接池
    return psycopg.connect(DSN, connect_timeout=5)


def wait_db(seconds=60):
    global _ready
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            with db() as conn, conn.cursor() as cur:
                cur.execute("SELECT 1 FROM stock LIMIT 1")
            _ready = True
            log.info("db ready")
            return
        except Exception as e:
            log.warning("db not ready: %s", e)
            time.sleep(2)
    raise RuntimeError("db unreachable")


from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app: FastAPI):
    wait_db()
    yield
    global _ready
    _ready = False


app = FastAPI(title="mini-mart inventory", version=APP_VERSION, lifespan=lifespan)
tracer = setup_telemetry("inventory", app)
try:
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry import trace as otel_trace
    FastAPIInstrumentor.instrument_app(app, tracer_provider=otel_trace.get_tracer_provider())
except Exception as e:  # noqa: BLE001
    log.warning("fastapi instrumentation skipped: %s", e)


class ReserveReq(BaseModel):
    order_id: str
    product_id: str
    quantity: int


@app.get("/fault")
async def fault(delay: str = "0"):
    FAULT["delay_s"] = float(delay.rstrip("s")) if delay else 0.0
    return {"fault": FAULT}


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "version": APP_VERSION}


@app.get("/readyz")
async def readyz():
    if not _ready:
        raise HTTPException(status_code=503, detail="db not ready")
    return {"status": "ready"}


@app.get("/stock/{product_id}")
async def stock(product_id: str):
    await _maybe_delay()
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT available, reserved FROM stock WHERE product_id=%s", (product_id,))
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="unknown product")
    return {"product_id": product_id, "available": row[0], "reserved": row[1]}


@app.post("/reserve")
async def reserve(req: ReserveReq):
    await _maybe_delay()
    if req.quantity <= 0:
        raise HTTPException(status_code=400, detail="bad quantity")
    with db() as conn, conn.cursor() as cur:
        # 事务 1：行锁校验 + 幂等插入预定单
        cur.execute(
            "INSERT INTO reservations(order_id, product_id, quantity, status) "
            "VALUES (%s,%s,%s,'reserved') ON CONFLICT (order_id) DO NOTHING",
            (req.order_id, req.product_id, req.quantity),
        )
        if cur.rowcount == 0:
            # 已有同号预定：Saga 重试/响应丢失场景，直接返回既有结果（幂等）
            conn.commit()
            log.info("reserve idempotent hit: %s", req.order_id)
            return {"order_id": req.order_id, "status": "reserved", "idempotent": True}
        cur.execute("SELECT available FROM stock WHERE product_id=%s FOR UPDATE", (req.product_id,))
        row = cur.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="unknown product")
        if row[0] < req.quantity:
            conn.rollback()
            raise HTTPException(status_code=409, detail="insufficient stock")
        cur.execute(
            "UPDATE stock SET available=available-%s, reserved=reserved+%s WHERE product_id=%s",
            (req.quantity, req.quantity, req.product_id),
        )
    log.info("reserved %s x%d for %s", req.product_id, req.quantity, req.order_id)
    return {"order_id": req.order_id, "status": "reserved"}


@app.post("/release/{order_id}")
async def release(order_id: str):
    await _maybe_delay()
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT product_id, quantity, status FROM reservations WHERE order_id=%s FOR UPDATE", (order_id,))
        row = cur.fetchone()
        if row is None or row[2] != "reserved":
            # 没预定过 / 已释放：补偿幂等
            conn.commit()
            log.info("release idempotent no-op: %s", order_id)
            return {"order_id": order_id, "status": "released", "idempotent": True}
        cur.execute(
            "UPDATE stock SET available=available+%s, reserved=reserved-%s WHERE product_id=%s",
            (row[1], row[1], row[0]),
        )
        cur.execute("UPDATE reservations SET status='released' WHERE order_id=%s", (order_id,))
    log.info("released reservation for %s", order_id)
    return {"order_id": order_id, "status": "released"}


@app.get("/reservations/{order_id}")
async def reservations(order_id: str):
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT product_id, quantity, status FROM reservations WHERE order_id=%s", (order_id,))
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="no reservation")
    return {"order_id": order_id, "product_id": row[0], "quantity": row[1], "status": row[2]}


async def _maybe_delay():
    if FAULT["delay_s"] > 0:
        log.warning("fault injection: sleeping %.1fs", FAULT["delay_s"])
        import asyncio
        await asyncio.sleep(FAULT["delay_s"])


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
