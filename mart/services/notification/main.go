// mini-mart 通知服务（项目 5）：消费 order.created 事件"发送通知"。
// 三个消费语义都实现在这里：
//   - 重试：处理失败同步重试 3 次（带日志）
//   - DLQ：3 次仍失败 → 原消息写入 orders.dlq 并提交（不让毒消息堵死分区）
//   - 幂等：同一 order_id 只发一次通知，重复投递直接抑制
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/twmb/franz-go/pkg/kgo"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

const (
	consumedTopic = "orders"
	dlqTopic      = "orders.dlq"
	groupID       = "notification"
	maxAttempts   = 3
)

type OrderEvent struct {
	EventType  string `json:"event_type"`
	OrderID    string `json:"order_id"`
	ProductID  string `json:"product_id"`
	Quantity   int    `json:"quantity"`
	PriceCents int64  `json:"price_cents"`
}

// ---- 运行状态（/stats 可观测；故障注入开关） ----

var (
	mu         sync.Mutex
	processed  int
	dlqCount   int
	duplicates int
	failMode   bool
	seen       = map[string]bool{} // 幂等表：order_id -> 已处理
)

func statsJSON(w http.ResponseWriter, _ *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	writeJSON(w, map[string]any{
		"processed":  processed,
		"dlq":        dlqCount,
		"duplicates": duplicates,
		"fail_mode":  failMode,
	})
}

// handle 处理一条消息；返回 error 表示"连 DLQ 都进不去"，不提交等重投
func handle(ctx context.Context, cl *kgo.Client, rec *kgo.Record) error {
	var ev OrderEvent
	if err := json.Unmarshal(rec.Value, &ev); err != nil {
		log.Printf("bad message at %s/%d, skip: %v", rec.Topic, rec.Offset, err)
		return nil // 坏消息直接丢弃（也可进 DLQ，这里从简）
	}

	mu.Lock()
	dup := seen[ev.OrderID]
	mu.Unlock()
	if dup {
		mu.Lock()
		duplicates++
		mu.Unlock()
		log.Printf("DUPLICATE suppressed for %s (idempotency)", ev.OrderID)
		return nil
	}

	// 同步重试 3 次：真实消费者最常见的失败处理形态
	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		mu.Lock()
		injected := failMode
		mu.Unlock()
		if injected {
			lastErr = fmt.Errorf("injected consumer failure")
			log.Printf("process %s attempt %d/%d failed: %v", ev.OrderID, attempt, maxAttempts, lastErr)
			time.Sleep(300 * time.Millisecond)
			continue
		}
		log.Printf("NOTIFICATION sent for order %s (product=%s amount=%d)",
			ev.OrderID, ev.ProductID, ev.PriceCents)
		lastErr = nil
		break
	}
	if lastErr != nil {
		// 3 次全失败 → 原样进 DLQ
		dlqRec := &kgo.Record{Topic: dlqTopic, Key: rec.Key, Value: rec.Value}
		pctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		if err := cl.ProduceSync(pctx, dlqRec).FirstErr(); err != nil {
			log.Printf("DLQ publish failed, will re-consume: %v", err)
			return err
		}
		mu.Lock()
		dlqCount++
		seen[ev.OrderID] = true // 进了 DLQ 就算"处理完毕"，防止重复入 DLQ
		mu.Unlock()
		log.Printf("order %s -> DLQ after %d failed attempts", ev.OrderID, maxAttempts)
		return nil
	}

	mu.Lock()
	processed++
	seen[ev.OrderID] = true
	mu.Unlock()
	return nil
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

// kgoHeaderCarrier：从 Kafka headers 提取 trace context
type kgoHeaderCarrier struct{ h []kgo.RecordHeader }

func (c kgoHeaderCarrier) Get(k string) string {
	for _, hdr := range c.h {
		if hdr.Key == k {
			return string(hdr.Value)
		}
	}
	return ""
}
func (c kgoHeaderCarrier) Set(k, v string) {
	c.h = append(c.h, kgo.RecordHeader{Key: k, Value: []byte(v)})
}
func (c kgoHeaderCarrier) Keys() []string {
	keys := make([]string, 0, len(c.h))
	for _, hdr := range c.h {
		keys = append(keys, hdr.Key)
	}
	return keys
}

func main() {
	log.Printf("notification service starting")
	ctxRoot := context.Background()
	shutdownTelemetry := setupTelemetry(ctxRoot, "notification")
	defer shutdownTelemetry()
	brokers := []string{os.Getenv("KAFKA_ADDR")}
	if brokers[0] == "" {
		brokers[0] = "kafka.mart.svc:9092"
	}

	cl, err := kgo.NewClient(
		kgo.SeedBrokers(brokers...),
		kgo.ConsumerGroup(groupID),
		kgo.ConsumeTopics(consumedTopic),
		kgo.AutoCommitMarks(), // 处理完的消息才提交
	)
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	defer cl.Close()
	// 等 broker 就绪（部署顺序 kafka 在前，但重启场景也要能扛）
	pingCtx, pingCancel := context.WithTimeout(context.Background(), 30*time.Second)
	cl.Ping(pingCtx)
	pingCancel()

	mux := http.NewServeMux()
	mux.Handle("GET /metrics", promhttp.Handler())
	mux.HandleFunc("GET /stats", statsJSON)
	mux.HandleFunc("GET /fault", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		failMode = r.URL.Query().Get("mode") == "consumer_fail"
		cur := failMode
		mu.Unlock()
		writeJSON(w, map[string]bool{"fail_mode": cur})
	})
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})
	go func() {
		// otelhttp 提供 RED 指标与 server span（指标名 http_server_request_duration_seconds_*）
		h := otelhttp.NewHandler(mux, "notification-http")
		if err := http.ListenAndServe(":8000", h); err != nil {
			log.Printf("http: %v", err)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	log.Printf("consuming topic %s as group %s", consumedTopic, groupID)
	for {
		fetches := cl.PollRecords(ctx, 32)
		if fetches.IsClientClosed() {
			return
		}
		fetches.EachError(func(t string, p int32, err error) {
			log.Printf("fetch error %s/%d: %v", t, p, err)
		})
		fetches.EachRecord(func(rec *kgo.Record) {
			// 从消息 headers 恢复 trace context：与生产端串成一条 trace
			carrier := kgoHeaderCarrier{h: rec.Headers}
			propCtx := otel.GetTextMapPropagator().Extract(ctx, carrier)
			tracer := otel.Tracer("notification")
			pctx, span := tracer.Start(propCtx, "notification.process",
				trace.WithAttributes(attribute.String("messaging.order_id", rec.Topic)))
			err := handle(pctx, cl, rec)
			if err != nil {
				span.RecordError(err)
				span.SetStatus(codes.Error, err.Error())
			} else {
				span.SetStatus(codes.Ok, "")
				cl.MarkCommitRecords(rec)
			}
			span.End()
		})
	}
}
