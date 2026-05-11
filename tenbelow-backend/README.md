# TenBelow Backend Deployment

This backend is an Express + Stripe service intended to run as a long-lived web process.

## Why a persistent disk is required

The backend stores live application state on disk:

- `products.json`
- `config.json`
- `sellers.json`
- `orders.json`
- `drops.json`
- uploaded media under `media/`
- push device registrations

In production, mount a persistent disk and point `BACKEND_DATA_DIR` at it.

## Render blueprint

A starter Render blueprint lives at the repo root in `render.yaml`.

Recommended settings:

- Root directory: `tenbelow-backend`
- Build command: `npm install`
- Start command: `npm start`
- Health check path: `/config`
- Persistent disk mount path: `/var/data`
- `BACKEND_DATA_DIR=/var/data`

## Required environment variables

- `BACKEND_URL=https://your-backend-domain.com`
- `BACKEND_DATA_DIR=/var/data`
- `STRIPE_SECRET_KEY=sk_test_...` or `sk_live_...`
- `STRIPE_WEBHOOK_SECRET=whsec_...`

Optional but recommended:

- `RESEND_API_KEY=re_...`
- `EMAIL_FROM=TenBelow <orders@yourdomain.com>`
- SMTP fallback if you do not use Resend:
  - `SMTP_HOST=smtp.yourmailhost.com`
  - `SMTP_PORT=587`
  - `SMTP_USER=...`
  - `SMTP_PASS=...`
  - `SMTP_SECURE=false` (or `true` for port 465)
- `SELLER_SUBSCRIPTION_PRODUCT_ID=com.innovativecodeworks.com.TenBelow.seller.monthly`

Buyer email/password updates now require transactional email delivery for confirmation.
Configure either Resend or SMTP so those updates can complete successfully.

## Stripe webhook setup

After deploy, create a Stripe webhook endpoint that points to:

`https://your-backend-domain.com/webhook`

Current required event:

- `payment_intent.succeeded`

## First deploy behavior

On first boot, the backend seeds its persistent data directory from the current local project files when available. After that, the mounted disk becomes the source of truth.

## Local development

Use the sample env file:

```bash
cp .env.example .env
```

Typical local values:

```env
BACKEND_URL=http://localhost:3000
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

Start the server:

```bash
npm install
npm run dev
```

For local webhook testing:

```bash
stripe listen --forward-to localhost:3000/webhook
```
