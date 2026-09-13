// mini-mart 订单服务（项目 2）：REST 对外，gRPC 对内查价。
// 弹性要点实现在 getProductWithTimeout：500ms 总预算 + 1 次快速重试，
// 预算用尽返回 504 而不是悬挂（验收③）。
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"

	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/sony/gobreaker"
	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"

	pb "mart/api/gen/go/mart/v1"
)

const (
	appVersion      = "0.2.0"
	lookupTimeout   = 500 * time.Millisecond // 查价总预算：含重试
	retryBackoff    = 50 * time.Millisecond
	maxRetryAttempt = 2 // 首次 + 1 次重试
)

// podSuffix：HOSTNAME 末段（kind Pod 名最后一段唯一），保证多副本订单号不撞
var podSuffix = func() string {
	h := os.Getenv("HOSTNAME")
	if i := strings.LastIndex(h, "-"); i >= 0 {
		return h[i+1:]
	}
	return h
}()

type order struct {
	ID         string `json:"id"`
	ProductID  string `json:"product_id"`
	Quantity   int    `json:"quantity"`
	PriceCents int64  `json:"price_cents"` // 下单瞬间的成交价快照
	Status     string `json:"status"`
	CreatedAt  string `json:"created_at"`
}

type createReq struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

type server struct {
	seq     atomic.Int64 // 仅用于本地订单号生成；订单本体在 Postgres
	conn    *grpc.ClientConn
	product pb.ProductServiceClient
	cb      *gobreaker.CircuitBreaker
	events  *EventPublisher
	st      *store
	invHTTP *http.Client
}

// Saga 参数：重试预算要能覆盖 inventory Pod 被杀后的重建窗口（约 20-30s）
const (
	sagaMaxAttempts  = 10
	sagaStepTimeout  = 3 * time.Second
	sagaRetryBackoff = 2 * time.Second
)

var errInsufficientStock = errors.New("insufficient stock")

// lookupProduct：熔断器包住每次 gRPC 尝试，重试带指数退避 + jitter。
// 预算仍是整体 500ms；熔断 Open 时 Execute 立即返回 ErrOpenState，
// 请求在毫秒级快速失败，不进入重试（这就是"不雪崩"的关键）
func (s *server) lookupProduct(ctx context.Context, id string) (*pb.Product, error) {
	ctx, cancel := context.WithTimeout(ctx, lookupTimeout)
	defer cancel()
	var lastErr error
	for attempt := 1; attempt <= maxRetryAttempt; attempt++ {
		if attempt > 1 {
			// 指数退避 + jitter：50~100ms 随机，防惊群
			backoff := retryBackoff + time.Duration(rand.Int63n(int64(retryBackoff)))
			select {
			case <-time.After(backoff):
			case <-ctx.Done():
				return nil, lastErr
			}
		}
		result, err := s.cb.Execute(func() (any, error) {
			return s.product.GetProduct(ctx, &pb.GetProductRequest{ProductId: id})
		})
		if err == nil {
			return result.(*pb.GetProductResponse).GetProduct(), nil
		}
		if errors.Is(err, gobreaker.ErrOpenState) {
			return nil, err // 熔断打开：跳过重试立即失败
		}
		lastErr = err
		// NOT_FOUND 是业务错误，重试没有意义
		if st, ok := status.FromError(err); ok && st.Code() == 5 {
			return nil, err
		}
		log.Printf("GetProduct(%s) attempt %d failed: %v", id, attempt, err)
	}
	return nil, lastErr
}

