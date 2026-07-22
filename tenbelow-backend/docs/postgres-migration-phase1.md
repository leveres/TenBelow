# PostgreSQL + Prisma Migration — Phase 1 Plan

This document supersedes the exploratory migration analysis and reflects approved production decisions.

**Backend:** `tenbelow-backend/`  
**Scope:** Phase 1 only — schema, tooling, documentation, and Prisma client scaffolding. No route rewrites, no deletion of JSON persistence, no Swift changes.

---

## Approved decisions

### 1. Schema style — fully normalized

All core marketplace data uses normalized PostgreSQL tables with foreign keys and indexes. JSONB is reserved for:

- Raw Stripe / App Store provider payloads
- Non-critical flexible metadata
- Before/after snapshots on audit rows where shape varies

Core entities are **not** stored as large JSONB blobs. The existing `pgRelational.mjs` `payload JSONB` pattern is **not** carried forward into Prisma.

### 2. Cutover strategy — maintenance-window bulk migration

The app has not publicly launched. There is **no long-term JSON/PostgreSQL dual-write**.

| Step | Action |
|------|--------|
| 1 | Back up all JSON under `BACKEND_DATA_DIR` and any existing Postgres data |
| 2 | Run dry-run migration report (`npm run migrate:prisma:dry-run`) |
| 3 | Enable maintenance window |
| 4 | Run bulk migration (`npm run migrate:json-to-prisma`) |
| 5 | Compare record counts and FK relationships (`npm run verify:prisma`) |
| 6 | Test Prisma-backed routes on staging |
| 7 | Switch reads/writes to Prisma (`STORAGE_BACKEND=prisma`) |
| 8 | Keep JSON files read-only for short verification period |
| 9 | Retire JSON writes and file-based snapshot restore |

### 3. Snapshots and backups

- **Primary recovery:** Render-managed PostgreSQL backups + documented `pg_dump` procedures ([postgres-backup-restore.md](./postgres-backup-restore.md))
- **Temporary fallback:** Existing file-based snapshot restore (read-only during verification only)
- **Not building:** A second custom PostgreSQL snapshot system

### 4. Push devices and audit logs — migrate in Phase 1 schema

**PushDevice** table supports:

- Multiple devices per user
- Enabled/disabled status
- Token refresh and invalidation
- Platform and app environment
- Last seen timestamp
- Logout/revocation (`revokedAt`)

**AuditLogEntry** table is append-only and records:

- Actor (type + id)
- Action
- Target type and target id
- Before/after metadata (JSONB, optional)
- Timestamp
- Request/correlation id
- IP address (when safely available)
- Admin and moderation actions

### 5. Existing `pg` dual-write — brief validation only

- Keep `pgDocuments.mjs` / `pgRelational.mjs` during Prisma validation
- Remove mirror and dual-write code after Prisma migration, verification, integration tests, and route checks pass
- **Final production path:** Prisma only

---

## Domain mapping (JSON → normalized tables)

| Current JSON / embedded shape | Prisma models |
|------------------------------|---------------|
| `buyers.json` | `Buyer` |
| `sellers.json` (account + profile + membership) | `Seller`, `SellerProfile`, `SellerMembership`, `FoundingCreatorAccess` |
| `products.json` | `Product`, `ProductMedia`, `ProductRights`, `ProductVariant`, `InventoryItem` |
| Cart (client-only today) | `Cart`, `CartItem` (schema ready; empty at migration) |
| `orders.json` | `Order`, `SellerOrder`, `Shipment`, `OrderItem` |
| Stripe PaymentIntent (not persisted today) | `Payment`, `PaymentTransfer` |
| Support refunds (not persisted today) | `Refund` |
| `product-reviews.json` | `ProductReview` |
| `exchange-requests.json` | `ExchangeRequest`, `ExchangeProofAsset`, `ExchangeTimelineEvent` |
| `drops.json` | `WeeklyDrop`, `DropEntry` |
| `custom-order-requests.json` | `CustomOrderRequest` |
| `seller-inquiries.json` | `SellerInquiryThread`, `InquiryMessage` |
| Order embedded support/messages | `SupportRequest`, `SupportEvidenceAsset`, `OrderMessage` |
| `webhook-events.json` | `ProcessedWebhookEvent` |
| `push_devices.json` | `PushDevice` |
| `audit-log.jsonl` | `AuditLogEntry` |
| Push sends (not persisted today) | `NotificationDelivery` |
| Admin product review | `ModerationRecord` |
| `config.json` | `AppConfig` |
| Seller/product media uploads | `SellerMediaAsset` |

