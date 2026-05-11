import { appendFileSync, existsSync, readFileSync } from "fs";
import path from "path";
import { DATA_DIRECTORY_PATH } from "./storagePaths.js";

const AUDIT_LOG_PATH = path.join(DATA_DIRECTORY_PATH, "audit-log.jsonl");

/** Default max lines returned by readAuditLogTail (public/admin small reads). */
const PUBLIC_TAIL_MAX = 500;

/**
 * Upper bound for operator scans (incident history, metrics). Override via AUDIT_LOG_MAX_SCAN_LINES.
 * Capped to avoid OOM on accidental huge files.
 */
export const AUDIT_LOG_SCAN_MAX = Math.max(
  5000,
  Math.min(250000, Number(process.env.AUDIT_LOG_MAX_SCAN_LINES) || 50000)
);

/**
 * Append one JSON line to the data-directory audit log (newline-delimited JSON).
 */
export function auditLog(entry) {
  try {
    const line =
      JSON.stringify({
        ts: new Date().toISOString(),
        ...entry,
      }) + "\n";
    appendFileSync(AUDIT_LOG_PATH, line, "utf8");
  } catch (err) {
    console.warn("auditLog:", err?.message || err);
  }
}

export function clientIp(req) {
  const xff = req.headers["x-forwarded-for"];
  if (typeof xff === "string" && xff.length) {
    return xff.split(",")[0].trim();
  }
  return req.socket?.remoteAddress || req.ip || "";
}

/**
 * @param {number} limit - desired number of newest entries
 * @param {{ maxCap?: number }} [options] - maxCap defaults to PUBLIC_TAIL_MAX; use AUDIT_LOG_SCAN_MAX for large scans
 */
export function readAuditLogTail(limit = 100, options = {}) {
  const maxCap = Number.isFinite(options.maxCap) ? options.maxCap : PUBLIC_TAIL_MAX;
  const maxEntries = Math.max(1, Math.min(maxCap, Number(limit) || 100));
  if (!existsSync(AUDIT_LOG_PATH)) return [];

  try {
    const raw = readFileSync(AUDIT_LOG_PATH, "utf8");
    const lines = raw
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .slice(-maxEntries);

    return lines
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return { ts: new Date().toISOString(), action: "audit_line_parse_failed", raw: line };
        }
      })
      .reverse();
  } catch (err) {
    return [
      {
        ts: new Date().toISOString(),
        action: "audit_log_read_failed",
        error: err?.message || String(err),
      },
    ];
  }
}
