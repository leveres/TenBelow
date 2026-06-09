#!/usr/bin/env node
/**
 * Safe migration: import managed JSON documents + relational rows.
 *
 * Usage:
 *   DATABASE_URL=... node scripts/migrate-json-to-pg-relational.mjs
 * Optional:
 *   DRY_RUN=1 DATABASE_URL=... node scripts/migrate-json-to-pg-relational.mjs
 */
import "dotenv/config";
import { existsSync, readFileSync } from "fs";
import path from "path";
import { DATA_DIRECTORY_PATH } from "../storagePaths.js";
import { closePool, ensureSchema, upsertDocumentRow } from "../db/pgDocuments.mjs";
import { ensureRelationalSchema, upsertRelationalForManagedDocument } from "../db/pgRelational.mjs";

const dryRun = String(process.env.DRY_RUN || "").trim() === "1";

const DOCUMENT_CANDIDATES = [
  { key: "products", filenames: ["products.json"] },
  { key: "config", filenames: ["config.json"] },
  { key: "sellers", filenames: ["sellers.json"] },
  { key: "buyers", filenames: ["buyers.json"] },
  { key: "orders", filenames: ["orders.json"] },
  { key: "drops", filenames: ["drops.json"] },
  { key: "productReviews", filenames: ["product-reviews.json", "reviews.json"] },
  { key: "exchangeRequests", filenames: ["exchange-requests.json", "exchanges.json"] },
  { key: "customOrderRequests", filenames: ["custom-order-requests.json", "support-requests.json"] },
  { key: "sellerInquiries", filenames: ["seller-inquiries.json", "inquiries.json", "support-messages.json"] },
  { key: "webhookEvents", filenames: ["webhook-events.json"] },
  { key: "push_devices", filenames: ["push_devices.json"] },
];

function readJSON(pathname) {
  return JSON.parse(readFileSync(pathname, "utf8"));
}

function resolveFirstExisting(filenames) {
  for (const filename of filenames) {
    const fullPath = path.join(DATA_DIRECTORY_PATH, filename);
    if (existsSync(fullPath)) return { filename, fullPath };
  }
  return null;
}

async function main() {
  if (!String(process.env.DATABASE_URL || "").trim()) {
    throw new Error("DATABASE_URL is required");
  }

  try {
    await ensureSchema();
    await ensureRelationalSchema();

    let migratedDocuments = 0;
    for (const candidate of DOCUMENT_CANDIDATES) {
      const resolved = resolveFirstExisting(candidate.filenames);
      if (!resolved) {
        console.warn(`skip ${candidate.key}: no file found (${candidate.filenames.join(", ")})`);
        continue;
      }

      const payload = readJSON(resolved.fullPath);
      if (dryRun) {
        console.log(`[dry-run] would migrate ${candidate.key} from ${resolved.filename}`);
        migratedDocuments += 1;
        continue;
      }

      if (candidate.key !== "push_devices") {
        await upsertDocumentRow(candidate.key, payload);
        await upsertRelationalForManagedDocument(candidate.key, payload);
        console.log(`migrated ${candidate.key} from ${resolved.filename}`);
      } else {
        await upsertDocumentRow("push_devices", payload);
        console.log("migrated push_devices");
      }
      migratedDocuments += 1;
    }

    console.log(
      dryRun
        ? `[dry-run] checked ${migratedDocuments} document sources`
        : `migration complete (${migratedDocuments} document sources)`
    );
  } finally {
    await closePool();
  }
}

main().catch((error) => {
  console.error("migration failed:", error);
  process.exit(1);
});