**Naming note:** In the current API, a seller-scoped order slice is embedded as `order.shipments[]`. In the normalized schema this becomes `SellerOrder` (commercial slice) + `Shipment` (fulfillment) + `OrderItem` rows. API response assembly in later phases will reconstruct the existing JSON shape.

---

## Phase 1 deliverables (this phase)

| Deliverable | Status |
|-------------|--------|
| Updated plan (this document) | ✅ |
| Backup/restore runbook | ✅ |
| `prisma/schema.prisma` — full normalized schema | ✅ |
| Prisma client singleton (`db/prisma/client.js`) | ✅ |
| npm scripts: `prisma:generate`, `prisma:validate`, dry-run report | ✅ |
| `db/repositories/phase1.js` — orchestrator | ✅ |
| Phase 1 repositories (users, profiles, products, variants, categories) | ✅ |
| `sync:prisma:phase1` / `verify:prisma:phase1` scripts | ✅ |
| Route cutover | Phase 3+ |

---

## Phase 1 constraints (do not violate)

- Do **not** rewrite all routes at once
- Do **not** delete old persistence files or `pgRelational.mjs`
- Do **not** change API response shapes without documenting required changes first
- Do **not** alter the Swift app

---

## Environment variables (future cutover)

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL connection string (required for Prisma) |
| `STORAGE_BACKEND` | `json` (default) → `prisma` after cutover |
| `PG_READS` | Legacy; deprecated once `STORAGE_BACKEND=prisma` |

During Phase 1, default runtime behavior remains JSON file persistence unchanged.

Optional Phase 1 repository flags (JSON remains authoritative):

| Variable | Purpose |
|----------|---------|
| `PRISMA_SYNC=1` | After JSON writes to buyers/sellers/products, upsert Phase 1 Prisma tables |
| `PRISMA_COMPARE=1` | After JSON reads, log JSON vs Prisma mismatch reports (30s cooldown) |

Sync and verify:

```bash
cd tenbelow-backend
DATABASE_URL=... npm run sync:prisma:phase1
DATABASE_URL=... npm run verify:prisma:phase1
STRICT=1 DATABASE_URL=... npm run verify:prisma:phase1
```

---

## Commit sequence (Phase 1)

1. Migration plan document
2. Backup/restore procedures
3. Prisma dependencies and npm scripts
4. Normalized `schema.prisma`
5. Prisma client module + dry-run report script
6. Runbook cross-links

---

## Phase 2 preview (not started)

- `scripts/migrate-json-to-prisma.mjs` — bulk import in dependency order inside transactions
- `scripts/verify-prisma.mjs` — count and FK checks vs JSON source
- Repository modules per aggregate
- First route wired behind feature flag

---

## Known API shape preservation items (document before changing)

These computed/joined fields are added at read time today and must be reconstructed from normalized tables:

| Field | Source today |
|-------|--------------|
| `product.averageRating`, `product.reviewCount` | Aggregated from reviews |
| `order.deliveredAt`, exchange summary fields | `exchangePolicy.attachExchangeSummariesToOrders` |
| `seller` public profile in list endpoints | `buildSellerProfile()` aggregation |
| `sellerScopedOrder` | Filters shipments to authenticated seller |

No response shape changes in Phase 1.
