# Weekly Drop — seller submit testing guide

Use this to test the full seller flow from submission through buyer visibility.

---

## Prerequisites

| Requirement | How to verify |
|-------------|----------------|
| Seller account signed in | Store tab shows your dashboard |
| Active seller membership | Seller hub / subscription shows active |
| Profile saved on server | Edit Profile → Save succeeds |
| Real product photos | URLs load from R2 (`pub-….r2.dev`) |

```bash
curl -s https://tenbelow.onrender.com/ready | jq '.checks.mediaStorageMode'
# "object_storage"
```

---

## Submission window (ET)

Drop submissions are only accepted during:

**Thursday 5:00 PM → 11:59 PM Eastern**

Outside that window, the app shows a countdown and the API returns:

```json
{ "error": "Drop submissions are only open Thursday from 5:00 PM through 11:59 PM ET." }
```

The buyer-facing drop goes **live Friday 12:00 AM ET** through **Sunday night**.

---

## Step-by-step (seller app)

1. **Store → Weekly Drop** tab  
2. Tap **Prepare weekly drop** (or equivalent CTA when window is open)  
3. **Create Weekly Drop** product:
   - Name, price **over $10.00** ($10.01+)
   - At least one **uploaded photo** (not a placeholder)
   - Material, durability, care warnings
   - Drop headline / story / best use case
   - Product rights section completed  
4. **Submit** — should show “Drop product submitted”  
5. **Weekly Drop hub** → “Your submissions” lists the product (status: submitted)

---

## Admin approval (required before buyers see it)

Submitted products are **`approvalStatus: submitted`** until approved.

On Render shell or with admin credentials:

```bash
curl -s -X POST "https://tenbelow.onrender.com/admin/products/PRODUCT_ID/review" \
  -H "Content-Type: application/json" \
  -H "X-Admin-API-Key: YOUR_ADMIN_KEY" \
  -d '{"decision":"approve","notes":"Weekly drop test"}'
```

Replace `PRODUCT_ID` with the id from the submission (shown in seller hub or `GET /drop/my-submissions/:sellerId`).

After approval:
- Product becomes `isApproved: true`, `isDrop: true`
- Included in `/drop/current` when the weekend window is live

---

## Verify API

```bash
# Current buyer lineup
curl -s -H "X-TenBelow-App-Key: YOUR_APP_KEY" \
  https://tenbelow.onrender.com/drop/current | jq '{active, products: [.products[] | {name, sellerId, priceCents}]}'

# Your submissions (seller JWT required)
curl -s -H "X-TenBelow-App-Key: YOUR_APP_KEY" \
  -H "Authorization: Bearer SELLER_JWT" \
  https://tenbelow.onrender.com/drop/my-submissions/lll | jq .
```

---

## Common failures

| Symptom | Cause | Fix |
|---------|--------|-----|
| “Active seller membership required” | No paid subscription | Complete seller membership checkout |
| “Submissions only open Thursday…” | Outside ET window | Wait for Thu 5pm ET or test on Thursday |
| “Drop products must be over $10” | Price ≤ $10.00 | Set price to $10.01 or higher |
| Empty buyer Weekly Drop | Nothing approved yet | Admin approve submission |
| Mock sellers in lineup | Old app build | Rebuild; seed sellers filtered in latest code |
| Photos don’t upload | R2 misconfigured | Check `/ready` → `object_storage` |

---

## Shipping & policies (now server-backed)

**Store → Manage shipping / Manage policies → Save** syncs to:

- `PUT /seller-store-settings/:sellerId`

Settings persist across devices and simulator resets. Dashboard chips read from the same cached settings after sync.

```bash
curl -s -H "X-TenBelow-App-Key: YOUR_APP_KEY" \
  -H "Authorization: Bearer SELLER_JWT" \
  https://tenbelow.onrender.com/seller-store-settings/lll | jq .
```

---

## DEBUG-only preview

In **DEBUG** builds, the Weekly Drop toolbar **Preview** menu simulates schedule phases. Release builds use **live data only** — no mock seed products.
