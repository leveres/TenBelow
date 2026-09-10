#!/usr/bin/env node
/**
 * Smoke test for in-app account deletion routes.
 *
 * Usage:
 *   BASE_URL=http://127.0.0.1:3000 node scripts/smoke-account-deletion.mjs
 *
 * Optional:
 *   APP_API_KEY=...                 # X-TenBelow-App-Key when required
 *   AUTH_JWT_SECRET=...             # required for local integration checks
 *   SMOKE_ACCOUNT_DELETION_INTEGRATION=1
 *   STRICT=1                        # exit non-zero on failure
 *
 * Integration mode runs only against localhost and creates/deletes ephemeral test accounts.
 */
import "dotenv/config";
import crypto from "node:crypto";

const baseURL = String(process.env.BASE_URL || process.env.BACKEND_URL || "http://127.0.0.1:3000")
  .trim()
  .replace(/\/$/, "");
const appApiKey = String(process.env.APP_API_KEY || "").trim();
const strict = String(process.env.STRICT || "").trim() === "1";
const integrationRequested = String(process.env.SMOKE_ACCOUNT_DELETION_INTEGRATION || "").trim() === "1";
const isLocalBaseUrl = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(baseURL);
const runIntegration = integrationRequested && isLocalBaseUrl;

function authHeaders(extra = {}) {
  const headers = { "Content-Type": "application/json", ...extra };
  if (appApiKey) headers["X-TenBelow-App-Key"] = appApiKey;
  return headers;
}

async function request(method, path, { body, token, expectStatus } = {}) {
  const headers = authHeaders(token ? { Authorization: `Bearer ${token}` } : {});
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers,
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
  return { ok, status: response.status, json, text };
}

function printResult(name, result, expectedStatus) {
  const marker = result.ok ? "OK " : "!! ";
  console.log(
    `${marker} ${name.padEnd(34)} status=${String(result.status).padStart(3)} expected=${expectedStatus}`
  );
  if (!result.ok && result.text) {
    console.log(`   body: ${result.text.slice(0, 220).replace(/\s+/g, " ").trim()}`);
  }
}

async function main() {
  const results = [];

  results.push({
    name: "buyer-delete-requires-auth",
    ...(await request("POST", "/auth/buyer-account/delete", {
      body: { password: "" },
      expectStatus: 401,
    })),
    expectedStatus: 401,
  });

  results.push({
    name: "seller-delete-requires-auth",
    ...(await request("POST", "/auth/seller-account/delete", {
      body: { password: "" },
      expectStatus: 401,
    })),
    expectedStatus: 401,
  });

  if (runIntegration) {
    const suffix = crypto.randomUUID().slice(0, 8);
    const buyerEmail = `smoke-delete-buyer-${suffix}@example.com`;
    const sellerId = `smk-del-${suffix}`.slice(0, 24);
    const sellerEmail = `smoke-delete-seller-${suffix}@example.com`;
    const password = "SmokeTest1!";

    const guestSession = await request("POST", "/auth/guest-checkout-session", {
      body: { email: buyerEmail, fullName: "Smoke Delete Buyer" },
      expectStatus: 200,
    });
    results.push({ name: "buyer-seed-guest-session", ...guestSession, expectedStatus: 200 });

    if (guestSession.ok && guestSession.json?.token) {
      const buyerDelete = await request("POST", "/auth/buyer-account/delete", {
        body: { password: "" },
        token: guestSession.json.token,
        expectStatus: 200,
      });
      results.push({ name: "buyer-delete-account", ...buyerDelete, expectedStatus: 200 });

      const buyerGone = await request("POST", "/auth/buyer-session", {
        body: { email: buyerEmail },
        expectStatus: 404,
      });
      results.push({ name: "buyer-account-removed", ...buyerGone, expectedStatus: 404 });
    }

    const sellerCreate = await request("POST", "/create-seller-account", {
      body: {
        sellerId,
        email: sellerEmail,
        password,
        businessName: "Smoke Delete Seller",
        legalName: "Smoke Delete Seller LLC",
        shippingOriginCountry: "US",
        shippingOriginState: "NY",
        sellerAgreementAccepted: true,
        sellerPoliciesAcknowledged: true,
      },
      expectStatus: 200,
    });
    results.push({ name: "seller-seed-account", ...sellerCreate, expectedStatus: 200 });

    if (sellerCreate.ok && sellerCreate.json?.token) {
      const sellerDelete = await request("POST", "/auth/seller-account/delete", {
        body: { password },
        token: sellerCreate.json.token,
        expectStatus: 200,
      });
      results.push({ name: "seller-delete-account", ...sellerDelete, expectedStatus: 200 });

      const sellerGone = await request("POST", "/auth/seller-login", {
        body: { identifier: sellerId, password },
        expectStatus: 404,
      });
      results.push({ name: "seller-account-removed", ...sellerGone, expectedStatus: 404 });
    }
  } else if (integrationRequested && !isLocalBaseUrl) {
    console.log("SKIP integration checks (SMOKE_ACCOUNT_DELETION_INTEGRATION=1 requires localhost BASE_URL)");
  }

  console.log(`\nAccount deletion smoke @ ${baseURL}\n`);
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
  console.error("smoke-account-deletion failed:", err.message || err);
  process.exit(1);
});
