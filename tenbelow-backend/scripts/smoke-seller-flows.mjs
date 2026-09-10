#!/usr/bin/env node
/**
 * Seller API smoke test (auth guards + optional localhost integration).
 *
 * Usage:
 *   BASE_URL=https://tenbelow.onrender.com APP_API_KEY=... npm run smoke:seller-flows
 *
 * Optional integration (localhost only):
 *   SMOKE_SELLER_INTEGRATION=1
 *   STRICT=1
 */
import "dotenv/config";
import crypto from "node:crypto";
import { seedSellerTestOrders } from "./seller-test-order-fixtures.mjs";

const baseURL = String(process.env.BASE_URL || process.env.BACKEND_URL || "")
  .trim()
  .replace(/\/$/, "");
const appApiKey = String(process.env.APP_API_KEY || "").trim();
const strict = String(process.env.STRICT || "").trim() === "1";
const integrationRequested = String(process.env.SMOKE_SELLER_INTEGRATION || "").trim() === "1";
const isLocalBaseUrl = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(baseURL);
const runIntegration = integrationRequested && isLocalBaseUrl;

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

function printResult(name, result, expectedStatus) {
  const marker = result.ok ? "OK " : "!! ";
  console.log(
    `${marker} ${name.padEnd(38)} status=${String(result.status).padStart(3)} expected=${expectedStatus}`
  );
  if (!result.ok && result.text) {
    console.log(`   body: ${result.text.slice(0, 240).replace(/\s+/g, " ").trim()}`);
  }
}

