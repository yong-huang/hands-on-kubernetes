# 构建上下文是 mart/ 根：docker build -f services/notification/Dockerfile -t mart/notification:0.1.0 .
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY services/notification/go.mod services/notification/go.sum* ./services/notification/
COPY services/notification/vendor ./services/notification/vendor
WORKDIR services/notification
# 依赖已 vendor：构建全程离线
COPY services/notification/*.go .
RUN CGO_ENABLED=0 go build -mod=vendor -ldflags="-s -w" -o /out/notification .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/notification /notification
EXPOSE 8000
ENTRYPOINT ["/notification"]
