/**
 * Prisma client singleton for TenBelow backend.
 * Phase 1: scaffolding only — runtime still uses JSON persistence by default.
 */
import { PrismaClient } from "@prisma/client";

let prisma = null;

export function isPrismaConfigured() {
  return Boolean(String(process.env.DATABASE_URL || "").trim());
}

/**
 * @returns {PrismaClient | null}
 */
export function getPrisma() {
  if (!isPrismaConfigured()) return null;
  if (!prisma) {
    prisma = new PrismaClient({
      log: process.env.PRISMA_LOG_QUERIES === "1" ? ["query", "error", "warn"] : ["error", "warn"],
    });
  }
  return prisma;
}

export async function disconnectPrisma() {
  if (prisma) {
    await prisma.$disconnect();
    prisma = null;
  }
}
