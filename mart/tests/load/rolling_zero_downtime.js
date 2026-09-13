// 项目 1 验收①：滚动更新期间持续打流量，统计非 2xx 响应数
// 用法：BASE=http://192.168.x.x:30880 DURATION=45s k6 run rolling_zero_downtime.js
import http from 'k6/http';
import { Counter } from 'k6/metrics';
import { sleep } from 'k6';

const BASE = __ENV.BASE || 'http://127.0.0.1:30880';
const bad = new Counter('bad_responses');   // 任何非 200 都计入（502/503/拒绝）
const ok = new Counter('ok_responses');

export const options = {
  vus: 5,
  duration: __ENV.DURATION || '45s',
  rps: 50, // 恒压 50 rps：低到不触发限流，高到能在切换窗口抓到失败
};

export default function () {
  const res = http.get(`${BASE}/products`, { timeout: '2s' });
  if (res.status === 200) {
    ok.add(1);
  } else {
    bad.add(1);
    console.warn(`BAD status=${res.status} body=${String(res.body).slice(0, 120)}`);
  }
  sleep(0.02);
}

export function handleSummary(data) {
  const out = __ENV.OUT || '/tmp/k6-rolling.json';
  return { [out]: JSON.stringify(data, null, 2) };
}
