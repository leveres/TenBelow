import { isPrismaConfigured } from "../prisma/client.js";
import { logComparisonReport, printReportSummary } from "./compareUtils.js";
import { syncUsersToPrisma, compareUsers } from "./userRepository.js";
import { syncCreatorProfilesToPrisma, compareCreatorProfiles } from "./creatorProfileRepository.js";
import { syncProductsToPrisma, compareProducts } from "./productRepository.js";
import { syncVariantsToPrisma, compareVariants } from "./productVariantRepository.js";
import { syncCategoriesToPrisma, compareCategories } from "./categoryRepository.js";

export const PHASE1_SYNC_ORDER = [
  "users",
  "creatorProfiles",
  "categories",
  "products",
  "productVariants",
];

export function isPhase1CompareEnabled() {
  return String(process.env.PRISMA_COMPARE || "").trim() === "1";
}

export function isPhase1SyncEnabled() {
  return String(process.env.PRISMA_SYNC || "").trim() === "1";
}

export async function syncPhase1ToPrisma() {
  if (!isPrismaConfigured()) {
    return { skipped: true, reason: "DATABASE_URL not configured" };
  }

  const users = await syncUsersToPrisma();
  const creatorProfiles = await syncCreatorProfilesToPrisma();
  const categories = await syncCategoriesToPrisma();
  const products = await syncProductsToPrisma();
  const productVariants = await syncVariantsToPrisma();

  return {
    users,
    creatorProfiles,
    categories,
    products,
    productVariants,
  };
}

export async function comparePhase1Repositories() {
  if (!isPrismaConfigured()) {
    return {
      skipped: true,
      reason: "DATABASE_URL not configured",
      reports: [],
      allOk: false,
    };
  }

  const users = await compareUsers();
  const reports = [
    users.buyers,
    users.sellers,
    await compareCreatorProfiles(),
    await compareCategories(),
    await compareProducts(),
    await compareVariants(),
  ];
  const allOk = reports.every((report) => report.ok);
  return { reports, allOk };
}

export async function runPhase1ComparisonReport({ log = true, print = false } = {}) {
  const { reports, allOk, skipped, reason } = await comparePhase1Repositories();
  if (skipped) {
    if (log) console.warn(`[prisma-compare:phase1] skipped — ${reason}`);
    return { allOk: false, skipped: true, reason, reports: [] };
  }
  if (log) {
    for (const report of reports) {
      logComparisonReport(report);
    }
  }
  if (print) {
    printReportSummary(reports);
  }
  return { allOk, reports };
}

let compareInFlight = false;
let lastCompareAt = 0;
const COMPARE_COOLDOWN_MS = 30_000;

/** Fire-and-forget compare after JSON reads when PRISMA_COMPARE=1. */
export function schedulePhase1Compare(trigger = "read") {
  if (!isPhase1CompareEnabled() || !isPrismaConfigured()) return;
  const now = Date.now();
  if (compareInFlight || now - lastCompareAt < COMPARE_COOLDOWN_MS) return;
  compareInFlight = true;
  lastCompareAt = now;
  runPhase1ComparisonReport({ log: true })
    .catch((err) => console.error(`[prisma-compare:phase1] ${trigger} failed:`, err?.message || err))
    .finally(() => {
      compareInFlight = false;
    });
}

/** Sync Phase 1 entities after JSON writes when PRISMA_SYNC=1. */
export async function syncPhase1AfterJsonWrite(managedKey) {
  if (!isPhase1SyncEnabled() || !isPrismaConfigured()) return;
  try {
    switch (managedKey) {
      case "buyers":
      case "sellers":
        await syncUsersToPrisma();
        await syncCreatorProfilesToPrisma();
        break;
      case "products":
        await syncCategoriesToPrisma();
        await syncProductsToPrisma();
        await syncVariantsToPrisma();
        break;
      default:
        break;
    }
  } catch (err) {
    console.error(`[prisma-sync:phase1] failed after ${managedKey} write:`, err?.message || err);
  }
}
