#!/usr/bin/env node
/**
 * One-shot R2 production cutover helper (run on Render shell with production env).
 *
 * 1) Verify object storage config
 * 2) Upload disk media → R2
 * 3) Rewrite JSON media URLs to PUBLIC_MEDIA_BASE_URL
 *
 * Usage:
 *   npm run setup:r2-production
 *   SKIP_MIGRATION=1 npm run setup:r2-production   # rewrite URLs only
 */
import "dotenv/config";
import { spawnSync } from "node:child_process";

function run(script, env = {}) {
  const result = spawnSync(process.execPath, [script], {
    stdio: "inherit",
    env: { ...process.env, ...env },
  });
  if (result.status !== 0) {
    throw new Error(`${script} failed`);
  }
}

async function main() {
  console.log("\n=== Step 1/3: Media storage checklist ===");
  run("scripts/print-media-storage-checklist.mjs");

  if (process.env.SKIP_MIGRATION !== "1") {
    console.log("\n=== Step 2/3: Upload disk media → R2 ===");
    run("scripts/migrate-disk-media-to-r2.mjs");
  } else {
    console.log("\n=== Step 2/3: Skipped (SKIP_MIGRATION=1) ===");
  }

  console.log("\n=== Step 3/3: Rewrite JSON media URLs ===");
  run("scripts/rewrite-json-media-urls.mjs");

  console.log("\nR2 production setup complete.");
  console.log("Restart the service (Render manual deploy) so JSON cache reloads.");
  console.log("Then test Edit Profile → Save with a photo in the app.");
}

main().catch((err) => {
  console.error("setup-r2-production failed:", err.message || err);
  process.exitCode = 1;
});