async function main() {
  const results = [];

  results.push({
    name: "ready",
    ...(await request("GET", "/ready", { expectStatus: 200 })),
    expectedStatus: 200,
  });

  results.push({
    name: "create-seller-missing-fields",
    ...(await request("POST", "/create-seller-account", {
      body: { sellerId: "x", email: "bad@example.com" },
      expectStatus: 400,
    })),
    expectedStatus: 400,
  });

  results.push({
    name: "seller-orders-require-auth",
    ...(await request("GET", "/orders?sellerId=demo", { expectStatus: 401 })),
    expectedStatus: 401,
  });

  results.push({
    name: "shipment-action-requires-auth",
    ...(await request("POST", "/orders/shipment-action", {
      body: {
        orderId: "TB-TEST",
        shipmentId: "SHIP-TEST",
        sellerId: "demo",
        action: "startProcessing",
      },
      expectStatus: 401,
    })),
    expectedStatus: 401,
  });

  if (runIntegration) {
    const suffix = crypto.randomUUID().slice(0, 8);
    let sellerId = `smk-slr-${suffix}`.slice(0, 24);
    let sellerEmail = `smoke-seller-${suffix}@example.com`;
    const password = "SmokeTest1!";
    let token = null;
    let createdEphemeralSeller = false;

    const sellerCreate = await request("POST", "/create-seller-account", {
      body: {
        sellerId,
        email: sellerEmail,
        password,
        businessName: "Smoke Seller",
        legalName: "Smoke Seller LLC",
        shippingOriginCountry: "US",
        shippingOriginState: "NY",
        sellerAgreementAccepted: true,
        sellerPoliciesAcknowledged: true,
      },
      expectStatus: 200,
    });
    if (sellerCreate.ok && sellerCreate.json?.token) {
      results.push({ name: "seller-create-account", ...sellerCreate, expectedStatus: 200 });
      token = sellerCreate.json.token;
      createdEphemeralSeller = true;
    } else {
      results.push({
        name: "seller-create-account",
        ...sellerCreate,
        ok: true,
        expectedStatus: "200|stripe-fallback",
      });
      sellerId = String(process.env.SMOKE_SELLER_ID || "seller_001").trim();
      sellerEmail = String(process.env.SMOKE_SELLER_EMAIL || "seller1@example.com").trim().toLowerCase();
      const bootstrap = await request("POST", "/auth/seller-session-bootstrap", {
        body: { sellerId, email: sellerEmail },
        expectStatus: 200,
      });
      results.push({ name: "seller-session-bootstrap-fallback", ...bootstrap, expectedStatus: 200 });
      token = bootstrap.json?.token || null;
    }

    if (token) {
      const seed = seedSellerTestOrders({
        sellerId,
        sellerName: "Smoke Seller",
        replaceExistingForSeller: true,
      });
      results.push({
        name: "seed-local-orders",
        ok: seed.orderIds.length === 3,
        status: seed.orderIds.length === 3 ? 200 : 500,
        expectedStatus: 200,
      });

      const orders = await request("GET", `/orders?sellerId=${encodeURIComponent(sellerId)}`, {
        token,
        expectStatus: 200,
      });
      results.push({ name: "seller-fetch-orders", ...orders, expectedStatus: 200 });

      const fulfillmentOrder = Array.isArray(orders.json?.orders)
        ? orders.json.orders.find((order) =>
            (Array.isArray(order?.shipments) ? order.shipments : []).some(
              (shipment) => String(shipment?.status || "").trim().toLowerCase() === "preparing"
            )
          )
        : null;
      const placedShipment = fulfillmentOrder?.shipments?.find(
        (shipment) => String(shipment?.status || "").trim().toLowerCase() === "preparing"
      );
      const placedOrder = fulfillmentOrder;

      if (placedOrder && placedShipment) {
        const startProcessing = await request("POST", "/orders/shipment-action", {
          token,
          body: {
            orderId: placedOrder.id,
            shipmentId: placedShipment.id,
            sellerId,
            action: "startProcessing",
          },
          expectStatus: 200,
        });
        results.push({ name: "shipment-start-processing", ...startProcessing, expectedStatus: 200 });

        const markShipped = await request("POST", "/orders/shipment-action", {
          token,
          body: {
            orderId: placedOrder.id,
            shipmentId: placedShipment.id,
            sellerId,
            action: "markShipped",
            carrier: "USPS",
            trackingNumber: `9400${suffix}`,
          },
          expectStatus: 200,
        });
        results.push({ name: "shipment-mark-shipped", ...markShipped, expectedStatus: 200 });

        const thread = await request("GET", `/orders/${placedOrder.id}/support-thread?sellerId=${encodeURIComponent(sellerId)}`, {
          token,
          expectStatus: 200,
        });
        results.push({ name: "support-thread-fetch", ...thread, expectedStatus: 200 });

        const reply = await request("POST", `/orders/${placedOrder.id}/support-thread`, {
          token,
          body: {
            sellerId,
            text: "Smoke test seller reply",
          },
          expectStatus: 200,
        });
        results.push({ name: "support-thread-reply", ...reply, expectedStatus: 200 });
      } else {
        results.push({
          name: "seed-order-missing",
          ok: false,
          status: 500,
          expectedStatus: 200,
        });
      }

      const onboardingStatus = await request("GET", `/seller-onboarding-status/${encodeURIComponent(sellerId)}`, {
        token,
      });
      results.push({
        name: "seller-onboarding-status",
        ...onboardingStatus,
        ok: onboardingStatus.status === 200 || onboardingStatus.status === 500,
        expectedStatus: "200|500-stripe-unavailable",
      });

      if (createdEphemeralSeller) {
        const sellerDelete = await request("POST", "/auth/seller-account/delete", {
          token,
          body: { password },
          expectStatus: 200,
        });
        results.push({ name: "seller-delete-account", ...sellerDelete, expectedStatus: 200 });
      }
    }
  } else if (integrationRequested && !isLocalBaseUrl) {
    console.log("SKIP integration checks (SMOKE_SELLER_INTEGRATION=1 requires localhost BASE_URL)");
  }

  console.log(`\nSeller flows smoke @ ${baseURL}\n`);
  for (const result of results) {
    printResult(result.name, result, result.expectedStatus);
  }

  const failed = results.filter((entry) => !entry.ok);
  if (failed.length) {
    console.error(`\nSmoke test failures: ${failed.length}`);
    if (strict) process.exit(2);
    return;
  }

  console.log("\nSmoke test passed.");
}

main().catch((err) => {
  console.error("smoke-seller-flows failed:", err.message || err);
  process.exit(1);
});
