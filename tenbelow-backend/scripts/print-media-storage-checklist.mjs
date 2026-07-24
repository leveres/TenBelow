#!/usr/bin/env node
/**
 * Print Phase 1 (disk) vs Phase 2 (R2) media env checklist for Render.
 *
 * Usage:
 *   npm run print:media-storage-checklist
 *   BASE_URL=https://tenbelow.onrender.com npm run print:media-storage-checklist
 */
import "dotenv/config";
import {
  getMediaStorageMode,
  getPartialObjectStorageWarning,
  isObjectStorageEnabled,
} from "../mediaObjectStorage.js";
import { getMediaStorageChecks } from "../mediaStorageHealth.js";

const BASE_URL = String(process.env.BASE_URL || process.env.BACKEND_URL || "").trim().replace(/\/$/, "");

function line(label, ok, detail = "") {
  const mark = ok ? "OK" : "!!";
  console.log(`${mark}  ${label}${detail ? ` — ${detail}` : ""}`);
}

console.log("\n=== TenBelow media storage checklist ===\n");

const mode = getMediaStorageMode();
const partial = getPartialObjectStorageWarning();
const checks = getMediaStorageChecks();

console.log("Local / shell env (this machine):");
line("BACKEND_URL", Boolean(String(process.env.BACKEND_URL || "").trim()), process.env.BACKEND_URL || "not set");
line("BACKEND_DATA_DIR", Boolean(String(process.env.BACKEND_DATA_DIR || "").trim()), process.env.BACKEND_DATA_DIR || "default ./data");
line("mediaStorageMode", true, mode);
line("objectStorageEnabled", !isObjectStorageEnabled(), isObjectStorageEnabled() ? "R2/S3 active" : "disk (Phase 1)");
if (partial) {
  line("partial R2 config", false, partial);
} else {
  line("no partial R2 config", true);
}
line("mediaDirectoryWritable", checks.mediaDirectoryWritable);

console.log("\nPhase 1 (launch) — Render dashboard:");
console.log("  KEEP: BACKEND_URL, BACKEND_DATA_DIR, DATABASE_URL, APP_API_KEY, secrets");
console.log("  REMOVE: S3_MEDIA_BUCKET, S3_MEDIA_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,");
console.log("          S3_ENDPOINT, PUBLIC_MEDIA_BASE_URL");
console.log("  Docs: tenbelow-backend/docs/media-storage-setup.md");

console.log("\nProduction R2 cutover (Render shell, after full env + redeploy):");
console.log("  DRY_RUN=1 npm run migrate:disk-media-to-r2");
console.log("  npm run setup:r2-production");
console.log("  Then manual deploy to reload JSON cache");

if (BASE_URL) {
  console.log(`\nProduction probe: ${BASE_URL}/ready`);
  try {
    const response = await fetch(`${BASE_URL}/ready`);
    const body = await response.json();
    const c = body.checks || {};
    line("HTTP /ready", response.ok, String(response.status));
    if (c.mediaStorageMode) line("mediaStorageMode", c.mediaStorageMode === "disk" || c.mediaStorageMode === "object_storage", c.mediaStorageMode);
    if (c.mediaStorageReady != null) line("mediaStorageReady", c.mediaStorageReady === true);
    if (c.mediaStoragePartialConfig) line("mediaStoragePartialConfig", false, "remove partial R2 env vars");
  } catch (err) {
    line("HTTP /ready", false, err.message || String(err));
  }
}

console.log("");
