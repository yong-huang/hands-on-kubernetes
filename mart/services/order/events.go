// 订单事件发布（项目 5）：订单创建后向 Kafka 发 order.created。
// 解耦原则：Kafka 不可用只记日志，绝不阻断下单主流程——这是异步化的意义所在
package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"
	"go.opentelemetry.io/otel"
)

const orderCreatedTopic = "orders"

// OrderEvent：订单领域事件（JSON 序列化上 Kafka，跨语言消费者可读）
type OrderEvent struct {
	EventType  string `json:"event_type"`
	OrderID    string `json:"order_id"`
	ProductID  string `json:"product_id"`
	Quantity   int    `json:"quantity"`
	PriceCents int64  `json:"price_cents"`
}

// EventPublisher 包一个 franz-go 客户端；连接失败也不致命
type EventPublisher struct {
	cl *kgo.Client
}

func NewEventPublisher(addr string) *EventPublisher {
	cl, err := kgo.NewClient(kgo.SeedBrokers(addr))
	if err != nil {
		log.Printf("kafka producer init failed (events disabled): %v", err)
		return &EventPublisher{}
	}
	// 探活 3s，不通只打日志；kgo 会持续后台重连
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cl.Ping(ctx)
	return &EventPublisher{cl: cl}
}

// kgoHeaderCarrier：把 OTel propagator 接到 Kafka headers 上，
// 消费端（notification）据此把消息串进同一条 trace
type kgoHeaderCarrier struct{ h *[]kgo.RecordHeader }

func (c kgoHeaderCarrier) Get(k string) string {
	for _, hdr := range *c.h {
		if hdr.Key == k {
			return string(hdr.Value)
		}
	}
	return ""
}
func (c kgoHeaderCarrier) Set(k, v string) {
	*c.h = append(*c.h, kgo.RecordHeader{Key: k, Value: []byte(v)})
}
func (c kgoHeaderCarrier) Keys() []string {
	keys := make([]string, 0, len(*c.h))
	for _, hdr := range *c.h {
		keys = append(keys, hdr.Key)
	}
	return keys
}

// PublishOrderCreated 异步发送；带 span，trace context 随 headers 传播
func (p *EventPublisher) PublishOrderCreated(ctx context.Context, o *order) {
	if p.cl == nil {
		return
	}
	tracer := otel.Tracer("order")
	ctx, span := tracer.Start(ctx, "kafka.publish order.created")
	span.End() // 异步：发布 span 立即结束，Kafka 往返不占用请求延迟
	ev := OrderEvent{
		EventType:  "order.created",
		OrderID:    o.ID,
		ProductID:  o.ProductID,
		Quantity:   o.Quantity,
		PriceCents: o.PriceCents,
	}
	b, err := json.Marshal(ev)
	if err != nil {
		log.Printf("marshal event: %v", err)
		return
	}
	headers := []kgo.RecordHeader{}
	otel.GetTextMapPropagator().Inject(ctx, kgoHeaderCarrier{&headers})
	rec := &kgo.Record{Topic: orderCreatedTopic, Value: b, Headers: headers}
	// 异步发布：订单已持久化在 PG，事件失败只记日志（压测发现同步等待
	// 会被 Kafka 偶发停顿拖出 5s 长尾，压垮 p99——典型的请求路径瘦身）
	p.cl.Produce(context.Background(), rec, func(_ *kgo.Record, err error) {
		if err != nil {
			log.Printf("publish order.created failed (order flow NOT affected): %v", err)
			return
		}
		log.Printf("published order.created for %s (partition=%d offset=%d)",
			o.ID, rec.Partition, rec.Offset)
	})
}
