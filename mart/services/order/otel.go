// 遥测初始化（项目 7）：traces → Jaeger(OTLP)，metrics → Prometheus /metrics
package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	otelprom "go.opentelemetry.io/otel/exporters/prometheus"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// setupTelemetry 返回 shutdown 函数；失败不致命（观测挂了业务照常跑）
func setupTelemetry(ctx context.Context, serviceName string) func() {
	res, _ := resource.New(ctx, resource.WithAttributes(semconv.ServiceName(serviceName)))

	shutdowns := []func(){}

	// traces：OTLP/gRPC 直发 Jaeger
	if tp, err := traceProvider(ctx, res); err == nil {
		otel.SetTracerProvider(tp)
		otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
			propagation.TraceContext{}, propagation.Baggage{}))
		shutdowns = append(shutdowns, func() { _ = tp.Shutdown(context.Background()) })
	} else {
		log.Printf("trace provider init failed: %v", err)
	}

	// metrics：Prometheus reader，挂在 /metrics 由 prometheus 抓
	if mp, err := meterProvider(res); err == nil {
		otel.SetMeterProvider(mp)
		shutdowns = append(shutdowns, func() { _ = mp.Shutdown(context.Background()) })
	} else {
		log.Printf("meter provider init failed: %v", err)
	}

	return func() {
		for _, f := range shutdowns {
			f()
		}
	}
}

func traceProvider(ctx context.Context, res *resource.Resource) (*sdktrace.TracerProvider, error) {
	addr := os.Getenv("OTEL_TRACE_ADDR")
	if addr == "" {
		addr = "jaeger.observability.svc:4317"
	}
	exp, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(addr),
		otlptracegrpc.WithInsecure())
	if err != nil {
		return nil, err
	}
	return sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
	), nil
}

func meterProvider(res *resource.Resource) (*sdkmetric.MeterProvider, error) {
	// Prometheus reader 把指标写进 client_golang 默认 registry，
	// /metrics 端点用 promhttp.Handler() 即可同时暴露 Go 运行时指标
	exp, err := otelprom.New()
	if err != nil {
		return nil, err
	}
	return sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(exp),
		sdkmetric.WithResource(res),
	), nil
}
