// mini-mart 全链路压测（项目 10）：查商品 -> 下单（Saga 跨库 + gRPC + Kafka）
// 恒压到达率模型，贴近真实流量形状
import http from 'k6/http';
import { check, sleep } from 'k6';

const ORDER = __ENV.ORDER_BASE || 'http://order.mart.svc:8000';
const PRODUCT = __ENV.PRODUCT_BASE || 'http://product.mart.svc:8000';
const RATE = Number(__ENV.RATE || 200);
const DURATION = __ENV.DURATION || '5m';

export const options = {
  scenarios: {
    checkout: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 150,
      maxVUs: 400,
    },
  },
  thresholds: {
    http_req_duration: ['p(99)<300'],
    http_req_failed: ['rate<0.001'],
  },
};

export default function () {
  // 1. 查商品
  const p = http.get(`${PRODUCT}/products/p1`, { tags: { name: 'get_product' } });
  check(p, { 'product ok': (r) => r.status === 200 });

  // 2. 下单（服务端：gRPC 查价 -> Saga 锁库存 -> PG -> Kafka）
  const res = http.post(`${ORDER}/orders`,
    JSON.stringify({ product_id: 'p1', quantity: 1 }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'create_order' } });
  check(res, { 'order accepted': (r) => r.status === 201 });

  sleep(0.05);
}
