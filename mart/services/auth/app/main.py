"""mini-mart 认证服务（项目 8）：JWT 签发 + 校验。
作为 ingress-nginx 的外部授权服务（auth-url）：网关收到请求先来问这里，
401 就直接拦下——这是网关生态里最常用的 external auth 模式"""
import logging
import os
import time

import jwt
from fastapi import FastAPI, HTTPException, Request

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("auth")

SECRET = os.getenv("JWT_SECRET", "mart-demo-secret")
ALG = "HS256"
TOKEN_TTL = 3600

app = FastAPI(title="mini-mart auth", version="0.1.0")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/token")
def mint(sub: str = "demo"):
    """签发测试用 JWT（生产应走登录流程，这里只演示网关侧校验）"""
    payload = {"sub": sub, "iat": int(time.time()), "exp": int(time.time()) + TOKEN_TTL}
    return {"sub": sub, "token": jwt.encode(payload, SECRET, algorithm=ALG)}


@app.api_route("/auth", methods=["GET", "POST"])
def auth(request: Request):
    """ingress auth-url 回调：Authorization: Bearer <jwt> 合法放行，否则 401 拦截"""
    raw = request.headers.get("Authorization", "")
    token = raw[7:] if raw.startswith("Bearer ") else raw
    if not token:
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        payload = jwt.decode(token, SECRET, algorithms=[ALG])
    except jwt.PyJWTError as e:
        raise HTTPException(status_code=401, detail=f"invalid token: {e}")
    log.info("authorized sub=%s", payload.get("sub"))
    return {"sub": payload.get("sub")}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
