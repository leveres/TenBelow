#!/usr/bin/env node
/**
 * Sync Phase 1 entities from JSON (source of truth) into normalized Prisma tables.
 * Does not modify JSON files or remove pgRelational mirror behavior.
 */
import "dotenv/config";
import { disconnectPrisma, isPrismaConfigured } from "../db/prisma/client.js";
import { syncPhase1ToPrisma, PHASE1_SYNC_ORDER } from "../db/repositories/phase1.js";

async function main() {
  if (!isPrismaConfigured()) {
    throw new Error("DATABASE_URL is required");
  }

  const dryRun = String(process.env.DRY_RUN || "").trim() === "1";
  console.log("TenBelow Phase 1 JSON → Prisma sync");
  console.log(`Order: ${PHASE1_SYNC_ORDER.join(" → ")}`);
  if (dryRun) {
    console.log("DRY_RUN=1 — no database writes will be performed.");
    return;
  }

  const result = await syncPhase1ToPrisma();
  console.log(JSON.stringify(result, null, 2));
  console.log("Phase 1 sync complete.");
}

main()
  .catch((err) => {
    console.error("sync-json-to-prisma-phase1 failed:", err.message || err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await disconnectPrisma();
  });
