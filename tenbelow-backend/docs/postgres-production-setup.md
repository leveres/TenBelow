# Render PostgreSQL — production setup checklist

Use this once when wiring **tenbelow_postgres_prod** to **tenbelow-backend**. JSON on `/var/data` stays the marketplace source of truth until you approve a later cutover.

**Security:** Never commit `DATABASE_URL` or paste passwords in chat. If a password was exposed, rotate it in Render → Postgres → **Reset credentials**.

---

## 1. Render Postgres service

You already have a database (e.g. `tenbelow_postgres_prod`). Confirm in the dashboard:

- Status: **Available**
- Plan has **automatic backups** enabled

---

## 2. Wire environment on the web service

Dashboard → **tenbelow-backend** → **Environment**:

| Variable | Value | Notes |
|----------|--------|--------|
| `DATABASE_URL` | **Internal Database URL** from the Postgres page | Same region as the web service |
| `PG_READS` | `0` | Keep JSON as read source |
| `PRISMA_SYNC` | `1` | After JSON writes, update Phase 1 Prisma tables |
| `PRISMA_BOOTSTRAP_SYNC` | **unset or `0`** | Do **not** run full JSON sync on every boot (use repair script once) |
| `PG_RELATIONAL_MIRROR` | **unset or `0`** | Legacy mirror DDL conflicts with Prisma — leave off |

Do **not** set `PG_READS=1` until after a planned maintenance cutover.

**Start command:** `npm run start:production`  
(runs `prisma migrate deploy` → `sync:legal-documents` → `node server.js`)

**Save** → Render redeploys the web service.

Internal URL format (example):

```text
postgresql://USER:PASSWORD@dpg-xxxxx-a/DATABASE_NAME
```

For commands run **on your Mac**, use the **External Database URL** from the same Postgres page (hostname includes `.render.com`).

---

## 3. If you see `The column 'email' does not exist` on boot

Production Postgres was likely baselined while the old **pgRelational** mirror tables were present. Those tables use the same names (`buyers`, `sellers`, `products`, …) but a different shape than Prisma Phase 1.

**Fix once** (Render Shell, after backup):

```bash
cd ~/project/src/tenbelow-backend   # path shown in Render shell
CONFIRM_REPAIR=1 STRICT=1 npm run repair:prisma:phase1
```

This script:

1. Drops conflicting Prisma/legacy mirror tables (keeps `tb_documents`)
2. Re-applies Prisma migrations from scratch
3. Re-seeds legal agreement documents
4. Syncs JSON → Prisma and verifies

Then set env as in section 2 and redeploy. You should **not** need `PRISMA_BOOTSTRAP_SYNC=1` afterward.

See [postgres-backup-restore.md](./postgres-backup-restore.md) before running repair.

---

## 4. First-time setup (empty DB, no legacy mirror)

### Option A — from your Mac (uses repo `data/` or `BACKEND_DATA_DIR`)

```bash
cd tenbelow-backend
export DATABASE_URL='postgresql://...EXTERNAL URL from Render...'
export DATABASE_SSL_REQUIRE=1
STRICT=1 npm run setup:postgres:phase1
```

### Option B — on Render (production JSON on disk)

After deploy with `start:production`:

```bash
npm run sync:prisma:phase1
STRICT=1 npm run verify:prisma:phase1
```

Production JSON lives on Render disk (`/var/data`), not in git.

---

## 5. Verify everything

### Readiness (no admin key)

```bash
curl -s https://tenbelow.onrender.com/ready | jq .
```

Look for:

- `checks.databaseUrlConfigured`: `true`
- `checks.postgresReachable`: `true`

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
| Source of truth | JSON on persistent disk |
| Legacy `pgRelational.mjs` | Off by default when `DATABASE_URL` + Prisma are active |

Postgres is a **validated mirror** for Phase 1 and seller legal/welcome email; the app does not read orders or checkout from Postgres yet.

---

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `The column 'email' does not exist` on bootstrap sync | Run `CONFIRM_REPAIR=1 npm run repair:prisma:phase1` (section 3) |
| `legal_agreement_documents does not exist` | Ensure start command is `npm run start:production`; or run `npm run sync:legal-documents` in shell |
| `Can't reach database server` from Mac | Use **External** URL + `DATABASE_SSL_REQUIRE=1` |
| Verify mismatches after deploy | Run `npm run sync:prisma:phase1` in Render shell |
| `postgresReachable: false` on `/ready` | Check `DATABASE_URL`, Postgres status, redeploy |
| Password rotated | Update `DATABASE_URL` on web service |

---

## 8. Backups

- Enable Render Postgres automatic backups
- Before schema repair: `pg_dump` — see [postgres-backup-restore.md](./postgres-backup-restore.md)

---

## Related

- [postgres-migration-phase1.md](./postgres-migration-phase1.md)
- [seller-welcome-email-setup.md](./seller-welcome-email-setup.md)
- [runbook.md](./runbook.md)
