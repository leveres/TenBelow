# PostgreSQL backup and restore procedures

TenBelow uses Render-managed PostgreSQL as the post-migration source of truth. File-based JSON snapshots remain a **temporary read-only fallback** during migration verification only.

---

## Before any migration or schema change

### 1. Back up JSON data (current source of truth)

```bash
cd tenbelow-backend
export BACKEND_DATA_DIR="${BACKEND_DATA_DIR:-./data}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="tenbelow-json-backup-${STAMP}.tar.gz"

tar -czf "../${ARCHIVE}" -C "$(dirname "$BACKEND_DATA_DIR")" "$(basename "$BACKEND_DATA_DIR")"
echo "Created ${ARCHIVE}"
```

On Render, download or snapshot the persistent disk mounted at `/var/data` before maintenance.

### 2. Back up existing PostgreSQL data (if `DATABASE_URL` is set)

```bash
export DATABASE_URL='postgresql://...'
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
pg_dump "$DATABASE_URL" --format=custom --file="tenbelow-pg-backup-${STAMP}.dump"
echo "Created tenbelow-pg-backup-${STAMP}.dump"
```

Keep at least one backup off-host (local machine or object storage).

---

## Render-managed backups

1. Open the Render dashboard → PostgreSQL instance → **Backups**
2. Confirm automatic daily backups are enabled
3. Before maintenance window, trigger a **manual backup** if available on your plan
4. Record backup timestamp and instance id in your ops log

Render backups are the primary recovery path for production PostgreSQL.

---

## Logical backup with pg_dump (recommended for migrations)

### Full database (custom format — supports parallel restore)

```bash
pg_dump "$DATABASE_URL" \
  --format=custom \
  --no-owner \
  --no-acl \
  --file="tenbelow-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

### Schema only (for review)

```bash
pg_dump "$DATABASE_URL" --schema-only --file=tenbelow-schema.sql
```

### Data only (after schema applied elsewhere)

```bash
pg_dump "$DATABASE_URL" --data-only --format=custom --file=tenbelow-data.dump
```

---

## Restore procedures

### Restore from pg_dump (custom format)

**Warning:** This replaces data in the target database. Run only during a maintenance window.

```bash
export DATABASE_URL='postgresql://...'
pg_restore --clean --if-exists --no-owner --no-acl \
  --dbname="$DATABASE_URL" \
  tenbelow-YYYYMMDDTHHMMSSZ.dump
```

Verify after restore:

```bash
cd tenbelow-backend
npm run verify:prisma   # available after Phase 2 migration scripts land
npm run smoke:core
curl -s "$BASE_URL/ready"
```

### Restore from Render backup

1. Render dashboard → PostgreSQL → Backups → select backup → Restore
2. Render provisions a new database or restores in place per plan capabilities
3. Update `DATABASE_URL` on the web service if the connection string changes
4. Run verification scripts before re-enabling traffic

### Emergency fallback — JSON file restore (temporary, pre-Prisma cutover)

If PostgreSQL migration fails before cutover:

1. Set `STORAGE_BACKEND=json` (or unset Prisma flag)
2. Restore JSON tarball to `BACKEND_DATA_DIR`
3. Restart the backend service
4. Use admin **Snapshot Restore** at `/admin/review` only if individual document recovery is needed

Retire this path after `STORAGE_BACKEND=prisma` is verified in production.

---

## Post-migration verification checklist

- [ ] Row counts match dry-run report (`npm run migrate:prisma:dry-run`)
- [ ] FK integrity checks pass (`npm run verify:prisma`)
- [ ] Core smoke test passes (`npm run smoke:core`)
- [ ] `/ready` reports healthy with Postgres connectivity (after Phase 3)
- [ ] Sample buyer order, seller shipment, exchange, and review flows tested manually

---

## Retention guidance

| Asset | Minimum retention |
|-------|-------------------|
| Pre-migration JSON tarball | 90 days after successful Prisma cutover |
| Pre-migration pg_dump | 90 days after successful Prisma cutover |
| Render automatic backups | Per Render plan (keep enabled indefinitely) |
| File autosnapshots under `data/snapshots/` | Remove after Prisma cutover verified (7–14 days) |

---

## Related documents

- [postgres-migration-phase1.md](./postgres-migration-phase1.md) — schema and phase plan
- [runbook.md](./runbook.md) — deployment and legacy Postgres mirror notes
