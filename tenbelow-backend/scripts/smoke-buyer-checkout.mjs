#!/usr/bin/env node
/**
 * Buyer checkout API smoke (Stripe test mode / guest session).
 *
 * Creates a PaymentIntent only — does not confirm payment (use the iOS app + test cards for that).
 *
 * Usage:
 *   BASE_URL=https://tenbelow.onrender.com APP_API_KEY=... npm run smoke:buyer-checkout
 *   STRICT=1 …  # exit non-zero on failure
 */
import "dotenv/config";
import crypto from "node:crypto";

const baseURL = String(process.env.BASE_URL || process.env.BACKEND_URL || "")
  .trim()
  .replace(/\/$/, "");
const appApiKey = String(process.env.APP_API_KEY || "").trim();
const strict = String(process.env.STRICT || "").trim() === "1";
const MINIMUM_ORDER_CENTS = 1500;

if (!baseURL) {
  console.error("BASE_URL or BACKEND_URL is required");
  process.exit(1);
}

function headers(extra = {}) {
  const next = { "Content-Type": "application/json", ...extra };
  if (appApiKey) next["X-TenBelow-App-Key"] = appApiKey;
  return next;
}

async function request(method, path, { body, token, expectStatus } = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: headers(token ? { Authorization: `Bearer ${token}` } : {}),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  const ok = expectStatus === undefined ? response.ok : response.status === expectStatus;
  return { ok, status: response.status, json, text, expectStatus };
}

function printResult(name, result) {
  const marker = result.ok ? "OK " : "!! ";
  const expected = result.expectStatus ?? "2xx";
  console.log(`${marker} ${name.padEnd(36)} status=${String(result.status).padStart(3)} expected=${expected}`);
  if (!result.ok && result.text) {
    console.log(`   body: ${result.text.slice(0, 240).replace(/\s+/g, " ").trim()}`);
  }
}

function shipping(email) {
  return {
    name: "Buyer Smoke",
    line1: "1 Market St",
    city: "San Francisco",
    state: "CA",
    postalCode: "94105",
    country: "US",
  };
}

function buildCartLines(products, { meetMinimum }) {
  const lines = [];
  let subtotal = 0;
  for (const product of products) {
    const colors = Array.isArray(product.availableColors) ? product.availableColors : [];
    const selectedColorId = colors[0]?.id || colors[0]?.colorId || null;
    if (colors.length && !selectedColorId) continue;

    const price = Number(product.priceCents || 0);
    if (!price || !product.id) continue;

    let quantity = 1;
    if (meetMinimum) {
      quantity = Math.max(1, Math.ceil(MINIMUM_ORDER_CENTS / price));
    }

    lines.push({
      productId: product.id,
      quantity,
      selectedColorId: selectedColorId || undefined,
    });
    subtotal += price * quantity;
    if (meetMinimum && subtotal >= MINIMUM_ORDER_CENTS) break;
    if (!meetMinimum) break;
  }
  return { lines, subtotal };
}

async function main() {
  const results = [];

  const ready = await request("GET", "/ready");
  results.push({ name: "ready", ...ready, expectStatus: 200, ok: ready.status === 200 });

  const catalog = await request("GET", "/catalog");
  results.push({ name: "catalog", ...catalog, expectStatus: 200 });
  const products = Array.isArray(catalog.json?.products)
    ? catalog.json.products.filter((p) => p.isActive !== false && p.isApproved !== false)
    : [];

  const email = `buyer-smoke-${crypto.randomUUID().slice(0, 8)}@example.com`;
  const guest = await request("POST", "/auth/guest-checkout-session", {
    body: { email, fullName: "Buyer Smoke" },
    expectStatus: 200,
  });
  results.push({ name: "guest-checkout-session", ...guest, expectStatus: 200 });
  const token = guest.json?.token;

  if (token && products.length) {
    const under = buildCartLines(products, { meetMinimum: false });
    if (under.lines.length && under.subtotal < MINIMUM_ORDER_CENTS) {
      const underMin = await request("POST", "/create-payment-intent", {
        token,
        body: { email, shipping: shipping(email), items: under.lines },
        expectStatus: 400,
      });
      underMin.ok = underMin.status === 400 && underMin.json?.code === "minimum_order_not_met";
      results.push({ name: "payment-intent-under-minimum", ...underMin, expectStatus: 400 });
    } else {
      console.log("SKIP payment-intent-under-minimum (could not build under-$15 cart)");
    }

    const colored = products.find((p) => Array.isArray(p.availableColors) && p.availableColors.length > 0);
    if (colored) {
      const qty = Math.max(1, Math.ceil(MINIMUM_ORDER_CENTS / Number(colored.priceCents || 1)));
      const missingColor = await request("POST", "/create-payment-intent", {
        token,
        body: {
          email,
          shipping: shipping(email),
          items: [{ productId: colored.id, quantity: qty }],
        },
        expectStatus: 400,
      });
      missingColor.ok =
        missingColor.status === 400 && missingColor.json?.code === "color_selection_required";
      results.push({ name: "payment-intent-color-required", ...missingColor, expectStatus: 400 });
    } else {
      console.log("SKIP payment-intent-color-required (no colored products in catalog)");
    }

    const valid = buildCartLines(products, { meetMinimum: true });
    if (valid.lines.length && valid.subtotal >= MINIMUM_ORDER_CENTS) {
      const wrongEmail = await request("POST", "/create-payment-intent", {
        token,
        body: {
          email: `other-${email}`,
          shipping: shipping(email),
          items: valid.lines,
        },
        expectStatus: 403,
      });
      results.push({ name: "payment-intent-email-mismatch", ...wrongEmail, expectStatus: 403 });

      const create = await request("POST", "/create-payment-intent", {
        token,
        body: { email, shipping: shipping(email), items: valid.lines },
        expectStatus: 200,
      });
      create.ok = create.status === 200 && Boolean(create.json?.clientSecret || create.json?.client_secret);
      results.push({ name: "payment-intent-create", ...create, expectStatus: 200 });
    } else {
      console.log("SKIP payment-intent-create (could not build valid cart)");
    }
  }

  console.log(`\nBuyer checkout smoke @ ${baseURL}\n`);
  for (const result of results) printResult(result.name, result);

  const failed = results.filter((entry) => !entry.ok);
  if (failed.length) {
    console.error(`\nSmoke test failures: ${failed.length}`);
    if (strict) process.exit(2);
    return;
  }
  console.log("\nSmoke test passed.");
  console.log("Next: in the iOS Debug app, turn off Force simulated checkout and pay with Stripe test cards.");
}

main().catch((err) => {
  console.error("smoke-buyer-checkout failed:", err.message || err);
  process.exit(1);
});
