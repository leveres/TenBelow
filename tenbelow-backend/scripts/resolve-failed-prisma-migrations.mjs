#!/usr/bin/env node
/**
 * Diagnose and optionally resolve Prisma P3009 (failed migrations block deploy).
 *
 * Run on Render Shell (Internal DATABASE_URL is already set):
 *   npm run prisma:resolve-failed
 *
 * Auto-fix known safe cases (e.g. color columns already exist):
 *   CONFIRM_RESOLVE=1 npm run prisma:resolve-failed
 */
import "dotenv/config";
import { execSync } from "node:child_process";
import { applyDatabaseUrlToEnv } from "../db/prisma/databaseUrl.js";
import { getPool } from "../db/pgDocuments.mjs";

const COLOR_MIGRATION = "20260819190000_product_color_options";

function run(command) {
  execSync(command, { stdio: "inherit", env: process.env });
}

async function columnExists(pool, tableName, columnName) {
  const { rows } = await pool.query(
    `
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = $1
      AND column_name = $2
    LIMIT 1
    `,
    [tableName, columnName]
  );
  return rows.length > 0;
}

async function listFailedMigrations(pool) {
  const { rows } = await pool.query(`
    SELECT migration_name, started_at, finished_at, rolled_back_at, logs
    FROM "_prisma_migrations"
    WHERE finished_at IS NULL
      AND rolled_back_at IS NULL
    ORDER BY started_at ASC
  `);
  return rows;
}

async function colorMigrationApplied(pool) {
  const checks = [
    ["products", "available_colors"],
    ["order_items", "selected_color_id"],
    ["order_items", "selected_color_name"],
    ["order_items", "selected_color_hex"],
  ];
  for (const [table, column] of checks) {
    if (!(await columnExists(pool, table, column))) {
      return false;
    }
  }
  return true;
}

async function resolveColorMigration(pool, { autoFix }) {
  const applied = await colorMigrationApplied(pool);
  if (applied) {
    console.log(
      `\n${COLOR_MIGRATION}: schema changes are present — marking migration as applied.`
    );
    if (!autoFix) {
      console.log(`Run: CONFIRM_RESOLVE=1 npm run prisma:resolve-failed`);
      return false;
    }
    run(`npx prisma migrate resolve --applied ${COLOR_MIGRATION}`);
    return true;
  }

  console.log(
    `\n${COLOR_MIGRATION}: columns missing — mark rolled back, then redeploy to retry:`
  );
  console.log(`  npx prisma migrate resolve --rolled-back ${COLOR_MIGRATION}`);
  return false;
}

async function main() {
  const databaseUrl = applyDatabaseUrlToEnv();
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }

  const pool = getPool();
  if (!pool) throw new Error("Postgres pool unavailable");

  await pool.query("SELECT 1");

  const failed = await listFailedMigrations(pool);
  if (!failed.length) {
    console.log("No failed Prisma migrations in _prisma_migrations.");
    console.log("If deploy still fails, run: npx prisma migrate deploy");
    return;
  }

  console.log(`Found ${failed.length} failed migration(s):\n`);
  for (const row of failed) {
    console.log(`- ${row.migration_name}`);
    console.log(`  started_at: ${row.started_at}`);
    if (row.logs) {
      console.log(`  logs: ${String(row.logs).trim().slice(0, 500)}`);
    }
  }

  const autoFix = String(process.env.CONFIRM_RESOLVE || "").trim() === "1";
  let resolvedAny = false;

  for (const row of failed) {
    if (row.migration_name === COLOR_MIGRATION) {
      if (await resolveColorMigration(pool, { autoFix })) {
        resolvedAny = true;
      }
      continue;
    }

    console.log(
      `\n${row.migration_name}: no auto-fix — inspect logs above, repair schema manually, then:`
    );
    console.log(`  npx prisma migrate resolve --applied ${row.migration_name}`);
    console.log("  — or —");
    console.log(`  npx prisma migrate resolve --rolled-back ${row.migration_name}`);
  }

  if (resolvedAny) {
    console.log("\nRe-running migrate deploy...");
    run("npx prisma migrate deploy");
    console.log("\nResolved. Trigger a Render redeploy or restart the service.");
  } else if (!autoFix) {
    console.log("\nDry run only. To apply safe fixes: CONFIRM_RESOLVE=1 npm run prisma:resolve-failed");
  }
}

main().catch((err) => {
  console.error("\nresolve-failed-prisma-migrations failed:", err.message || err);
  process.exitCode = 1;
});
