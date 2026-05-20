#!/usr/bin/env node
/**
 * One-shot import of JSON data files into Postgres `tb_documents` table.
 * Usage: DATABASE_URL=... node scripts/migrate-json-to-pg.mjs
 */
import "dotenv/config";
import { readFileSync, existsSync } from "fs";
import path from "path";
import pg from "pg";
import { DATA_DIRECTORY_PATH } from "../storagePaths.js";

const { Client } = pg;

const entries = [
  ["products", "products.json"],
  ["config", "config.json"],
  ["sellers", "sellers.json"],
  ["buyers", "buyers.json"],
  ["orders", "orders.json"],
  ["drops", "drops.json"],
  ["productReviews", "product-reviews.json"],
  ["exchangeRequests", "exchange-requests.json"],
  ["customOrderRequests", "custom-order-requests.json"],
  ["webhookEvents", "webhook-events.json"],
];

function readJsonFile(absPath) {
  const raw = readFileSync(absPath, "utf8");
  return JSON.parse(raw);
}

async function main() {
  if (!String(process.env.DATABASE_URL || "").trim()) {
    console.error("DATABASE_URL is not set.");
    process.exit(1);
  }

  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS tb_documents (
        key TEXT PRIMARY KEY,
        body JSONB NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    for (const [key, filename] of entries) {
      const abs = path.join(DATA_DIRECTORY_PATH, filename);
      if (!existsSync(abs)) {
        console.warn(`skip missing ${filename}`);
        continue;
      }
      const body = readJsonFile(abs);
      await client.query(
        `INSERT INTO tb_documents (key, body, updated_at) VALUES ($1, $2::jsonb, NOW())
         ON CONFLICT (key) DO UPDATE SET body = EXCLUDED.body, updated_at = NOW()`,
        [key, JSON.stringify(body)]
      );
      console.log(`OK ${key}`);
    }

    const pushPath = path.join(DATA_DIRECTORY_PATH, "push_devices.json");
    if (existsSync(pushPath)) {
      const body = readJsonFile(pushPath);
      await client.query(
        `INSERT INTO tb_documents (key, body, updated_at) VALUES ($1, $2::jsonb, NOW())
         ON CONFLICT (key) DO UPDATE SET body = EXCLUDED.body, updated_at = NOW()`,
        ["push_devices", JSON.stringify(body)]
      );
      console.log("OK push_devices");
    }
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
