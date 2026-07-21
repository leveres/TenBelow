#!/usr/bin/env node
/**
 * Compare JSON source-of-truth reads against Phase 1 Prisma repositories.
 *
 * Usage:
 *   DATABASE_URL=... npm run sync:prisma:phase1
 *   DATABASE_URL=... npm run verify:prisma:phase1
 *   STRICT=1 DATABASE_URL=... npm run verify:prisma:phase1
 */
import "dotenv/config";
import { disconnectPrisma, isPrismaConfigured } from "../db/prisma/client.js";
import { runPhase1ComparisonReport } from "../db/repositories/phase1.js";

async function main() {
  if (!isPrismaConfigured()) {
    throw new Error("DATABASE_URL is required");
  }

  const strict = String(process.env.STRICT || "").trim() === "1";
  const { allOk, reports, skipped, reason } = await runPhase1ComparisonReport({ log: false, print: true });

  if (skipped) {
    console.warn(`Skipped: ${reason}`);
    process.exitCode = 1;
    return;
  }

  if (strict && !allOk) {
    process.exitCode = 2;
  }
}

main()
  .catch((err) => {
    console.error("verify-prisma-phase1 failed:", err.message || err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await disconnectPrisma();
  });