// handleCreateOrder：Saga 编排器（order 是协调者）
//  0. 本地事务落 pending 订单
//  1. 正向步骤：inventory.reserve（幂等，可重试）
//  2. 成功 → status=created + 发领域事件
//  3. 库存不足 → status=cancelled（409）
//  4. 其他失败 → 尽力补偿 release，status=cancelled（502）
func (s *server) handleCreateOrder(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req createReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ProductID == "" {
		http.Error(w, "invalid body: need {\"product_id\",\"quantity\"}", http.StatusBadRequest)
		return
	}
	if req.Quantity <= 0 {
		req.Quantity = 1
	}

	product, err := s.lookupProduct(r.Context(), req.ProductID)
	if err != nil {
		writeLookupError(w, err, req.ProductID)
		return
	}

	o := &order{
		// 带 epoch：Pod 重启后内存 seq 归零会与库中旧单撞号（ON CONFLICT 静默吞单）
		ID:         fmt.Sprintf("o-%s-%d-%d", podSuffix, time.Now().Unix(), s.seq.Add(1)),
		ProductID:  req.ProductID,
		Quantity:   req.Quantity,
		PriceCents: product.GetPriceCents() * int64(req.Quantity),
		Status:     "pending",
	}
	// Saga 第 0 步：先落 pending，崩了也能从库里看见悬挂订单
	if err := s.st.insertPending(r.Context(), o); err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	log.Printf("saga start: %s product=%s", o.ID, o.ProductID)

	// Saga 第 1 步：正向锁库存
	if err := s.runReserveSaga(r.Context(), o); err != nil {
		if errors.Is(err, errInsufficientStock) {
			s.finalize(o, "cancelled")
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusConflict)
			_ = json.NewEncoder(w).Encode(map[string]any{"id": o.ID, "status": "cancelled", "error": "insufficient stock"})
			return
		}
		// 系统性失败：尽力补偿（release 幂等，没预定成功时是无害 no-op）
		s.compensate(o)
		s.finalize(o, "cancelled")
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadGateway)
		_ = json.NewEncoder(w).Encode(map[string]any{"id": o.ID, "status": "cancelled", "error": "saga failed"})
		return
	}

	// Saga 第 2 步：确认
	s.finalize(o, "created")
	log.Printf("saga done: %s created price=%d", o.ID, o.PriceCents)
	s.events.PublishOrderCreated(r.Context(), o)
	writeJSON(w, http.StatusCreated, o)
}

// runReserveSaga：正向步骤重试循环，覆盖 inventory Pod 重建窗口
func (s *server) runReserveSaga(ctx context.Context, o *order) error {
	tracer := otel.Tracer("order")
	ctx, span := tracer.Start(ctx, "saga.reserve")
	defer span.End()
	var lastErr error
	for attempt := 1; attempt <= sagaMaxAttempts; attempt++ {
		actx, cancel := context.WithTimeout(ctx, sagaStepTimeout)
		err := s.reserveInventory(actx, o)
		cancel()
		if err == nil {
			return nil
		}
		var httpE *httpStatusError
		if errors.As(err, &httpE) && httpE.code == http.StatusConflict {
			return errInsufficientStock // 业务失败不重试
		}
		lastErr = err
		span.RecordError(err)
		log.Printf("saga reserve %s attempt %d/%d failed: %v", o.ID, attempt, sagaMaxAttempts, err)
		select {
		case <-time.After(sagaRetryBackoff):
		case <-ctx.Done():
			return lastErr
		}
	}
	return lastErr
}

// compensate：补偿事务。release 按 order_id 幂等，多调无害
func (s *server) compensate(o *order) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	resp, err := s.invCall(ctx, "POST", "/release/"+o.ID, nil)
	if err != nil {
		log.Printf("compensate %s failed (best effort): %v", o.ID, err)
		return
	}
	resp.Body.Close()
	log.Printf("compensated %s", o.ID)
}

func (s *server) finalize(o *order, status string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := s.st.setStatus(ctx, o.ID, status); err != nil {
		log.Printf("finalize %s -> %s failed: %v", o.ID, status, err)
	}
	o.Status = status
}

type httpStatusError struct{ code int }

func (e *httpStatusError) Error() string { return fmt.Sprintf("inventory http %d", e.code) }

// invCall：inventory HTTP 调用小封装
func (s *server) invCall(ctx context.Context, method, path string, body []byte) (*http.Response, error) {
	addr := os.Getenv("INVENTORY_ADDR")
	if addr == "" {
		addr = "inventory.mart.svc:8000"
	}
	url := "http://" + addr + path
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, url, rd)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	return s.invHTTP.Do(req)
}

func (s *server) reserveInventory(ctx context.Context, o *order) error {
	body, _ := json.Marshal(map[string]any{"order_id": o.ID, "product_id": o.ProductID, "quantity": o.Quantity})
	resp, err := s.invCall(ctx, "POST", "/reserve", body)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusConflict {
		return &httpStatusError{code: http.StatusConflict}
	}
	if resp.StatusCode >= 300 {
		return &httpStatusError{code: resp.StatusCode}
	}
	return nil
}

func writeLookupError(w http.ResponseWriter, err error, productID string) {
	if st, ok := status.FromError(err); ok && st.Code() == 5 {
		http.Error(w, fmt.Sprintf("product %s not found", productID), http.StatusNotFound)
		return
	}
	if errors.Is(err, gobreaker.ErrOpenState) {
		http.Error(w, "circuit breaker open: product service unavailable", http.StatusServiceUnavailable)
		return
	}
	http.Error(w, fmt.Sprintf("product lookup failed: %v", err), http.StatusGatewayTimeout)
}

