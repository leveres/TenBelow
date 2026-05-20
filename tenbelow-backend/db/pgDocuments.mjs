/**
 * Optional Postgres backing store for managed JSON documents (see MANAGED_DATA_TARGETS in server.js).
 * Set DATABASE_URL. Use PG_READS=1 to load from DB into memory on startup.
 */
import pg from "pg";

const { Pool } = pg;

let pool = null;

export function isPgEnabled() {
  return Boolean(String(process.env.DATABASE_URL || "").trim());
}

export function getPool() {
  if (!isPgEnabled()) return null;
  if (!pool) {
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: Number.parseInt(process.env.PG_POOL_MAX || "10", 10),
    });
  }
  return pool;
}

export async function ensureSchema() {
  const p = getPool();
  if (!p) return;
  await p.query(`
    CREATE TABLE IF NOT EXISTS tb_documents (
      key TEXT PRIMARY KEY,
      body JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

/**
 * @param {string} key
 * @param {unknown} body JSON-serializable
 */
export async function upsertDocumentRow(key, body) {
  const p = getPool();
  if (!p) return;
  await ensureSchema();
  await p.query(
    `INSERT INTO tb_documents (key, body, updated_at)
     VALUES ($1, $2::jsonb, NOW())
     ON CONFLICT (key) DO UPDATE SET body = EXCLUDED.body, updated_at = NOW()`,
    [key, JSON.stringify(body ?? null)]
  );
}

/**
 * @param {Map<string, unknown>} targetMap
 */
export async function loadAllDocumentsInto(targetMap) {
  const p = getPool();
  if (!p) return;
  await ensureSchema();
  const { rows } = await p.query("SELECT key, body FROM tb_documents");
  for (const row of rows) {
    targetMap.set(row.key, row.body);
  }
}

export async function closePool() {
  if (pool) {
    await pool.end().catch(() => {});
    pool = null;
  }
}
