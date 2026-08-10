import { isPrismaConfigured } from "./prisma/client.js";

/**
 * Legacy JSON→Postgres mirror (pgRelational.mjs) uses the same table names as Prisma
 * Phase 1 but a different column layout. When Prisma is configured, keep the mirror
 * off unless explicitly re-enabled for debugging.
 */
export function isPgRelationalMirrorEnabled() {
  const flag = String(process.env.PG_RELATIONAL_MIRROR || "").trim();
  if (flag === "1") return true;
  if (flag === "0") return false;
  return !isPrismaConfigured();
}
