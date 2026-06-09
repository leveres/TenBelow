#!/usr/bin/env node
/**
 * One-command production checklist:
 * 1) JSON -> Postgres relational migration
 * 2) Relational verification (strict)
 * 3) Core smoke test
 * 4) Readiness + admin relational health summary
 *
 * Usage:
 *   DATABASE_URL=... BASE_URL=https://tenbelow.onrender.com node scripts/release-checklist.mjs
 *
 * Optional:
 *   ADMIN_API_KEY=...      # includes admin smoke + health auth
 *   APP_API_KEY=...        # passed to smoke script
 *   SKIP_MIGRATION=1       # skip migration step
 *   SKIP_VERIFY=1          # skip verify step
 *   SKIP_SMOKE=1           # skip smoke step
 */
import "dotenv/config";
import { spawnSync } from "node:child_process";

const BASE_URL = String(process.env.BASE_URL || process.env.BACKEND_URL || "").trim().replace(/\/$/, "");
const DATABASE_URL = String(process.env.DATABASE_URL || "").trim();
const ADMIN_API_KEY = String(process.env.ADMIN_API_KEY || "").trim();

function runNodeScript(scriptPath, env = {}) {
  const result = spawnSync(process.execPath, [scriptPath], {
    stdio: "inherit",
    env: { ...process.env, ...env },
  });
  if (result.status !== 0) {
    throw new Error(`${scriptPath} failed with exit code ${result.status}`);
  }
}

async function fetchJSON(url, headers = {}) {
  const response = await fetch(url, { headers });
  const text = await response.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    body = { raw: text };
  }
  return { status: response.status, ok: response.ok, body };
}

function printSection(title) {
  console.log(`\n=== ${title} ===`);
}

async function main() {
  if (!BASE_URL) {
    throw new Error("BASE_URL or BACKEND_URL is required.");
  }
  if (!DATABASE_URL && process.env.SKIP_MIGRATION !== "1" && process.env.SKIP_VERIFY !== "1") {
    throw new Error("DATABASE_URL is required unless both migration and verify are skipped.");
  }

  if (process.env.SKIP_MIGRATION !== "1") {
    printSection("Step 1/4: Migrate JSON -> Postgres relational");
    runNodeScript("scripts/migrate-json-to-pg-relational.mjs");
  } else {
    printSection("Step 1/4: Migration skipped (SKIP_MIGRATION=1)");
  }

  if (process.env.SKIP_VERIFY !== "1") {
    printSection("Step 2/4: Verify relational tables (STRICT)");
    runNodeScript("scripts/verify-pg-relational.mjs", { STRICT: "1" });
  } else {
    printSection("Step 2/4: Verify skipped (SKIP_VERIFY=1)");
  }

  if (process.env.SKIP_SMOKE !== "1") {
    printSection("Step 3/4: Smoke test core endpoints");
    runNodeScript("scripts/smoke-core-endpoints.mjs", {
      BASE_URL,
      STRICT: "1",
      ...(ADMIN_API_KEY ? { ADMIN_API_KEY } : {}),
    });
  } else {
    printSection("Step 3/4: Smoke skipped (SKIP_SMOKE=1)");
  }

  printSection("Step 4/4: Runtime readiness summary");
  const ready = await fetchJSON(`${BASE_URL}/ready`);
  console.log(`ready status=${ready.status} ok=${ready.body?.ok === true}`);
  if (ready.body?.checks) {
    console.log(`ready checks: ${JSON.stringify(ready.body.checks)}`);
  }

  if (ADMIN_API_KEY) {
    const adminHealth = await fetchJSON(`${BASE_URL}/admin/pg-relational-health`, {
      "X-Admin-Key": ADMIN_API_KEY,
    });
    console.log(`pg-relational-health status=${adminHealth.status} ok=${adminHealth.body?.ok === true}`);
    if (adminHealth.body?.checks) {
      console.log(`pg checks: ${JSON.stringify(adminHealth.body.checks)}`);
    }
  } else {
    console.log("pg-relational-health skipped (set ADMIN_API_KEY to include admin summary).");
  }

  console.log("\nRelease checklist complete.");
}

main().catch((error) => {
  console.error(`release-checklist failed: ${error.message || error}`);
  process.exit(1);
});

