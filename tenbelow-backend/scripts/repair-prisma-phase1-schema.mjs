#!/usr/bin/env node
/**
 * One-time production repair when Postgres has legacy pgRelational tables that conflict
 * with Prisma Phase 1 (e.g. buyers.id PK vs buyers.email PK).
 *
 * Run on Render Shell after backing up Postgres (see docs/postgres-backup-restore.md):
 *   CONFIRM_REPAIR=1 npm run repair:prisma:phase1
 *
 * Optional:
 *   STRICT=1 — exit non-zero if verify fails
 *   SKIP_SYNC=1 — only rebuild schema (no JSON→Prisma sync)
 */
import "dotenv/config";
import { execSync } from "node:child_process";
import { applyDatabaseUrlToEnv } from "../db/prisma/databaseUrl.js";
import { disconnectPrisma, getPrisma } from "../db/prisma/client.js";
import { runPhase1ComparisonReport, syncPhase1ToPrisma } from "../db/repositories/phase1.js";
import { syncLegalAgreementDocumentsToPrisma } from "../db/repositories/legalAgreementRepository.js";
import { getPool } from "../db/pgDocuments.mjs";

const MIGRATIONS_NEWEST_FIRST = [
  "20260819190000_product_color_options",
  "20260809033000_seller_welcome_email",
  "20260721013000_add_categories",
  "20260721000000_init",
];

const LEGACY_MIRROR_TABLES = [
  "support_messages",
  "seller_media",
  "creator_programs",
];

const PRISMA_TABLES = [
  "seller_agreement_acceptances",
  "legal_agreement_documents",
  "seller_agreements",
  "founding_creator_access",
  "seller_memberships",
  "seller_profiles",
  "product_media",
  "product_rights",
  "product_variants",
  "inventory_items",
  "cart_items",
  "carts",
  "order_items",
  "shipments",
  "seller_orders",
  "payment_transfers",
  "payments",
  "refunds",
  "exchange_timeline_events",
  "exchange_proof_assets",
  "exchange_requests",
  "drop_entries",
  "weekly_drops",
  "support_evidence_assets",
  "support_requests",
  "order_messages",
  "custom_order_requests",
  "inquiry_messages",
  "seller_inquiry_threads",
  "notification_deliveries",
  "push_devices",
  "moderation_records",
  "audit_log_entries",
  "processed_webhook_events",
  "seller_media_assets",
  "product_reviews",
  "orders",
  "products",
  "categories",
  "sellers",
  "buyers",
  "app_config",
];

function requireConfirmation() {
  if (String(process.env.CONFIRM_REPAIR || "").trim() !== "1") {
    throw new Error(
      "Refusing to run without CONFIRM_REPAIR=1. Back up Postgres first (docs/postgres-backup-restore.md)."
    );
  }
}

function run(command) {
  execSync(command, { stdio: "inherit", env: process.env });
}

async function dropConflictingObjects(pool) {
  const tables = [...new Set([...PRISMA_TABLES, ...LEGACY_MIRROR_TABLES])];
  const tableList = tables.map((name) => `"${name}"`).join(", ");
  console.log(`Dropping ${tables.length} Prisma/legacy mirror tables (CASCADE)...`);
  await pool.query(`DROP TABLE IF EXISTS ${tableList} CASCADE`);

  const { rows: enums } = await pool.query(`
    SELECT t.typname
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e'
  `);
  if (enums.length) {
    console.log(`Dropping ${enums.length} public enum types...`);
    for (const row of enums) {
      await pool.query(`DROP TYPE IF EXISTS "${row.typname}" CASCADE`);
    }
  }
}

async function rollbackMigrations() {
  console.log("Marking Prisma migrations as rolled back (newest first)...");
  for (const migration of MIGRATIONS_NEWEST_FIRST) {
    try {
      run(`npx prisma migrate resolve --rolled-back ${migration}`);
    } catch (err) {
      console.warn(`  skipped ${migration}:`, err?.message || err);
    }
  }
}

async function verifyBuyersSchema() {
  const prisma = getPrisma();
  if (!prisma) throw new Error("Prisma client unavailable");
  const rows = await prisma.$queryRaw`
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'buyers'
  `;
  const columns = new Set(rows.map((row) => row.column_name));
  if (!columns.has("email")) {
    throw new Error("Repair incomplete: buyers.email column is still missing.");
  }
}

async function main() {
  requireConfirmation();

  const databaseUrl = applyDatabaseUrlToEnv();
  if (!databaseUrl) throw new Error("DATABASE_URL is required");

  const host = (() => {
    try {
      return new URL(databaseUrl).hostname;
    } catch {
      return "(invalid url)";
    }
  })();

  console.log("TenBelow Prisma Phase 1 schema repair");
  console.log(`Host: ${host}`);
  console.log("JSON on disk remains the marketplace source of truth.\n");
  console.log("tb_documents (managed JSON blobs) is preserved.\n");

  const pool = getPool();
  if (!pool) throw new Error("Postgres pool unavailable");

  await pool.query("SELECT 1");
  console.log("Postgres connection OK.\n");

  await dropConflictingObjects(pool);
  await rollbackMigrations();

  console.log("\nApplying Prisma migrations...");
  run("npx prisma migrate deploy");

  await verifyBuyersSchema();
  console.log("Schema check OK (buyers.email present).\n");

  console.log("Syncing legal agreement documents...");
  const legalResult = await syncLegalAgreementDocumentsToPrisma();
  console.log(JSON.stringify(legalResult, null, 2));

  if (String(process.env.SKIP_SYNC || "").trim() === "1") {
    console.log("\nSKIP_SYNC=1 — skipping Phase 1 JSON sync.");
    return;
  }

  console.log("\nSyncing Phase 1 entities from JSON on disk...");
  const syncResult = await syncPhase1ToPrisma();
  console.log(JSON.stringify(syncResult, null, 2));

  console.log("\nVerifying JSON vs Prisma...");
  const strict = String(process.env.STRICT || "").trim() === "1";
  const { allOk, skipped, reason } = await runPhase1ComparisonReport({ log: false, print: true });
  if (skipped) throw new Error(reason || "Comparison skipped");
  if (strict && !allOk) {
    process.exitCode = 2;
    console.error("\nRepair finished with mismatches (STRICT=1).");
    return;
  }

  console.log(
    allOk
      ? "\nRepair complete — Prisma Phase 1 schema matches JSON."
      : "\nRepair finished with mismatches — review report above."
  );
}

main()
  .catch((err) => {
    console.error("\nrepair-prisma-phase1-schema failed:", err.message || err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await disconnectPrisma();
  });
