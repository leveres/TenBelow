/**
 * Normalize DATABASE_URL for Render and other hosted Postgres providers.
 */
export function normalizeDatabaseUrl(rawUrl = process.env.DATABASE_URL) {
  const trimmed = String(rawUrl || "").trim();
  if (!trimmed) return "";

  let url;
  try {
    url = new URL(trimmed);
  } catch {
    return trimmed;
  }

  if (!url.searchParams.has("sslmode")) {
    const host = url.hostname.toLowerCase();
    const needsSsl =
      host.includes("render.com") ||
      host.startsWith("dpg-") ||
      String(process.env.DATABASE_SSL_REQUIRE || "").trim() === "1";
    if (needsSsl) {
      url.searchParams.set("sslmode", "require");
    }
  }

  return url.toString();
}

export function applyDatabaseUrlToEnv() {
  const normalized = normalizeDatabaseUrl();
  if (normalized) {
    process.env.DATABASE_URL = normalized;
  }
  return normalized;
}