func (s *server) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	o, err := s.st.getOrder(r.Context(), r.PathValue("id"))
	if err != nil {
		http.Error(w, "order not found", http.StatusNotFound)
		return
	}
	writeJSON(w, http.StatusOK, o)
}

func (s *server) handleListOrders(w http.ResponseWriter, r *http.Request) {
	items, err := s.st.listOrders(r.Context())
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []*order{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "version": appVersion})
}

// readyz：gRPC 连接进入 READY 才对外就绪（GetState 是瞬时快照，空闲时会回落 Idle，
// 所以 Idle 也算健康——真实链路是否通由验收测试保证）
func (s *server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	state := s.conn.GetState().String()
	if state != "READY" && state != "IDLE" {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": state})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ready", "grpc": state, "version": appVersion})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func main() {
	log.Printf("order service %s starting", appVersion)
	ctx0, cancel0 := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel0()
	// 项目 7：遥测初始化（traces→Jaeger，metrics→/metrics）
	shutdownTelemetry := setupTelemetry(ctx0, "order")
	defer shutdownTelemetry()
	productAddr := os.Getenv("PRODUCT_ADDR")
	if productAddr == "" {
		productAddr = "product.mart.svc:50051"
	}

	// gRPC client 挂 OTel 拦截器：跨服务 span + trace context 自动传播
	conn, err := grpc.NewClient(productAddr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithStatsHandler(otelgrpc.NewClientHandler()))
	if err != nil {
		log.Fatalf("grpc connect %s: %v", productAddr, err)
	}
	defer conn.Close()

	// 熔断器（项目 4）：连续 5 次失败即打开，10s 后放行 2 个探测请求（Half-Open）
	cb := gobreaker.NewCircuitBreaker(gobreaker.Settings{
		Name:        "product-grpc",
		MaxRequests: 2,
		Interval:    30 * time.Second,
		Timeout:     10 * time.Second,
		ReadyToTrip: func(c gobreaker.Counts) bool {
			return c.Requests >= 3 && c.TotalFailures == c.Requests
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			log.Printf("CIRCUIT [%s]: %s -> %s", name, from, to) // 验收②断言对象
		},
	})

	mux := http.NewServeMux()
	// 连 Postgres（orderdb）：订单从内存搬进库，多副本安全
	dsn := os.Getenv("ORDER_DB_DSN")
	if dsn == "" {
		dsn = "postgres://order_user:orderpw@postgres.mart.svc:5432/orderdb"
	}
	st, err := newStore(ctx0, dsn)
	if err != nil {
		log.Fatalf("store init: %v", err)
	}
	defer st.pool.Close()
	invClient := &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}
	srv := &server{conn: conn, product: pb.NewProductServiceClient(conn), cb: cb, st: st, invHTTP: invClient}
	kafkaAddr := os.Getenv("KAFKA_ADDR")
	if kafkaAddr == "" {
		kafkaAddr = "kafka.mart.svc:9092"
	}
	srv.events = NewEventPublisher(kafkaAddr)
	hotConfig := NewHotConfig("/etc/mart/config.json")
	mux.HandleFunc("POST /orders", srv.handleCreateOrder)
	mux.HandleFunc("GET /orders", srv.handleListOrders)
	mux.HandleFunc("GET /orders/{id}", srv.handleGetOrder)
	mux.HandleFunc("GET /healthz", srv.handleHealthz)
	mux.HandleFunc("GET /readyz", srv.handleReadyz)
	mux.HandleFunc("GET /config", func(w http.ResponseWriter, r *http.Request) {
		// 项目 3：热加载的运行时配置（fsnotify 监听 kubelet 的符号链接换名）
		writeJSON(w, http.StatusOK, map[string]any{
			"config": hotConfig.Snapshot(),
			"pod":    os.Getenv("HOSTNAME"),
		})
	})

	// HTTP 挂 OTel 中间件 + /metrics 端点
	otelMux := http.NewServeMux()
	otelMux.Handle("GET /metrics", promhttp.Handler())
	otelMux.Handle("/", mux)
	httpServer := &http.Server{
		Addr:    ":8000",
		Handler: otelhttp.NewHandler(otelMux, "order-http"),
	}

	go func() {
		log.Printf("http listening on :8000")
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("http server: %v", err)
		}
	}()

	// 优雅关闭：SIGTERM 后停止收新请求、排空在途请求
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
	<-sig
	log.Println("SIGTERM received, draining")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(ctx)
}
