FROM python:3.13-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /venv \
 && /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.13-slim
RUN useradd -m -u 10001 appuser
COPY --from=builder /venv /venv
WORKDIR /app
COPY app/ ./app/
ENV PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=dev
USER appuser
EXPOSE 8000
CMD ["python", "-m", "app.main"]
