/**
 * Normalize DATABASE_URL for Render and other hosted Postgres providers.
 */
function hostNeedsHostedPostgresSsl(hostname = "") {
  const host = String(hostname || "").toLowerCase();
  return host.includes("render.com") || host.startsWith("dpg-");
}

export function normalizeDatabaseUrl(rawUrl = process.env.DATABASE_URL) {
  const trimmed = String(rawUrl || "").trim();
  if (!trimmed) return "";

  let url;
  try {
    url = new URL(trimmed);
  } catch {
    return trimmed;
  }

  const needsSsl =
    hostNeedsHostedPostgresSsl(url.hostname) ||
    String(process.env.DATABASE_SSL_REQUIRE || "").trim() === "1";

  if (needsSsl) {
    if (!url.searchParams.has("sslmode")) {
      url.searchParams.set("sslmode", "require");
    }
    // pg v8+ warns when sslmode is set without libpq-compatible semantics; pg v9 will change defaults.
    if (!url.searchParams.has("uselibpqcompat")) {
      url.searchParams.set("uselibpqcompat", "true");
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
