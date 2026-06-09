#!/usr/bin/env node
/**
 * Core API smoke test for production/staging.
 *
 * Usage:
 *   BASE_URL=https://tenbelow.onrender.com node scripts/smoke-core-endpoints.mjs
 *
 * Optional:
 *   APP_API_KEY=...            # adds X-TenBelow-App-Key header
 *   ADMIN_API_KEY=...          # optional; direct key only works when ADMIN_ALLOW_DIRECT_KEY_AUTH=true
 *   STRICT=1                   # exit non-zero if any required check fails
 */
import "dotenv/config";

const baseURL = String(process.env.BASE_URL || process.env.BACKEND_URL || "").trim().replace(/\/$/, "");
const appApiKey = String(process.env.APP_API_KEY || "").trim();
const adminApiKey = String(process.env.ADMIN_API_KEY || "").trim();
const strict = String(process.env.STRICT || "").trim() === "1";

if (!baseURL) {
  console.error("BASE_URL or BACKEND_URL is required");
  process.exit(1);
}

function withAuthHeaders(headers = {}, includeAdmin = false) {
  const next = { ...headers };
  if (appApiKey) next["X-TenBelow-App-Key"] = appApiKey;
  if (includeAdmin && adminApiKey) next["X-Admin-Key"] = adminApiKey;
  return next;
}

async function check(name, endpoint, { method = "GET", expectStatus = 200, headers = {}, includeAdmin = false } = {}) {
  const url = `${baseURL}${endpoint}`;
  const response = await fetch(url, {
    method,
    headers: withAuthHeaders(headers, includeAdmin),
  });
  const text = await response.text();
  const ok = response.status === expectStatus;
  return {
    name,
    endpoint,
    ok,
    status: response.status,
    expectStatus,
    bodyPreview: text.slice(0, 220),
  };
}

function printResult(result) {
  const marker = result.ok ? "OK " : "!! ";
  console.log(`${marker} ${result.name.padEnd(26)} status=${String(result.status).padStart(3)} expected=${result.expectStatus} ${result.endpoint}`);
  if (!result.ok && result.bodyPreview) {
    console.log(`   body: ${result.bodyPreview.replace(/\s+/g, " ").trim()}`);
  }
}

async function main() {
  const checks = [
    ["health", "/health"],
    ["ready", "/ready"],
    ["config", "/config"],
    ["catalog", "/catalog"],
    ["seller-profiles", "/seller-profiles"],
    ["drop-current", "/drop/current"],
  ];

  const results = [];
  for (const [name, endpoint] of checks) {
    results.push(await check(name, endpoint));
  }

  const adminResult = await check("admin-pg-relational-health", "/admin/pg-relational-health", {
    includeAdmin: Boolean(adminApiKey),
  });
  if (adminResult.status === 200) {
    adminResult.ok = true;
    results.push(adminResult);
  } else if (adminResult.status === 401) {
    console.log("SKIP admin-pg-relational-health (protected; admin session required)");
  } else {
    results.push(adminResult);
  }

  console.log("");
  results.forEach(printResult);

  const failed = results.filter((entry) => !entry.ok);
  if (failed.length) {
    console.error(`\nSmoke test failures: ${failed.length}`);
    if (strict) process.exit(2);
  } else {
    console.log("\nSmoke test passed.");
  }
}

main().catch((err) => {
  console.error("smoke-core-endpoints failed:", err.message || err);
  process.exit(1);
});

