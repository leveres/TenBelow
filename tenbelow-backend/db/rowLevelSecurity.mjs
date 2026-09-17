/**
 * Defense in depth for Postgres.
 * The iOS app never connects to the database. This locks tables so only the
 * backend database role can read or write them if another role is added later.
 */
const SENSITIVE_TABLES = [
  "tb_documents",
  "buyers",
  "sellers",
  "products",
  "orders",
  "weekly_drops",
  "exchanges",
  "reviews",
  "support_messages",
  "seller_media",
  "creator_programs",
  "payments",
  "refunds",
  "product_reviews",
  "exchange_requests",
  "order_messages",
  "inquiry_messages",
  "seller_inquiry_threads",
  "push_devices",
  "custom_order_requests",
];

export async function enforceRowLevelSecurity(pool) {
  if (!pool) return;
  const { rows } = await pool.query("SELECT current_user AS role_name, current_setting('is_superuser') AS is_superuser");
  const roleName = rows[0]?.role_name;
  if (!roleName) return;

  if (rows[0]?.is_superuser === "on") {
    console.warn(
      "Postgres role is a superuser, so row-level security cannot block that role. Use a non-superuser DATABASE_URL role in production."
    );
  }

  for (const tableName of SENSITIVE_TABLES) {
    const exists = await pool.query("SELECT to_regclass($1) AS relation", [tableName]);
    if (!exists.rows[0]?.relation) continue;

    await pool.query(`ALTER TABLE ${quoteIdent(tableName)} ENABLE ROW LEVEL SECURITY`);
    await pool.query(`ALTER TABLE ${quoteIdent(tableName)} FORCE ROW LEVEL SECURITY`);
    await pool.query(`DROP POLICY IF EXISTS tenbelow_backend_access ON ${quoteIdent(tableName)}`);
    await pool.query(
      `CREATE POLICY tenbelow_backend_access ON ${quoteIdent(tableName)}
       FOR ALL
       TO ${quoteIdent(roleName)}
       USING (true)
       WITH CHECK (true)`
    );
    await pool.query(`REVOKE ALL ON TABLE ${quoteIdent(tableName)} FROM PUBLIC`);
  }

  console.log(`Row-level security enforced for backend role ${roleName}`);
}

function quoteIdent(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}
