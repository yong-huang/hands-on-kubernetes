// 订单持久化（项目 6）：PostgreSQL（orderdb），替代项目 1-5 的内存存储。
// 多副本终于可以安全扩容——内存版的跨副本不一致在项目 2/5 踩过两次
package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const schema = `
CREATE TABLE IF NOT EXISTS orders (
	id          text PRIMARY KEY,
	product_id  text NOT NULL,
	quantity    int  NOT NULL,
	price_cents bigint NOT NULL,
	status      text NOT NULL,           -- pending | created | cancelled
	created_at  timestamptz NOT NULL DEFAULT now()
)`

type store struct {
	pool *pgxpool.Pool
}

func newStore(ctx context.Context, dsn string) (*store, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 4
	// db 可能比服务后就绪：重试等待
	var pool *pgxpool.Pool
	for i := 0; i < 30; i++ {
		if pool, err = pgxpool.NewWithConfig(ctx, cfg); err == nil {
			if pingErr := pool.Ping(ctx); pingErr == nil {
				break
			}
			pool.Close()
		}
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		return nil, err
	}
	if _, err := pool.Exec(ctx, schema); err != nil {
		return nil, err
	}
	return &store{pool: pool}, nil
}

// insertPending：Saga 第 0 步，落一条 pending 订单（本地事务）
func (s *store) insertPending(ctx context.Context, o *order) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO orders(id, product_id, quantity, price_cents, status)
		 VALUES ($1,$2,$3,$4,'pending')
		 ON CONFLICT (id) DO NOTHING`, // 同号重试幂等
		o.ID, o.ProductID, o.Quantity, o.PriceCents)
	return err
}

func (s *store) setStatus(ctx context.Context, id, status string) error {
	_, err := s.pool.Exec(ctx, `UPDATE orders SET status=$1 WHERE id=$2`, status, id)
	return err
}

func (s *store) getOrder(ctx context.Context, id string) (*order, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT id, product_id, quantity, price_cents, status, created_at FROM orders WHERE id=$1`, id)
	var o order
	var createdAt time.Time
	if err := row.Scan(&o.ID, &o.ProductID, &o.Quantity, &o.PriceCents, &o.Status, &createdAt); err != nil {
		return nil, err
	}
	o.CreatedAt = createdAt.UTC().Format(time.RFC3339)
	return &o, nil
}

func (s *store) listOrders(ctx context.Context) ([]*order, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, product_id, quantity, price_cents, status, created_at
		 FROM orders ORDER BY created_at DESC LIMIT 100`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*order
	for rows.Next() {
		var o order
		var createdAt time.Time
		if err := rows.Scan(&o.ID, &o.ProductID, &o.Quantity, &o.PriceCents, &o.Status, &createdAt); err != nil {
			return nil, err
		}
		o.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		out = append(out, &o)
	}
	return out, rows.Err()
}
