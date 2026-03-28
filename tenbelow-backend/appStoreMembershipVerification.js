import { createRequire } from "module";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import path from "path";

const require = createRequire(import.meta.url);
const {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  Status,
  APIException,
} = require("@apple/app-store-server-library");

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadPrivateKeyPem() {
  const keyPath = process.env.APP_STORE_PRIVATE_KEY_PATH?.trim();
  if (keyPath) {
    return readFileSync(keyPath, "utf8");
  }
  const inline = process.env.APP_STORE_PRIVATE_KEY?.trim();
  if (!inline) return null;
  return inline.replace(/\\n/g, "\n");
}

function loadAppleRootCertificates() {
  const names = ["AppleRootCA-G3.cer", "AppleRootCA-G2.cer"];
  const buffers = [];
  for (const name of names) {
    const p = path.join(__dirname, "certs", name);
    try {
      buffers.push(readFileSync(p));
    } catch {
      console.warn(`app-store: missing root cert at ${p}`);
    }
  }
  if (!buffers.length) {
    throw new Error("No Apple root certificates found (expected certs/AppleRootCA-G3.cer and G2)");
  }
  return buffers;
}

function parseApiEnvironment() {
  const v = (process.env.APP_STORE_SERVER_ENV || "sandbox").toLowerCase();
  if (v === "production") return Environment.PRODUCTION;
  return Environment.SANDBOX;
}

export function isAppStoreVerificationConfigured() {
  const hasKey = !!(
    process.env.APP_STORE_PRIVATE_KEY?.trim() || process.env.APP_STORE_PRIVATE_KEY_PATH?.trim()
  );
  return !!(
    process.env.APP_STORE_ISSUER_ID?.trim() &&
    process.env.APP_STORE_KEY_ID?.trim() &&
    hasKey &&
    process.env.APP_STORE_BUNDLE_ID?.trim()
  );
}

/**
 * Calls Apple's App Store Server API and verifies signed transaction JWS payloads.
 * @returns {Promise<{ hasActiveSubscription: boolean, expiresAt: string | null, productId: string, transactionId: string | null, originalTransactionId: string, appleStatus?: number }>}
 */
export async function verifySubscriptionWithAppStore(originalTransactionId, expectedProductId) {
  if (!isAppStoreVerificationConfigured()) {
    throw new Error("App Store Server API is not configured");
  }

  const signingKey = loadPrivateKeyPem();
  if (!signingKey) {
    throw new Error("APP_STORE_PRIVATE_KEY or APP_STORE_PRIVATE_KEY_PATH is missing");
  }

  const env = parseApiEnvironment();
  const bundleId = process.env.APP_STORE_BUNDLE_ID.trim();
  const issuerId = process.env.APP_STORE_ISSUER_ID.trim();
  const keyId = process.env.APP_STORE_KEY_ID.trim();
  const appAppleIdRaw = process.env.APP_STORE_APP_APPLE_ID?.trim();

  if (env === Environment.PRODUCTION && !appAppleIdRaw) {
    throw new Error("APP_STORE_APP_APPLE_ID is required when APP_STORE_SERVER_ENV=production (see App Store Connect app record)");
  }

  const appAppleId = appAppleIdRaw ? Number(appAppleIdRaw) : undefined;

  const client = new AppStoreServerAPIClient(signingKey, keyId, issuerId, bundleId, env);

  let statusResponse;
  try {
    statusResponse = await client.getAllSubscriptionStatuses(String(originalTransactionId));
  } catch (e) {
    if (e instanceof APIException) {
      const msg = e.errorMessage || `App Store Server API HTTP ${e.httpStatusCode}`;
      const err = new Error(msg);
      err.httpStatusCode = e.httpStatusCode;
      err.apiError = e.apiError;
      throw err;
    }
    throw e;
  }

  const appleRoots = loadAppleRootCertificates();
  const verifier = new SignedDataVerifier(
    appleRoots,
    true,
    env,
    bundleId,
    env === Environment.PRODUCTION ? appAppleId : undefined
  );

  const privilegedStatuses = new Set([
    Status.ACTIVE,
    Status.BILLING_GRACE_PERIOD,
    Status.BILLING_RETRY,
  ]);

  let best = null;

  for (const group of statusResponse.data || []) {
    for (const item of group.lastTransactions || []) {
      if (!item.signedTransactionInfo) continue;

      let decoded;
      try {
        decoded = await verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
      } catch {
        continue;
      }

      if (decoded.productId !== expectedProductId) continue;

      const st = item.status;
      let hasActive =
        privilegedStatuses.has(st) &&
        st !== Status.REVOKED &&
        (decoded.revocationDate == null || decoded.revocationDate === 0);

      const expiresMs = decoded.expiresDate;
      if (typeof expiresMs === "number" && expiresMs > 0) {
        if (new Date(expiresMs) <= new Date()) {
          hasActive = false;
        }
      }

      if (!best || (expiresMs || 0) > (best.expiresMs || 0)) {
        best = {
          expiresMs: expiresMs || 0,
          decoded,
          status: st,
          hasActive,
        };
      }
    }
  }

  if (!best) {
    return {
      hasActiveSubscription: false,
      expiresAt: null,
      productId: expectedProductId,
      transactionId: null,
      originalTransactionId: String(originalTransactionId),
    };
  }

  const expiresAt =
    best.decoded.expiresDate && best.decoded.expiresDate > 0
      ? new Date(best.decoded.expiresDate).toISOString()
      : null;

  return {
    hasActiveSubscription: best.hasActive,
    expiresAt,
    productId: best.decoded.productId,
    transactionId: best.decoded.transactionId || null,
    originalTransactionId: best.decoded.originalTransactionId || String(originalTransactionId),
    appleStatus: best.status,
  };
}
