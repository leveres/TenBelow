#!/usr/bin/env node
/**
 * One-shot production Postgres setup for Phase 1 (JSON remains authoritative).
 *
 * Usage (use External Database URL from Render when running locally):
 *   cd TenBelow/tenbelow-backend
 *   DATABASE_URL='postgresql://...' npm run setup:postgres:phase1
 *
 * Optional:
 *   STRICT=1  — exit non-zero if verify fails
 */
import "dotenv/config";
import { applyDatabaseUrlToEnv } from "../db/prisma/databaseUrl.js";
import { disconnectPrisma, isPrismaConfigured } from "../db/prisma/client.js";
import { syncPhase1ToPrisma } from "../db/repositories/phase1.js";
import { runPhase1ComparisonReport } from "../db/repositories/phase1.js";
import { execSync } from "node:child_process";

async function testConnection() {
  const { getPrisma } = await import("../db/prisma/client.js");
  const prisma = getPrisma();
  if (!prisma) throw new Error("Prisma client unavailable");
  await prisma.$queryRaw`SELECT 1 AS ok`;
}

async function main() {
  const databaseUrl = applyDatabaseUrlToEnv();
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }

  const host = (() => {
    try {
      return new URL(databaseUrl).hostname;
    } catch {
      return "(invalid url)";
    }
  })();

  console.log("TenBelow Postgres Phase 1 setup");
  console.log(`Host: ${host}`);
  console.log("JSON on disk remains the marketplace source of truth.\n");

  console.log("1/4 Applying Prisma migrations...");
  execSync("npx prisma migrate deploy", { stdio: "inherit", env: process.env });

  console.log("\n2/4 Testing database connection...");
  await testConnection();
  console.log("Connection OK.");

  console.log("\n3/4 Syncing Phase 1 entities from local JSON (BACKEND_DATA_DIR)...");
  const syncResult = await syncPhase1ToPrisma();
  console.log(JSON.stringify(syncResult, null, 2));

  console.log("\n4/4 Verifying JSON vs Prisma...");
  const strict = String(process.env.STRICT || "").trim() === "1";
  const { allOk, skipped, reason } = await runPhase1ComparisonReport({ log: false, print: true });

  if (skipped) {
    throw new Error(reason || "Comparison skipped");
  }
  if (strict && !allOk) {
    process.exitCode = 2;
    console.error("\nSetup finished with mismatches (STRICT=1).");
    return;
  }

  console.log(allOk ? "\nSetup complete — Phase 1 repositories match JSON." : "\nSetup finished with mismatches — review report above.");
}

main()
  .catch((err) => {
    console.error("\nsetup-postgres-phase1 failed:", err.message || err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await disconnectPrisma();
  });
