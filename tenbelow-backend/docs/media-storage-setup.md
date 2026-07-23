# Media storage — disk now, R2 later

TenBelow serves seller/product media through the backend. **Phase 1 (launch)** uses the Render persistent disk. **Phase 2 (scale)** switches to Cloudflare R2 when every object-storage env var is set together.

**Do not use Cloudflare Hyperdrive** for media or Postgres — Postgres lives on Render; media uses disk or R2.

---

## Phase 1 — Disk on Render (use this now)

Media files: `/var/data/media/` on the Render disk (mounted at `BACKEND_DATA_DIR`).

Public URLs: `https://tenbelow.onrender.com/media/{sellerId}/{productId}/{file}`

### Render → tenbelow-backend → Environment

**Keep (required for marketplace + media on disk):**

| Variable | Value |
|----------|--------|
| `BACKEND_URL` | `https://tenbelow.onrender.com` |
| `BACKEND_DATA_DIR` | `/var/data` |
| `DATABASE_URL` | Internal Postgres URL from Render |
| `APP_API_KEY` | Same as iOS `TENBELOW_APP_API_KEY` |
| `AUTH_JWT_SECRET` or shared secret material | (already set) |
| Stripe, Resend, etc. | (already set) |

**Remove for Phase 1** (partial R2 config breaks photo uploads):

| Variable | Action |
|----------|--------|
| `S3_MEDIA_BUCKET` | **Delete** |
| `S3_MEDIA_REGION` | **Delete** |
| `AWS_ACCESS_KEY_ID` | **Delete** |
| `AWS_SECRET_ACCESS_KEY` | **Delete** |
| `S3_ENDPOINT` | **Delete** |
| `PUBLIC_MEDIA_BASE_URL` | **Delete** |
| `S3_FORCE_PATH_STYLE` | **Delete** (optional; harmless if left) |

Save → redeploy.

### Verify after deploy

```bash
curl -s https://tenbelow.onrender.com/ready | jq '.checks | {mediaStorageMode, mediaStorageReady, mediaDirectoryWritable, backendUrlConfigured, mediaStoragePartialConfig}'
```

Expected:

```json
{
  "mediaStorageMode": "disk",
  "mediaStorageReady": true,
  "mediaDirectoryWritable": true,
  "backendUrlConfigured": true
}
```

No `mediaStoragePartialConfig: true`.

Local checklist:

```bash
cd tenbelow-backend
npm run print:media-storage-checklist
npm run test:media-storage
```

### iOS app

Rebuild from Xcode after backend deploy (includes R2 → `/media/` fallback for stale profile URLs).

Test: **Store → Edit Profile** → photo + banner → **Save Changes** → dashboard and **View stores** show images.

### Disk budget

Starter disk is **1 GB** (`render.yaml`). Monitor usage in Render. Plan R2 cutover before heavy video uploads or hundreds of large images.

---

## Phase 2 — Full Cloudflare R2 (when ready)

Only enable when you can set **all** variables in one session and verify a test upload returns **HTTP 200** from the public URL.

### Cloudflare (R2)

1. **Storage & databases → R2** → bucket (e.g. `tenbelow`)
2. **Manage public access** → allow public read (or custom domain)
3. Note **Public bucket URL** (e.g. `https://pub-xxxxx.r2.dev`)
4. **R2 → Manage R2 API tokens** → Create token with Object Read & Write on that bucket
5. Note **Account ID**, **Access Key ID**, **Secret Access Key**
6. **S3 API endpoint**: `https://{account_id}.r2.cloudflarestorage.com`

### Render → tenbelow-backend → Environment (add all at once)

| Variable | Example / notes |
|----------|------------------|
| `S3_MEDIA_BUCKET` | `tenbelow` |
| `S3_MEDIA_REGION` | `auto` |
| `AWS_ACCESS_KEY_ID` | From R2 API token |
| `AWS_SECRET_ACCESS_KEY` | From R2 API token |
| `S3_ENDPOINT` | `https://ACCOUNT_ID.r2.cloudflarestorage.com` |
| `S3_FORCE_PATH_STYLE` | `true` |
| `PUBLIC_MEDIA_BASE_URL` | `https://pub-xxxxx.r2.dev` (no trailing slash) |

Keep `BACKEND_URL` and `BACKEND_DATA_DIR` unchanged.

### Verify R2 cutover

```bash
curl -s https://tenbelow.onrender.com/ready | jq '.checks | {mediaStorageMode, objectStorageEnabled, mediaStorageReady}'
# mediaStorageMode: "object_storage"
# objectStorageEnabled: true

npm run test:media-storage
```

Upload one test image from the app, then open the returned URL in Safari — must be **200**, not 404.

### Existing media on disk

After R2 is live, either:

- **Re-save** seller profiles / products from the app (simplest at current scale), or
- **Copy** `/var/data/media/*` into the R2 bucket preserving keys (`sellerId/productId/file.ext`), then re-save profiles so URLs update.

The backend rewrites stale CDN URLs to `/media/...` on disk mode; after R2, new uploads use `PUBLIC_MEDIA_BASE_URL`.

---

## Quick reference — env template (do not commit secrets)

Copy to a password manager / Render dashboard when doing Phase 2:

```bash
# Phase 1 — disk only (no lines below)
BACKEND_URL=https://tenbelow.onrender.com
BACKEND_DATA_DIR=/var/data

# Phase 2 — add ALL of these together
# S3_MEDIA_BUCKET=tenbelow
# S3_MEDIA_REGION=auto
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# S3_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
# S3_FORCE_PATH_STYLE=true
# PUBLIC_MEDIA_BASE_URL=https://pub-xxxxx.r2.dev
```

See also: [postgres-production-setup.md](./postgres-production-setup.md) for database wiring.
