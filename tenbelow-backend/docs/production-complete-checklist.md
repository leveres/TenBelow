# Production complete checklist (one session)

Use this when you want TenBelow **fully wired for production** — no partial R2 config, no “come back later” media migration.

**Order matters.** Do Cloudflare + Render env first, redeploy, then run migration on Render shell, then verify app + Postgres.

---

## 1. Cloudflare R2 (15 min)

1. **Cloudflare dashboard → Storage & databases → R2**
2. Create bucket (e.g. `tenbelow`)
3. **Settings → Public access** → enable public bucket URL (or custom domain)
4. Copy **Public bucket URL** → `https://pub-xxxxx.r2.dev` (no trailing slash)
5. **R2 → Manage R2 API tokens → Create API token**
   - Permissions: Object Read & Write on your bucket
   - Copy **Access Key ID** and **Secret Access Key**
6. Note your **Account ID** (R2 overview)
7. **S3 endpoint:** `https://{ACCOUNT_ID}.r2.cloudflarestorage.com`

**Do not use Hyperdrive** — TenBelow Postgres is on Render, not Cloudflare Workers.

---

## 2. Render environment (all at once)

**Render → tenbelow-backend → Environment**

Set these **together** (never leave a partial subset):

| Variable | Value |
|----------|--------|
| `S3_MEDIA_BUCKET` | `tenbelow` (your bucket name) |
| `S3_MEDIA_REGION` | `auto` |
| `AWS_ACCESS_KEY_ID` | R2 token access key |
| `AWS_SECRET_ACCESS_KEY` | R2 token secret |
| `S3_ENDPOINT` | `https://ACCOUNT_ID.r2.cloudflarestorage.com` |
| `S3_FORCE_PATH_STYLE` | `true` |
| `PUBLIC_MEDIA_BASE_URL` | `https://pub-xxxxx.r2.dev` |

**Keep unchanged:**

| Variable | Value |
|----------|--------|
| `BACKEND_URL` | `https://tenbelow.onrender.com` |
| `BACKEND_DATA_DIR` | `/var/data` |
| `DATABASE_URL` | Render Postgres internal URL |
| `APP_API_KEY` | Must match iOS `TENBELOW_APP_API_KEY` |
| Stripe, Resend, auth secrets | (already set) |

Save → **Manual Deploy** → wait for live.

---

## 3. Verify R2 is active

```bash
curl -s https://tenbelow.onrender.com/ready | jq '.checks | {mediaStorageMode, mediaStorageReady, mediaStoragePartialConfig, objectStorageEnabled}'
```

Expected:

```json
{
  "mediaStorageMode": "object_storage",
  "mediaStorageReady": true,
  "objectStorageEnabled": true
}
```

`mediaStoragePartialConfig` must be **absent** or `false`.

---

## 4. Migrate existing disk files → R2 (Render shell)

**Render → tenbelow-backend → Shell** (production env is already loaded):

```bash
cd tenbelow-backend

# Preview files that would upload
DRY_RUN=1 npm run migrate:disk-media-to-r2

# Upload all /var/data/media/* to R2 (same object keys)
npm run migrate:disk-media-to-r2

# Rewrite sellers.json + products.json URLs to PUBLIC_MEDIA_BASE_URL
npm run rewrite:json-media-urls
```

Or one command:

```bash
npm run setup:r2-production
```

**Restart the service** after rewriting JSON (clears in-memory document cache):

Render → **Manual Deploy** once more, or restart the instance.

---

## 5. Postgres Phase 1 (if not done)

On the same Render shell:

```bash
cd tenbelow-backend
STRICT=1 npm run verify:prisma:phase1
```

Fix any mismatches with:

```bash
npm run sync:prisma:phase1
STRICT=1 npm run verify:prisma:phase1
```

Full relational path (optional, separate from Phase 1 Prisma):

```bash
npm run release:checklist
```

---

## 6. iOS app

1. Confirm **TENBELOW_BACKEND_BASE_URL** = `https://tenbelow.onrender.com`
2. Confirm **TENBELOW_APP_API_KEY** matches Render `APP_API_KEY`
3. **Product → Clean Build Folder → Run** on device

---

## 7. End-to-end smoke test

| Test | Pass criteria |
|------|----------------|
| Edit Profile → avatar + banner → Save | Images show on dashboard and public store |
| New product photo upload | URL starts with `PUBLIC_MEDIA_BASE_URL`; Safari opens **200** |
| `GET /ready` | `mediaStorageMode: "object_storage"` |
| Buyer catalog | Product images load |

---

## Quick commands reference

```bash
npm run print:media-storage-checklist   # env + /ready probe
npm run test:media-storage              # local upload smoke (needs full R2 env)
npm run setup:r2-production             # migrate disk → R2 + rewrite JSON
STRICT=1 npm run verify:prisma:phase1   # Postgres Phase 1 parity
```

See [media-storage-setup.md](./media-storage-setup.md) for troubleshooting partial R2 config and disk fallback details.
