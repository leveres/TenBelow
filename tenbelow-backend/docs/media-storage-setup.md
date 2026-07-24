# Media storage — production R2 (recommended)

For a **single end-to-end production setup** (Cloudflare R2 + migration + verify), start here:

**→ [production-complete-checklist.md](./production-complete-checklist.md)**

**Do not use Cloudflare Hyperdrive** for media or Postgres — Postgres lives on Render; media uses disk (local dev) or R2 (production).

---

## Production — Cloudflare R2

Set **all** object-storage env vars in one session. Partial config (e.g. only `PUBLIC_MEDIA_BASE_URL`) breaks uploads — files land on disk while JSON points at R2 (404 in app).

### Cloudflare

1. **Storage & databases → R2** → create bucket (e.g. `tenbelow`)
2. **Public access** → enable public bucket URL (or custom domain)
3. Copy **Public bucket URL** (e.g. `https://pub-xxxxx.r2.dev`, no trailing slash)
4. **R2 → Manage R2 API tokens** → Object Read & Write on that bucket
5. Note **Account ID**, **Access Key ID**, **Secret Access Key**
6. **S3 endpoint:** `https://{ACCOUNT_ID}.r2.cloudflarestorage.com`

### Render → tenbelow-backend → Environment

| Variable | Example |
|----------|---------|
| `S3_MEDIA_BUCKET` | `tenbelow` |
| `S3_MEDIA_REGION` | `auto` |
| `AWS_ACCESS_KEY_ID` | From R2 token |
| `AWS_SECRET_ACCESS_KEY` | From R2 token |
| `S3_ENDPOINT` | `https://ACCOUNT_ID.r2.cloudflarestorage.com` |
| `S3_FORCE_PATH_STYLE` | `true` |
| `PUBLIC_MEDIA_BASE_URL` | `https://pub-xxxxx.r2.dev` |

Also keep: `BACKEND_URL`, `BACKEND_DATA_DIR`, `DATABASE_URL`, `APP_API_KEY`, Stripe, Resend, auth secrets.

Save → redeploy.

### Verify

```bash
curl -s https://tenbelow.onrender.com/ready | jq '.checks | {mediaStorageMode, mediaStorageReady, mediaStoragePartialConfig, objectStorageEnabled}'
```

Expected: `mediaStorageMode: "object_storage"`, `mediaStorageReady: true`, no partial config.

```bash
cd tenbelow-backend
npm run print:media-storage-checklist
npm run test:media-storage
```

Upload one image from the app; open the returned URL in Safari — must be **HTTP 200**.

### Migrate existing disk files

After R2 is live, on **Render shell**:

```bash
cd tenbelow-backend
DRY_RUN=1 npm run migrate:disk-media-to-r2   # preview
npm run setup:r2-production                  # upload + rewrite JSON URLs
```

Then **manual deploy** once (reloads in-memory JSON cache).

---

## Local dev / disk fallback

Without S3 env vars, media writes to `BACKEND_DATA_DIR/media/` and serves at `{BACKEND_URL}/media/...`.

**Remove** all `S3_*`, `AWS_*`, and `PUBLIC_MEDIA_BASE_URL` on Render if you are not doing full R2 yet — partial vars cause broken profile photos.

```bash
curl -s https://tenbelow.onrender.com/ready | jq '.checks | {mediaStorageMode, mediaStorageReady, mediaDirectoryWritable, mediaStoragePartialConfig}'
```

Expected disk mode:

```json
{
  "mediaStorageMode": "disk",
  "mediaStorageReady": true,
  "mediaDirectoryWritable": true
}
```

Disk budget on Render starter: **1 GB** (`render.yaml`). R2 avoids disk limits for marketplace media.

---

## Env template (do not commit secrets)

```bash
BACKEND_URL=https://tenbelow.onrender.com
BACKEND_DATA_DIR=/var/data

# Production R2 — set ALL together
# S3_MEDIA_BUCKET=tenbelow
# S3_MEDIA_REGION=auto
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# S3_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
# S3_FORCE_PATH_STYLE=true
# PUBLIC_MEDIA_BASE_URL=https://pub-xxxxx.r2.dev
```

See also: [postgres-production-setup.md](./postgres-production-setup.md).
