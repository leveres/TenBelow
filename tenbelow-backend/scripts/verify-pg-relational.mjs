#!/usr/bin/env node
/**
 * Verify relational Postgres rows against local managed JSON documents.
 *
 * Usage:
 *   DATABASE_URL=... node scripts/verify-pg-relational.mjs
 * Optional:
 *   STRICT=1 ...   # exit non-zero if any count mismatches
 */
import "dotenv/config";
import { existsSync, readFileSync } from "fs";
import path from "path";
import pg from "pg";
import { DATA_DIRECTORY_PATH } from "../storagePaths.js";

const { Client } = pg;
const strict = String(process.env.STRICT || "").trim() === "1";

function jsonAt(filename, fallbackValue) {
  const fullPath = path.join(DATA_DIRECTORY_PATH, filename);
  if (!existsSync(fullPath)) return fallbackValue;
  return JSON.parse(readFileSync(fullPath, "utf8"));
}

function countSupportMessagesFromOrders(orders) {
  if (!Array.isArray(orders)) return 0;
  return orders.reduce((sum, order) => {
    const req = Array.isArray(order?.supportRequests) ? order.supportRequests.length : 0;
    const msg = Array.isArray(order?.orderMessages) ? order.orderMessages.length : 0;
    return sum + req + msg;
  }, 0);
}

function countSupportMessagesFromInquiries(inquiries) {
  if (!Array.isArray(inquiries)) return 0;
  return inquiries.reduce((sum, thread) => {
    const messages = Array.isArray(thread?.messages) ? thread.messages.length : 0;
    return sum + (messages || 1);
  }, 0);
}

function countSellerMediaFromProducts(productsDoc) {
  const products = Array.isArray(productsDoc?.products) ? productsDoc.products : [];
  return products.reduce((sum, product) => {
    const images = Array.isArray(product?.imageURLs) ? product.imageURLs.filter(Boolean).length : 0;
    const demo = product?.demoVideoURL ? 1 : 0;
    const preview = product?.productionPreviewURL ? 1 : 0;
    return sum + images + demo + preview;
  }, 0);
}

function countSellerMediaFromSellers(sellers) {
  return Object.values(sellers || {}).reduce((sum, seller) => {
    const avatar = seller?.profile?.avatarURL ? 1 : 0;
    const banner = seller?.profile?.bannerURL ? 1 : 0;
    return sum + avatar + banner;
  }, 0);
}

async function main() {
  const databaseURL = String(process.env.DATABASE_URL || "").trim();
  if (!databaseURL) throw new Error("DATABASE_URL is required");

  const sellers = jsonAt("sellers.json", {});
  const buyers = jsonAt("buyers.json", {});
  const productsDoc = jsonAt("products.json", { products: [] });
  const orders = jsonAt("orders.json", []);
  const drops = jsonAt("drops.json", {});
  const exchanges = jsonAt("exchange-requests.json", jsonAt("exchanges.json", []));
  const reviews = jsonAt("product-reviews.json", jsonAt("reviews.json", []));
  const customOrderRequests = jsonAt("custom-order-requests.json", []);
  const sellerInquiries = jsonAt("seller-inquiries.json", jsonAt("inquiries.json", []));

  const expected = {
    sellers: Object.keys(sellers).length,
    creator_programs: Object.keys(sellers).length,
    buyers: Object.keys(buyers).length,
    products: Array.isArray(productsDoc?.products) ? productsDoc.products.length : 0,
    orders: Array.isArray(orders) ? orders.length : 0,
    weekly_drops: Object.keys(drops || {}).length,
    exchanges: Array.isArray(exchanges) ? exchanges.length : 0,
    reviews: Array.isArray(reviews) ? reviews.length : 0,
    support_messages:
      countSupportMessagesFromOrders(orders)
      + (Array.isArray(customOrderRequests) ? customOrderRequests.length : 0)
      + countSupportMessagesFromInquiries(sellerInquiries),
    seller_media:
      countSellerMediaFromProducts(productsDoc)
      + countSellerMediaFromSellers(sellers),
  };

  const client = new Client({ connectionString: databaseURL });
  await client.connect();
  try {
    const tables = Object.keys(expected);
    const actual = {};
    for (const table of tables) {
      const { rows } = await client.query(`SELECT COUNT(*)::int AS count FROM ${table}`);
      actual[table] = rows[0]?.count ?? 0;
    }

    let mismatches = 0;
    console.log("Relational verification summary:");
    for (const table of tables) {
      const ok = actual[table] === expected[table];
      if (!ok) mismatches += 1;
      console.log(
        `${ok ? "OK " : "!! "} ${table.padEnd(16)} expected=${String(expected[table]).padStart(6)} actual=${String(actual[table]).padStart(6)}`
      );
    }

    if (mismatches > 0) {
      console.warn(`Found ${mismatches} table count mismatch(es).`);
      if (strict) {
        process.exitCode = 2;
      }
    } else {
      console.log("All relational table counts match current JSON snapshots.");
    }
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error("verify-pg-relational failed:", error.message || error);
  process.exit(1);
});

