#!/usr/bin/env node
/**
 * Rewrite media URL strings in sellers.json + products.json to PUBLIC_MEDIA_BASE_URL.
 * Run after migrate:disk-media-to-r2 (or when switching from Render /media URLs to R2).
 *
 * Usage:
 *   npm run rewrite:json-media-urls
 *   DRY_RUN=1 npm run rewrite:json-media-urls
 */
import "dotenv/config";
import { readFileSync, writeFileSync } from "fs";
import {
  isObjectStorageEnabled,
  mediaRelativeKeyFromReference,
} from "../mediaObjectStorage.js";
import { DATA_DIRECTORY_PATH } from "../storagePaths.js";
import path from "path";

const publicBase = String(process.env.PUBLIC_MEDIA_BASE_URL || "").trim().replace(/\/$/, "");
const backendBase = String(process.env.BACKEND_URL || "http://localhost:3000").replace(/\/$/, "");

function rewriteReference(value) {
  if (value == null) return value;
  const trimmed = String(value).trim();
  if (!trimmed) return value;

  const relativeKey = mediaRelativeKeyFromReference(trimmed);
  if (!relativeKey) return value;

  if (isObjectStorageEnabled() && publicBase) {
    return `${publicBase}/${relativeKey}`;
  }

  return `${backendBase}/media/${relativeKey}`;
}

function rewriteStringFields(obj, keys) {
  if (!obj || typeof obj !== "object") return 0;
  let changes = 0;
  for (const key of keys) {
    if (!(key in obj)) continue;
    if (typeof obj[key] === "string") {
      const next = rewriteReference(obj[key]);
      if (next !== obj[key]) {
        obj[key] = next;
        changes += 1;
      }
    } else if (Array.isArray(obj[key])) {
      obj[key] = obj[key].map((item) => {
        if (typeof item !== "string") return item;
        const next = rewriteReference(item);
        if (next !== item) changes += 1;
        return next;
      });
    }
  }
  return changes;
}

function main() {
  if (!isObjectStorageEnabled() || !publicBase) {
    throw new Error("Object storage and PUBLIC_MEDIA_BASE_URL must be configured.");
  }

  const dryRun = String(process.env.DRY_RUN || "").trim() === "1";
  const sellersPath = path.join(DATA_DIRECTORY_PATH, "sellers.json");
  const productsPath = path.join(DATA_DIRECTORY_PATH, "products.json");

  const sellersDoc = JSON.parse(readFileSync(sellersPath, "utf8"));
  const productsDoc = JSON.parse(readFileSync(productsPath, "utf8"));

  let changes = 0;

  for (const seller of Object.values(sellersDoc.sellers || sellersDoc || {})) {
    if (!seller || typeof seller !== "object") continue;
    if (seller.profile) {
      changes += rewriteStringFields(seller.profile, ["avatarURL", "bannerURL"]);
    }
  }

  for (const product of productsDoc.products || []) {
    changes += rewriteStringFields(product, [
      "imageURLs",
      "demoVideoURL",
      "productionPreviewURL",
    ]);
  }

  console.log(`References rewritten: ${changes} (dryRun=${dryRun})`);

  if (!dryRun && changes > 0) {
    writeFileSync(sellersPath, `${JSON.stringify(sellersDoc, null, 2)}\n`);
    writeFileSync(productsPath, `${JSON.stringify(productsDoc, null, 2)}\n`);
    console.log(`Updated ${sellersPath}`);
    console.log(`Updated ${productsPath}`);
  }
}

main();
