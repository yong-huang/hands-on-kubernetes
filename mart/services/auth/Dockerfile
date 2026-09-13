# 多阶段构建：构建阶段只产出依赖 venv，运行阶段不带 pip 缓存与构建工具
FROM python:3.13-slim AS builder
WORKDIR /build
COPY requirements.txt .
# venv 装到固定路径 /venv，运行阶段整体 COPY，保证两个阶段环境一致
RUN python -m venv /venv \
 && /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.13-slim
# 非 root 运行：容器内被攻破也拿不到 root
RUN useradd -m -u 10001 appuser
COPY --from=builder /venv /venv
WORKDIR /app
COPY app/ ./app/
ENV PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=dev
USER appuser
EXPOSE 8000
# 跑模块而不是 uvicorn 命令：main.py 里要同时拉起 HTTP 和 gRPC 两个 server
CMD ["python", "-m", "app.main"]
