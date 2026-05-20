#!/usr/bin/env node
/**
 * Lightweight catalog/browse load probe using native fetch.
 * Usage: BASE_URL=http://localhost:3000 node scripts/load-test-catalog.mjs
 */
const base = String(process.env.BASE_URL || "http://localhost:3000").replace(/\/$/, "");
const concurrency = Number.parseInt(process.env.CONCURRENCY || "25", 10);
const requests = Number.parseInt(process.env.REQUESTS || "200", 10);

async function one(i) {
  const t0 = performance.now();
  const res = await fetch(`${base}/catalog`);
  const ms = performance.now() - t0;
  if (!res.ok) {
    throw new Error(`catalog ${i} → ${res.status}`);
  }
  await res.arrayBuffer();
  return ms;
}

async function main() {
  let ok = 0;
  let fail = 0;
  const latencies = [];
  let idx = 0;

  async function worker() {
    while (idx < requests) {
      const my = idx++;
      try {
        latencies.push(await one(my));
        ok += 1;
      } catch (e) {
        console.error(e.message || e);
        fail += 1;
      }
    }
  }

  const workers = Array.from({ length: Math.max(1, concurrency) }, () => worker());
  await Promise.all(workers);

  latencies.sort((a, b) => a - b);
  const p95 = latencies[Math.floor(latencies.length * 0.95)] ?? 0;
  console.log(
    JSON.stringify({
      base,
      ok,
      fail,
      p50: latencies[Math.floor(latencies.length * 0.5)] ?? 0,
      p95,
      max: latencies[latencies.length - 1] ?? 0,
    })
  );

  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
