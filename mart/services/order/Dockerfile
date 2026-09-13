# 构建上下文是 mart/ 根（要同时拿到 api/gen/go 本地模块）：
#   docker build -f services/order/Dockerfile -t mart/order:0.1.0 .
FROM golang:1.26-alpine AS build
WORKDIR /src
# 先拷 go.mod/go.sum 再拷源码：依赖不变时 Docker 层缓存让 go mod download 秒过
COPY services/order/go.mod services/order/go.sum* ./services/order/
COPY services/order/vendor ./services/order/vendor
COPY api/gen/go ./api/gen/go
WORKDIR services/order
# 依赖已 vendor：构建全程离线，网络抖动不再影响
COPY services/order/*.go .
RUN CGO_ENABLED=0 go build -mod=vendor -ldflags="-s -w" -o /out/order .

# distroless/static：无 shell、带 CA 证书、非 root
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/order /order
EXPOSE 8000
ENTRYPOINT ["/order"]
