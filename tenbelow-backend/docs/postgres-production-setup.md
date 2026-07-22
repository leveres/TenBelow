# Render PostgreSQL — production setup checklist

Use this once when wiring **tenbelow_postgres_prod** to **tenbelow-backend**. JSON on `/var/data` stays the marketplace source of truth until you approve a later cutover.

**Security:** Never commit `DATABASE_URL` or paste passwords in chat. If a password was exposed, rotate it in Render → Postgres → **Reset credentials**.

---

## 1. Render Postgres service

You already have a database (e.g. `tenbelow_postgres_prod`). Confirm in the dashboard:

- Status: **Available**
- Plan has **automatic backups** enabled

---

## 2. Wire `DATABASE_URL` on the web service

Dashboard → **tenbelow-backend** → **Environment**:

| Variable | Value | Notes |
|----------|--------|--------|
| `DATABASE_URL` | **Internal Database URL** from the Postgres page | Same region as the web service |
| `PG_READS` | `0` | Keep JSON as read source (already in `render.yaml`) |
| `PRISMA_SYNC` | `1` | After JSON writes, update Phase 1 Prisma tables |
| `PRISMA_BOOTSTRAP_SYNC` | `1` | On each deploy/restart, sync JSON → Prisma (safe at current scale) |

Do **not** set `PG_READS=1` until after a planned maintenance cutover.

**Save** → Render redeploys the web service.

Internal URL format (example):

```text
postgresql://USER:PASSWORD@dpg-xxxxx-a/DATABASE_NAME
```

For commands run **on your Mac**, use the **External Database URL** from the same Postgres page (hostname includes `.render.com`).

---

## 3. Deploy applies schema automatically

After the latest backend deploy, each start runs:

1. `npm run prisma:generate` (build)
2. `prisma migrate deploy` (start)
3. Phase 1 bootstrap sync (if `PRISMA_BOOTSTRAP_SYNC=1`)
4. `node server.js`

No manual migration step on Render unless bootstrap fails (see troubleshooting).

---

## 4. First-time bootstrap (if DB is empty)

### Option A — from your Mac (uses repo `data/` or `BACKEND_DATA_DIR`)

```bash
cd tenbelow-backend
export DATABASE_URL='postgresql://...EXTERNAL URL from Render...'
export DATABASE_SSL_REQUIRE=1
STRICT=1 npm run setup:postgres:phase1
```

This runs: migrate → connect test → sync from local JSON → verify.

Production JSON lives on Render disk (`/var/data`), not in git. For **production data**, use Option B.

### Option B — on Render (production JSON on disk)

Dashboard → **tenbelow-backend** → **Shell**:

```bash
cd ~/project/src/tenbelow-backend   # path may vary; use repo root shown in shell
npm run sync:prisma:phase1
STRICT=1 npm run verify:prisma:phase1
```

Or rely on `PRISMA_BOOTSTRAP_SYNC=1` after deploy (reads JSON from `/var/data`).

---

## 5. Verify everything

### Readiness (no admin key)

```bash
curl -s https://tenbelow.onrender.com/ready | jq .
```

Look for:

- `checks.databaseUrlConfigured`: `true`
- `checks.postgresReachable`: `true`
- Existing checks: disk, Stripe, email, auth

### Phase 1 JSON vs Prisma (Render shell or local with external URL)

```bash
STRICT=1 npm run verify:prisma:phase1
```

All sections should be **OK**:

- `users.buyers`, `users.sellers`
- `creatorProfiles`
- `categories`
- `products`
- `productVariants`

### Legacy mirror (optional)

```bash
curl -s -H "X-Admin-Key: $ADMIN_API_KEY" https://tenbelow.onrender.com/admin/pg-relational-health | jq .
```

### Marketplace smoke

```bash
BASE_URL=https://tenbelow.onrender.com npm run smoke:core
```

---

## 6. What stays the same (no marketplace breakage)

| Component | Behavior |
|-----------|----------|
| Checkout / orders | Unchanged — still JSON |
| API URLs & responses | Unchanged |
| iOS app | Unchanged |
| `pgRelational.mjs` | Still runs as temporary mirror when `DATABASE_URL` is set |
| Source of truth | JSON on persistent disk |

Postgres is a **validated mirror** for Phase 1; the app does not read orders or checkout from Postgres yet.

---

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Can't reach database server` from Mac | Use **External** URL + `DATABASE_SSL_REQUIRE=1` |
| `Can't reach database server` on Render | Use **Internal** URL on web service, same region |
| Verify mismatches after deploy | Run `npm run sync:prisma:phase1` in Render shell |
| `postgresReachable: false` on `/ready` | Check `DATABASE_URL`, Postgres status, redeploy |
| Password rotated | Update `DATABASE_URL` on web service |

---

## 8. Backups

- Enable Render Postgres automatic backups
- Before major migration: `pg_dump` — see [postgres-backup-restore.md](./postgres-backup-restore.md)

---

## Related

- [postgres-migration-phase1.md](./postgres-migration-phase1.md)
- [runbook.md](./runbook.md)
