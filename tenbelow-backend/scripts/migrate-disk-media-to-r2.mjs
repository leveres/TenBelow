#!/usr/bin/env node
/**
 * Upload every file under BACKEND_DATA_DIR/media/ to R2/S3 (same object keys).
 * Run on Render shell after ALL object-storage env vars are set.
 *
 * Usage:
 *   npm run migrate:disk-media-to-r2
 *   DRY_RUN=1 npm run migrate:disk-media-to-r2
 */
import "dotenv/config";
import { readdirSync, readFileSync, statSync } from "fs";
import path from "path";
import { MEDIA_DIRECTORY_PATH } from "../storagePaths.js";
import { isObjectStorageEnabled, storeMediaBytes } from "../mediaObjectStorage.js";
import { safeContentTypeForExtension } from "../mediaUploadPolicy.js";

function walkFiles(rootDir) {
  const results = [];
  function walk(current) {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.isFile()) continue;
      results.push(full);
    }
  }
  walk(rootDir);
  return results;
}

async function main() {
  if (!isObjectStorageEnabled()) {
    throw new Error("Object storage is not fully configured. Set bucket, region, and AWS credentials on Render first.");
  }

  const dryRun = String(process.env.DRY_RUN || "").trim() === "1";
  const files = walkFiles(MEDIA_DIRECTORY_PATH);
  console.log(`Found ${files.length} file(s) under ${MEDIA_DIRECTORY_PATH}`);

  let uploaded = 0;
  let skipped = 0;

  for (const absolutePath of files) {
    const relativeKey = path.relative(MEDIA_DIRECTORY_PATH, absolutePath).split(path.sep).join("/");
    const extension = relativeKey.split(".").pop() || "";
    const contentType = safeContentTypeForExtension(extension) || "application/octet-stream";

    if (dryRun) {
      console.log(`DRY  ${relativeKey}`);
      skipped += 1;
      continue;
    }

    const buffer = readFileSync(absolutePath);
    const { url } = await storeMediaBytes({ relativeKey, buffer, contentType });
    console.log(`OK   ${relativeKey} → ${url}`);
    uploaded += 1;
  }

  console.log(`\nDone. uploaded=${uploaded} dryRun=${dryRun} skipped=${skipped}`);
  if (!dryRun && uploaded > 0) {
    console.log("Next: npm run rewrite:json-media-urls");
  }
}

main().catch((err) => {
  console.error("migrate-disk-media-to-r2 failed:", err.message || err);
  process.exitCode = 1;
});
