import "dotenv/config";
import express from "express";
import cors from "cors";
import Stripe from "stripe";
import { Resend } from "resend";
import nodemailer from "nodemailer";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from "fs";
import crypto from "crypto";
import path from "path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "url";
import {
  isAppStoreVerificationConfigured,
  verifySubscriptionWithAppStore,
} from "./appStoreMembershipVerification.js";
import { registerPushDevice, unregisterPushDevice } from "./pushDevicesStore.js";
import {
  notifyOrderStatusChanged,
  notifyOrderSupportEvent,
  notifyPaymentSucceeded,
  notifyShipmentStatusToBuyer,
} from "./pushOrderNotifications.js";
import jwt from "jsonwebtoken";
import rateLimit from "express-rate-limit";
import { auditLog, AUDIT_LOG_SCAN_MAX, clientIp, readAuditLogTail } from "./auditLog.js";
import {
  attachExchangeSummariesToOrders,
  createExchangeTimelineEvent,
  DEFAULT_EXCHANGE_CONFIG,
  evaluateExchangeEligibility,
  exchangeBuyerUserId,
  exchangeSellerUserId,
  isActiveExchangeStatus,
  mergeExchangeConfig,
  normalizeExchangeProofAsset,
  normalizeExchangeRequest,
  normalizeExchangeRequests,
} from "./exchangePolicy.js";
import {
  computeShippingTotalsBySeller,
  FREE_SHIPPING_THRESHOLD_CENTS,
} from "./shippingPolicy.js";
import {
  DATA_DIRECTORY_PATH,
  DATA_DIRECTORY_URL,
  MEDIA_DIRECTORY_PATH,
  MEDIA_DIRECTORY_URL,
  dataFileURL,
  ensureDirectory,
} from "./storagePaths.js";
import { ensureSchema, getPool, isPgEnabled, loadAllDocumentsInto, upsertDocumentRow } from "./db/pgDocuments.mjs";
import {
  ensureRelationalSchema,
  recordSellerMediaUpload,
  upsertRelationalForManagedDocument,
} from "./db/pgRelational.mjs";
import { schedulePhase1Compare, syncPhase1AfterJsonWrite, syncPhase1ToPrisma } from "./db/repositories/phase1.js";
import { applyDatabaseUrlToEnv } from "./db/prisma/databaseUrl.js";
import { getPrisma, isPrismaConfigured } from "./db/prisma/client.js";
import { storeMediaBytes } from "./mediaObjectStorage.js";
import {
  MEDIA_SIZE_LIMITS,
  isServableMediaExtension,
  safeContentTypeForExtension,
  safeMediaServingMiddleware,
  validateCustomOrderReferenceUpload,
  validateExchangeProofUpload,
  validateSellerMediaUpload,
} from "./mediaUploadPolicy.js";
import {
  applyApprovedSupportRequest,
  normalizeOrderMessage,
  normalizeOrderSupportFields,
  normalizeSupportRequest,
  orderMessagesForSeller,
  validateSupportRequestCreate,
} from "./orderSupport.js";
import {
  appendInquiryMessage,
  findInquiryThread,
  normalizeInquiryThread,
  upsertInquiryThread,
} from "./sellerInquiry.js";

const app = express();
const STRIPE_SECRET_KEY = String(process.env.STRIPE_SECRET_KEY || "").trim();
const stripe = new Stripe(STRIPE_SECRET_KEY || "sk_test_missing");
const resend = process.env.RESEND_API_KEY
  ? new Resend(process.env.RESEND_API_KEY)
  : null;

const EMAIL_FROM = process.env.EMAIL_FROM || "TenBelow <noreply@tenbelow.com>";
const SMTP_HOST = String(process.env.SMTP_HOST || "").trim();
const SMTP_PORT = Number(process.env.SMTP_PORT || 587);
const SMTP_USER = String(process.env.SMTP_USER || "").trim();
const SMTP_PASS = String(process.env.SMTP_PASS || "").trim();
const SMTP_SECURE =
  String(process.env.SMTP_SECURE || "")
    .trim()
    .toLowerCase() === "true" || SMTP_PORT === 465;
const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:3000";
const CUSTOM_ORDER_ADMIN_EMAIL = String(process.env.CUSTOM_ORDER_ADMIN_EMAIL || "").trim();
const ADMIN_LOGIN_EMAIL = String(process.env.ADMIN_LOGIN_EMAIL || CUSTOM_ORDER_ADMIN_EMAIL || "").trim().toLowerCase();
const SELLER_SUBSCRIPTION_PRODUCT_ID =
  process.env.SELLER_SUBSCRIPTION_PRODUCT_ID || "com.innovativecodeworks.com.TenBelow.seller.monthly";
const APP_API_KEY = process.env.APP_API_KEY || "";
const AUTH_JWT_SECRET = process.env.AUTH_JWT_SECRET || APP_API_KEY || "";
const ADMIN_API_KEY = String(process.env.ADMIN_API_KEY || "").trim();
const ADMIN_SESSION_COOKIE_NAME = "tb_admin_session";
const LEGACY_ADMIN_COOKIE_NAME = "tb_admin_auth";
const ADMIN_SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 30;
const ADMIN_SESSION_TTL_SECONDS = Math.floor(ADMIN_SESSION_TTL_MS / 1000);
const EMAIL_OTP_TTL_MS = 1000 * 60 * 10;
const EMAIL_OTP_MAX_ATTEMPTS = 5;
const IS_PRODUCTION = process.env.NODE_ENV === "production";
const STRIPE_CONNECT_SETUP_MESSAGE =
  "Stripe Connect is not configured yet. Sellers can finish account setup now and connect payouts when TenBelow enables Stripe.";
const ADMIN_ALLOW_DIRECT_KEY_AUTH =
  !IS_PRODUCTION &&
  String(process.env.ADMIN_ALLOW_DIRECT_KEY_AUTH || "")
    .trim()
    .toLowerCase() === "true";
const ALLOWED_CORS_ORIGINS = String(process.env.CORS_ALLOWED_ORIGINS || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

const smtpConfigured = Boolean(SMTP_HOST && SMTP_USER && SMTP_PASS && Number.isFinite(SMTP_PORT));
let smtpTransporter = null;

if (ALLOWED_CORS_ORIGINS.length === 0) {
  ALLOWED_CORS_ORIGINS.push(
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:5173",
    "http://127.0.0.1:5173"
  );
  try {
    ALLOWED_CORS_ORIGINS.push(new URL(BACKEND_URL).origin);
  } catch {
    // ignore malformed BACKEND_URL; defaults above are still applied.
  }
}

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
});

const adminLoginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 25,
  standardHeaders: true,
  legacyHeaders: false,
});

const adminMutationLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
});

const paymentLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 45,
  standardHeaders: true,
  legacyHeaders: false,
});

const sellerInventoryLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
});

const sellerWriteLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 180,
  standardHeaders: true,
  legacyHeaders: false,
});

const publicReadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: Number.parseInt(process.env.PUBLIC_READ_RATE_LIMIT_MAX || "900", 10),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => clientIp(req) || "unknown",
});

const mediaReadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: Number.parseInt(process.env.MEDIA_READ_RATE_LIMIT_MAX || "2000", 10),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => clientIp(req) || "unknown",
});

const mediaUploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: Number.parseInt(process.env.MEDIA_UPLOAD_RATE_LIMIT_MAX || "120", 10),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => clientIp(req) || "unknown",
});

const sellerMediaRawLimit = `${Math.ceil(MEDIA_SIZE_LIMITS.sellerVideoBytes / (1024 * 1024))}mb`;
const exchangeProofRawLimit = `${Math.ceil(MEDIA_SIZE_LIMITS.exchangeVideoBytes / (1024 * 1024))}mb`;
const customOrderRefRawLimit = `${Math.ceil(MEDIA_SIZE_LIMITS.customOrderRefBytes / (1024 * 1024))}mb`;

const customOrderLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 48,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => clientIp(req) || "unknown",
});

const PREMIUM_LISTING_MIN_PRICE_CENTS = 1001;
const SELLER_VERIFICATION_MIN_SALES = 50;
const SELLER_VERIFICATION_MIN_POSITIVE_REVIEWS = 30;
const SELLER_VERIFICATION_MIN_AVERAGE_RATING = 4.0;
const SELLER_VERIFICATION_MIN_ACTIVE_DAYS = 30;
const PLATFORM_MINIMUM_ORDER_CENTS = 1500;
/** Marketplace revenue is seller membership — not per-sale commission on product. */
const PLATFORM_PRODUCT_COMMISSION_RATE = 0;
const LEGACY_PRODUCTS_PATH = new URL("../TenBelow/Data/Remote/products.json", import.meta.url);
const LEGACY_CONFIG_PATH = new URL("../TenBelow/Data/Remote/config.json", import.meta.url);
const LEGACY_SELLERS_PATH = new URL("./sellers.json", import.meta.url);
const LEGACY_ORDERS_PATH = new URL("./orders.json", import.meta.url);
const LEGACY_DROPS_PATH = new URL("./drops.json", import.meta.url);
const PRODUCTS_PATH = dataFileURL("products.json");
const CONFIG_PATH = dataFileURL("config.json");
const SELLERS_PATH = dataFileURL("sellers.json");
const BUYERS_PATH = dataFileURL("buyers.json");
const ORDERS_PATH = dataFileURL("orders.json");
const DROPS_PATH = dataFileURL("drops.json");
const PRODUCT_REVIEWS_PATH = dataFileURL("product-reviews.json");
const EXCHANGE_REQUESTS_PATH = dataFileURL("exchange-requests.json");
const CUSTOM_ORDER_REQUESTS_PATH = dataFileURL("custom-order-requests.json");
const SELLER_INQUIRIES_PATH = dataFileURL("seller-inquiries.json");
const WEBHOOK_EVENTS_PATH = dataFileURL("webhook-events.json");
const PUBLIC_INDEX_HTML_PATH = fileURLToPath(new URL("./public/index.html", import.meta.url));
const PUBLIC_ASSETS_PATH = fileURLToPath(new URL("./public/", import.meta.url));
const ADMIN_REVIEW_HTML_PATH = fileURLToPath(new URL("./admin/review.html", import.meta.url));
const ADMIN_ASSETS_PATH = fileURLToPath(new URL("./admin/", import.meta.url));
const SNAPSHOT_DIRECTORY_URL = new URL("./snapshots/", DATA_DIRECTORY_URL);
const snapshotRetentionRaw = Number.parseInt(String(process.env.DATA_SNAPSHOT_KEEP || "50"), 10);
const SNAPSHOT_RETENTION_PER_KEY = Number.isFinite(snapshotRetentionRaw) && snapshotRetentionRaw > 0
  ? snapshotRetentionRaw
  : 50;
const SNAPSHOT_SIGNING_SECRET = String(process.env.SNAPSHOT_SIGNING_SECRET || AUTH_JWT_SECRET || "").trim();
const SECURITY_ALERT_WINDOW_MS = 15 * 60 * 1000;
const SECURITY_ALERT_AUTH_FAILURE_THRESHOLD = 20;
const SECURITY_ALERT_OWNERSHIP_MISMATCH_THRESHOLD = 10;
const SECURITY_ALERT_WEBHOOK_URL = String(process.env.SECURITY_ALERT_WEBHOOK_URL || "").trim();
const SECURITY_ALERT_SLACK_WEBHOOK_URL = String(process.env.SLACK_ALERT_WEBHOOK_URL || "").trim();
const SECURITY_ALERT_WEBHOOK_URL_HIGH = String(process.env.SECURITY_ALERT_WEBHOOK_URL_HIGH || "").trim();
const SECURITY_ALERT_WEBHOOK_URL_MEDIUM = String(process.env.SECURITY_ALERT_WEBHOOK_URL_MEDIUM || "").trim();
const SLACK_ALERT_WEBHOOK_URL_HIGH = String(process.env.SLACK_ALERT_WEBHOOK_URL_HIGH || "").trim();
const SLACK_ALERT_WEBHOOK_URL_MEDIUM = String(process.env.SLACK_ALERT_WEBHOOK_URL_MEDIUM || "").trim();
const SECURITY_ALERT_COOLDOWN_MS = 10 * 60 * 1000;
const MANAGED_DATA_TARGETS = Object.freeze({
  products: PRODUCTS_PATH,
  config: CONFIG_PATH,
  sellers: SELLERS_PATH,
  buyers: BUYERS_PATH,
  orders: ORDERS_PATH,
  drops: DROPS_PATH,
  productReviews: PRODUCT_REVIEWS_PATH,
  exchangeRequests: EXCHANGE_REQUESTS_PATH,
  customOrderRequests: CUSTOM_ORDER_REQUESTS_PATH,
  sellerInquiries: SELLER_INQUIRIES_PATH,
  webhookEvents: WEBHOOK_EVENTS_PATH,
});
const DOCUMENT_MEMORY_CACHE = new Map();
let processedWebhookEventIds = new Set();
const securityAlertEscalationState = new Map();
const emailOtpChallenges = new Map();

function ensureJSONFile(targetURL, { seedCandidates = [], fallbackValue }) {
  const targetPath = fileURLToPath(targetURL);
  if (existsSync(targetPath)) return;

  ensureDirectory(new URL("./", targetURL));

  for (const candidateURL of seedCandidates) {
    const candidatePath = fileURLToPath(candidateURL);
    if (!existsSync(candidatePath)) continue;
    copyFileSync(candidatePath, targetPath);
    return;
  }

  const resolvedFallback =
    typeof fallbackValue === "function" ? fallbackValue() : fallbackValue;
  writeFileSync(targetPath, JSON.stringify(resolvedFallback, null, 2));
}

function initializeBackendStorage() {
  ensureDirectory(DATA_DIRECTORY_URL);
  ensureDirectory(MEDIA_DIRECTORY_URL);
  ensureDirectory(SNAPSHOT_DIRECTORY_URL);

  ensureJSONFile(PRODUCTS_PATH, {
    seedCandidates: [LEGACY_PRODUCTS_PATH],
    fallbackValue: () => ({ version: 1, updatedAt: new Date().toISOString(), products: [] }),
  });
  ensureJSONFile(CONFIG_PATH, {
    seedCandidates: [LEGACY_CONFIG_PATH],
    fallbackValue: () => ({ version: 2, minimumOrderCents: 1500 }),
  });
  ensureJSONFile(SELLERS_PATH, {
    seedCandidates: [LEGACY_SELLERS_PATH],
    fallbackValue: {},
  });
  ensureJSONFile(BUYERS_PATH, {
    fallbackValue: {},
  });
  ensureJSONFile(ORDERS_PATH, {
    seedCandidates: [LEGACY_ORDERS_PATH],
    fallbackValue: [],
  });
  ensureJSONFile(DROPS_PATH, {
    seedCandidates: [LEGACY_DROPS_PATH],
    fallbackValue: {},
  });
  ensureJSONFile(PRODUCT_REVIEWS_PATH, {
    fallbackValue: [],
  });
  ensureJSONFile(EXCHANGE_REQUESTS_PATH, {
    fallbackValue: [],
  });
  ensureJSONFile(CUSTOM_ORDER_REQUESTS_PATH, {
    fallbackValue: [],
  });
  ensureJSONFile(SELLER_INQUIRIES_PATH, {
    fallbackValue: [],
  });
  ensureJSONFile(WEBHOOK_EVENTS_PATH, {
    fallbackValue: () => ({ ids: [] }),
  });
}

initializeBackendStorage();

function hydrateWebhookProcessedIds() {
  try {
    const raw = JSON.parse(readFileSync(fileURLToPath(WEBHOOK_EVENTS_PATH), "utf-8"));
    const ids = Array.isArray(raw.ids) ? raw.ids : [];
    processedWebhookEventIds = new Set(ids);
  } catch {
    processedWebhookEventIds = new Set();
  }
}

hydrateWebhookProcessedIds();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getCachedDocument(key) {
  if (!DOCUMENT_MEMORY_CACHE.has(key)) return undefined;
  return DOCUMENT_MEMORY_CACHE.get(key);
}

function setCachedDocument(key, value) {
  DOCUMENT_MEMORY_CACHE.set(key, value);
}

function persistWebhookDedupeIds() {
  const arr = [...processedWebhookEventIds].slice(-2500);
  processedWebhookEventIds = new Set(arr);
  writeManagedJSON("webhookEvents", { ids: arr });
}

function readConfigDocumentMerged() {
  const cached = getCachedDocument("config");
  if (cached !== undefined) {
    return mergeExchangeConfig(cached);
  }
  try {
    const parsed = mergeExchangeConfig(JSON.parse(readFileSync(CONFIG_PATH, "utf-8")));
    setCachedDocument("config", parsed);
    return parsed;
  } catch {
    const fallback = mergeExchangeConfig({ version: 2, minimumOrderCents: 1500 });
    setCachedDocument("config", fallback);
    return fallback;
  }
}

function etagFromFileURL(targetURL) {
  try {
    const st = statSync(fileURLToPath(targetURL));
    return `"${Math.round(st.mtimeMs)}-${st.size}"`;
  } catch {
    return '"0"';
  }
}

function weakEtagFromString(value) {
  const h = crypto.createHash("sha1").update(String(value)).digest("hex").slice(0, 24);
  return `W/"${h}"`;
}

function sendPublicJsonWithCache(req, res, payload, { maxAgeSeconds, etag, extraHeaders = {} }) {
  const inm = req.headers["if-none-match"];
  if (inm && inm === etag) {
    res.set("Cache-Control", `public, max-age=${maxAgeSeconds}`);
    res.set("ETag", etag);
    for (const [hk, hv] of Object.entries(extraHeaders)) {
      res.set(hk, hv);
    }
    return res.status(304).end();
  }
  res.set("Cache-Control", `public, max-age=${maxAgeSeconds}`);
  res.set("ETag", etag);
  for (const [hk, hv] of Object.entries(extraHeaders)) {
    res.set(hk, hv);
  }
  return res.json(payload);
}

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch ${url} → ${res.status}`);
  return res.json();
}

async function fetchCatalog() {
  const hydrateCatalog = (catalog) => {
    const reviews = loadProductReviewsFile();
    const normalizedCatalog = {
      ...catalog,
      products: Array.isArray(catalog?.products)
        ? catalog.products.map((product) => normalizeCatalogProduct(product))
        : [],
    };
    return hydrateCatalogWithProductReviews(normalizedCatalog, reviews);
  };

  if (process.env.CATALOG_URL) {
    try {
      const remote = await fetchJSON(process.env.CATALOG_URL);
      setCachedDocument("products", remote);
      const hydrated = hydrateCatalog(remote);
      schedulePhase1CatalogCompare();
      return hydrated;
    } catch (e) {
      console.warn("CATALOG_URL fetch failed:", e.message);
    }
  }
  let catalogRaw = getCachedDocument("products");
  if (catalogRaw === undefined) {
    try {
      catalogRaw = JSON.parse(readFileSync(PRODUCTS_PATH, "utf-8"));
      setCachedDocument("products", catalogRaw);
    } catch {
      catalogRaw = { version: 1, updatedAt: new Date().toISOString(), products: [] };
      setCachedDocument("products", catalogRaw);
    }
  }
  const hydrated = hydrateCatalog(catalogRaw);
  schedulePhase1CatalogCompare();
  return hydrated;
}

function schedulePhase1CatalogCompare() {
  schedulePhase1Compare("catalog-read");
}

async function fetchConfig() {
  if (process.env.CONFIG_URL) {
    try {
      const remote = await fetchJSON(process.env.CONFIG_URL);
      const merged = mergeExchangeConfig(remote);
      setCachedDocument("config", merged);
      return merged;
    } catch (e) {
      console.warn("CONFIG_URL fetch failed:", e.message);
    }
  }
  return readConfigDocumentMerged();
}

async function fetchSellers() {
  if (process.env.SELLERS_URL) {
    try { return await fetchJSON(process.env.SELLERS_URL); } catch (e) {
      console.warn("SELLERS_URL fetch failed, falling back to local:", e.message);
    }
  }
  try {
    return normalizeSellerMap(JSON.parse(readFileSync(SELLERS_PATH, "utf-8")));
  } catch {
    console.warn("sellers.json not found, using empty map");
    return {};
  }
}

function normalizeMembership(membership = {}) {
  return {
    productId: membership.productId || SELLER_SUBSCRIPTION_PRODUCT_ID,
    hasActiveSubscription: membership.hasActiveSubscription === true,
    expiresAt: asISODateOrNull(membership.expiresAt),
    lastSyncedAt: asISODateOrNull(membership.lastSyncedAt),
    source: membership.source || "app_store",
    originalTransactionId: membership.originalTransactionId || null,
    transactionId: membership.transactionId || null,
    stripeSubscriptionId: membership.stripeSubscriptionId || null,
    stripeCustomerId: membership.stripeCustomerId || null,
  };
}

function asISODateOrNull(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return null;
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

function normalizeFoundingCreatorFields(record = {}) {
  const creatorBadge = String(record.creatorBadge || "Founding Creator").trim() || "Founding Creator";
  const startsAt = asISODateOrNull(record.foundingCreatorAccessStartsAt);
  const endsAt = asISODateOrNull(record.foundingCreatorAccessEndsAt);
  const isFoundingCreator = record.isFoundingCreator === true;
  return {
    isFoundingCreator,
    foundingCreatorAccessStartsAt: startsAt,
    foundingCreatorAccessEndsAt: endsAt,
    creatorBadge,
  };
}

function foundingCreatorStatus(record = {}, now = new Date()) {
  const founding = normalizeFoundingCreatorFields(record);
  const nowTs = now.getTime();
  const startsAtTs = founding.foundingCreatorAccessStartsAt
    ? new Date(founding.foundingCreatorAccessStartsAt).getTime()
    : null;
  const endsAtTs = founding.foundingCreatorAccessEndsAt
    ? new Date(founding.foundingCreatorAccessEndsAt).getTime()
    : null;

  const hasStarted = startsAtTs == null || nowTs >= startsAtTs;
  const hasNotEnded = endsAtTs != null && nowTs <= endsAtTs;
  const hasComplimentaryAccess = founding.isFoundingCreator && hasStarted && hasNotEnded;

  return {
    ...founding,
    hasComplimentaryAccess,
  };
}

function effectiveSellerMembershipStatus(record = {}, now = new Date()) {
  const membership = normalizeMembership(record.membership);
  const founding = foundingCreatorStatus(record, now);
  const hasActiveSubscription = membership.hasActiveSubscription === true || founding.hasComplimentaryAccess;
  const membershipStatus = founding.hasComplimentaryAccess
    ? "complimentary"
    : membership.hasActiveSubscription
      ? "active"
      : "expired";
  return {
    membership,
    founding,
    hasActiveSubscription,
    membershipStatus,
  };
}

function asFiniteNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function sanitizePathSegment(value, fallback = "file") {
  const normalized = String(value || "")
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, "-")
    .replace(/-+/g, "-");
  return normalized || fallback;
}

function sanitizeFileExtension(value, fallback = "bin") {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  return normalized || fallback;
}

function normalizeHostedMediaReference(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return null;
  if (trimmed.startsWith("/media/")) return trimmed;

  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol === "file:") {
      return null;
    }
    if (parsed.pathname.startsWith("/media/")) {
      return `${parsed.pathname}${parsed.search}`;
    }
  } catch {
    // Leave non-URL strings untouched below.
  }

  return trimmed;
}

function normalizeHostedMediaReferences(values) {
  if (!Array.isArray(values)) return [];
  return values
    .map((value) => normalizeHostedMediaReference(value))
    .filter(Boolean);
}

function isValidSellerId(value) {
  return /^[a-z0-9][a-z0-9_-]{2,23}$/.test(String(value || "").trim());
}

function normalizeRightsReferenceFlags(value) {
  return Array.isArray(value)
    ? value.map((flag) => String(flag || "").trim()).filter(Boolean)
    : [];
}

function normalizeCatalogProduct(product = {}) {
  const explicitApprovalStatus = String(product.approvalStatus || "").trim().toLowerCase();
  const resolvedApprovalStatus = explicitApprovalStatus || (
    product.isApproved === true && product.isActive !== false
      ? "approved"
      : product.reviewedAt || product.reviewNotes
        ? "rejected"
        : "submitted"
  );
  const isArchived = resolvedApprovalStatus === "archived";

  return {
    id: String(product.id || crypto.randomUUID()),
    sellerId: String(product.sellerId || "").trim(),
    name: String(product.name || "").trim(),
    priceCents: Math.max(0, asFiniteNumber(product.priceCents, 0)),
    previousPriceCents:
      product.previousPriceCents == null ? null : Math.max(0, asFiniteNumber(product.previousPriceCents, 0)),
    category: String(product.category || "desk").trim().toLowerCase(),
    imageURLs: normalizeHostedMediaReferences(product.imageURLs),
    demoVideoURL: normalizeHostedMediaReference(product.demoVideoURL),
    productionPreviewURL: normalizeHostedMediaReference(product.productionPreviewURL),
    dropHeadline: String(product.dropHeadline || "").trim(),
    dropStory: String(product.dropStory || "").trim(),
    dropBestUseCase: String(product.dropBestUseCase || "").trim(),
    material: String(product.material || "PLA+").trim(),
    durabilityNote: String(product.durabilityNote || "Built for everyday use.").trim(),
    careWarnings: Array.isArray(product.careWarnings) ? product.careWarnings.filter(Boolean) : [],
    shipsInMinDays: Math.max(1, asFiniteNumber(product.shipsInMinDays, 2)),
    shipsInMaxDays: Math.max(1, asFiniteNumber(product.shipsInMaxDays, 4)),
    isDrop: product.isDrop === true,
    isActive: isArchived ? false : product.isActive !== false,
    isApproved: isArchived ? false : product.isApproved !== false,
    approvalStatus: resolvedApprovalStatus,
    submittedAt: product.submittedAt || new Date().toISOString(),
    reviewedAt: product.reviewedAt || null,
    reviewNotes: product.reviewNotes || "",
    archivedAt: isArchived ? product.archivedAt || product.reviewedAt || null : null,
    rightsOwnershipType: product.rightsOwnershipType ? String(product.rightsOwnershipType).trim() : null,
    rightsReferenceFlags: normalizeRightsReferenceFlags(product.rightsReferenceFlags),
    rightsCertificationAccepted: product.rightsCertificationAccepted === true,
    rightsCertificationAcceptedAt: product.rightsCertificationAcceptedAt || null,
    requiresManualReview: product.requiresManualReview === true,
    reviewReason: product.reviewReason ? String(product.reviewReason).trim() : null,
  };
}

function auditContext(req, extra = {}) {
  return {
    requestId: req.requestId || null,
    ip: clientIp(req),
    method: req.method,
    path: req.originalUrl || req.url,
    ...extra,
  };
}

function auditOwnershipMismatch(req, details = {}) {
  recordSecurityAudit(req, {
    action: "ownership_mismatch",
    ...details,
  });
}

function constantTimeEquals(lhs = "", rhs = "") {
  const left = Buffer.from(String(lhs));
  const right = Buffer.from(String(rhs));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function setAdminSecurityHeaders(res) {
  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "base-uri 'self'",
      "connect-src 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "img-src 'self' data: https:",
      "media-src 'self' https:",
      "object-src 'none'",
      "script-src 'self'",
      "style-src 'self'",
    ].join("; ")
  );
}

function requireAdmin(req, res, next) {
  if (!ADMIN_API_KEY) {
    recordSecurityAudit(req, { action: "admin_auth_unconfigured" });
    return res.status(503).json({ error: "Admin auth is not configured" });
  }

  const sessionToken = readCookieValue(req.headers.cookie, ADMIN_SESSION_COOKIE_NAME);
  if (isValidAdminSessionToken(sessionToken)) {
    return next();
  }

  if (ADMIN_ALLOW_DIRECT_KEY_AUTH) {
    const bearerToken = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();
    const headerToken = String(req.headers["x-admin-key"] || "").trim();
    const providedToken = bearerToken || headerToken;
    if (providedToken && constantTimeEquals(providedToken, ADMIN_API_KEY)) {
      return next();
    }
  }

  recordSecurityAudit(req, {
    action: "admin_auth_failed",
    reason: "missing_or_invalid_admin_session",
  });
  return res.status(401).json({ error: "Admin session required" });
}

function requireAppClient(req, res, next) {
  if (!APP_API_KEY) {
    return next();
  }

  const headerToken = String(req.headers["x-tenbelow-app-key"] || "").trim();
  if (!headerToken || headerToken !== APP_API_KEY) {
    recordSecurityAudit(req, {
      action: "app_client_auth_failed",
      reason: "missing_or_invalid_app_key",
    });
    return res.status(401).json({ error: "Unauthorized app client" });
  }

  return next();
}

function issueUserSessionToken(payload) {
  if (!AUTH_JWT_SECRET) {
    throw new Error("AUTH_JWT_SECRET is not configured");
  }

  return jwt.sign(payload, AUTH_JWT_SECRET, {
    algorithm: "HS256",
    expiresIn: "30d",
  });
}

function decodeUserSessionToken(req) {
  if (!AUTH_JWT_SECRET) {
    return null;
  }

  const bearerToken = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();
  if (!bearerToken) {
    return null;
  }

  try {
    return jwt.verify(bearerToken, AUTH_JWT_SECRET);
  } catch {
    return null;
  }
}

function requireAuthenticatedUser(req, res, next) {
  const session = decodeUserSessionToken(req);
  if (!session) {
    recordSecurityAudit(req, {
      action: "user_session_missing_or_invalid",
      reason: "missing_or_invalid_bearer_token",
    });
    return res.status(401).json({ error: "Authenticated user session required" });
  }
  req.auth = session;
  return next();
}

function requireAuthenticatedBuyer(req, res, next) {
  const session = decodeUserSessionToken(req);
  if (!session || session.role !== "buyer") {
    recordSecurityAudit(req, {
      action: "buyer_session_missing_or_invalid",
      reason: !session ? "missing_or_invalid_bearer_token" : "role_mismatch",
    });
    return res.status(401).json({ error: "Authenticated buyer session required" });
  }
  req.auth = session;
  return next();
}

function requireAuthenticatedSeller(req, res, next) {
  const session = decodeUserSessionToken(req);
  if (!session || session.role !== "seller") {
    recordSecurityAudit(req, {
      action: "seller_session_missing_or_invalid",
      reason: !session ? "missing_or_invalid_bearer_token" : "role_mismatch",
    });
    return res.status(401).json({ error: "Authenticated seller session required" });
  }
  req.auth = session;
  return next();
}

function readCookieValue(cookieHeader = "", name) {
  const targetPrefix = `${name}=`;
  const parts = String(cookieHeader || "").split(";");
  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.startsWith(targetPrefix)) {
      return decodeURIComponent(trimmed.slice(targetPrefix.length));
    }
  }
  return "";
}

function createAdminSessionToken() {
  const signingSecret = AUTH_JWT_SECRET || ADMIN_API_KEY;
  if (!signingSecret) return "";
  return jwt.sign(
    {
      role: "admin",
      tokenType: "admin_session",
      sessionId: crypto.randomUUID(),
    },
    signingSecret,
    {
      algorithm: "HS256",
      issuer: "tenbelow-backend",
      audience: "tenbelow-admin",
      expiresIn: ADMIN_SESSION_TTL_SECONDS,
    }
  );
}

function maskedEmail(value = "") {
  const [localPart = "", domain = ""] = String(value || "").split("@");
  if (!localPart || !domain) return "";
  const visibleLocal = localPart.length <= 2
    ? `${localPart[0] || ""}*`
    : `${localPart.slice(0, 2)}***`;
  return `${visibleLocal}@${domain}`;
}

function pruneExpiredEmailOtpChallenges(now = Date.now()) {
  for (const [challengeId, challenge] of emailOtpChallenges.entries()) {
    if (!challenge?.expiresAt || challenge.expiresAt <= now) {
      emailOtpChallenges.delete(challengeId);
    }
  }
}

function emailOtpHash(challengeId, code) {
  return crypto
    .createHash("sha256")
    .update(`${challengeId}:${String(code || "").trim()}:${AUTH_JWT_SECRET || APP_API_KEY || ADMIN_API_KEY}`)
    .digest("hex");
}

function createEmailOtpChallenge({ req, purpose, email, subjectId = "" }) {
  pruneExpiredEmailOtpChallenges();

  const challengeId = crypto.randomUUID();
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");
  const expiresAt = Date.now() + EMAIL_OTP_TTL_MS;
  const normalizedEmail = String(email || "").trim().toLowerCase();

  emailOtpChallenges.set(challengeId, {
    purpose,
    email: normalizedEmail,
    subjectId: String(subjectId || "").trim(),
    codeHash: emailOtpHash(challengeId, code),
    expiresAt,
    attempts: 0,
    clientIp: clientIp(req),
    userAgent: String(req.headers["user-agent"] || "").slice(0, 240),
  });

  return { challengeId, code, expiresAt, email: normalizedEmail };
}

async function sendEmailOtp({ to, code, expiresAt, title, intro, warning }) {
  if (!transactionalEmailConfigured()) {
    throw new Error("Email codes require RESEND_API_KEY or SMTP settings on the backend.");
  }

  const expiration = new Date(expiresAt).toLocaleString("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
  });

  await sendTransactionalEmail({
    to,
    subject: title,
    html: `
      <h2>${escapeHtml(title)}</h2>
      <p>${escapeHtml(intro)}</p>
      <p style="font-size:28px;font-weight:700;letter-spacing:0.18em">${escapeHtml(code)}</p>
      <p>This code expires at ${escapeHtml(expiration)} and can only be used once.</p>
      <p>${escapeHtml(warning)}</p>
    `,
  });
}

function verifyEmailOtpChallenge({ challengeId, code, purpose, email, subjectId = "" }) {
  pruneExpiredEmailOtpChallenges();

  const normalizedChallengeId = String(challengeId || "").trim();
  const normalizedCode = String(code || "").replace(/\D/g, "");
  const normalizedEmail = String(email || "").trim().toLowerCase();
  const normalizedSubjectId = String(subjectId || "").trim();
  const challenge = emailOtpChallenges.get(normalizedChallengeId);

  if (!challenge || !normalizedCode) {
    return { ok: false, reason: "missing_or_expired_code" };
  }

  if (challenge.purpose !== purpose || challenge.email !== normalizedEmail) {
    return { ok: false, reason: "challenge_mismatch" };
  }

  if (normalizedSubjectId && challenge.subjectId && challenge.subjectId !== normalizedSubjectId) {
    return { ok: false, reason: "subject_mismatch" };
  }

  challenge.attempts += 1;
  if (challenge.attempts > EMAIL_OTP_MAX_ATTEMPTS) {
    emailOtpChallenges.delete(normalizedChallengeId);
    return { ok: false, reason: "too_many_attempts" };
  }

  const actualHash = emailOtpHash(normalizedChallengeId, normalizedCode);
  if (!constantTimeEquals(actualHash, challenge.codeHash)) {
    return { ok: false, reason: "invalid_code" };
  }

  emailOtpChallenges.delete(normalizedChallengeId);
  return { ok: true, challenge };
}

function isValidAdminSessionToken(token) {
  if (!token) return false;
  const signingSecret = AUTH_JWT_SECRET || ADMIN_API_KEY;
  if (!signingSecret) return false;

  try {
    const payload = jwt.verify(token, signingSecret, {
      algorithms: ["HS256"],
      issuer: "tenbelow-backend",
      audience: "tenbelow-admin",
    });
    return payload?.role === "admin" && payload?.tokenType === "admin_session";
  } catch {
    return false;
  }
}

function destroyAdminSessionToken(token) {
  // Admin sessions are signed cookies; clearing the browser cookie logs out this device.
}

function setAdminSessionCookie(res, token) {
  res.cookie(ADMIN_SESSION_COOKIE_NAME, token, {
    httpOnly: true,
    secure: IS_PRODUCTION,
    sameSite: "strict",
    path: "/admin",
    maxAge: ADMIN_SESSION_TTL_MS,
  });
}

function clearAdminCookies(res) {
  const options = {
    path: "/admin",
    secure: IS_PRODUCTION,
    sameSite: "strict",
  };
  res.clearCookie(ADMIN_SESSION_COOKIE_NAME, options);
  res.clearCookie(LEGACY_ADMIN_COOKIE_NAME, options);
}

function ensureAdminSessionFromLegacyCookie(req, res) {
  const sessionToken = readCookieValue(req.headers.cookie, ADMIN_SESSION_COOKIE_NAME);
  if (isValidAdminSessionToken(sessionToken)) {
    return true;
  }

  res.clearCookie(LEGACY_ADMIN_COOKIE_NAME, { path: "/admin" });
  return false;
}

function shouldAutoAuthenticateLocalAdmin(req) {
  return false;
}

function ensureLocalAdminSession(req, res) {
  if (ensureAdminSessionFromLegacyCookie(req, res)) {
    return true;
  }

  if (!shouldAutoAuthenticateLocalAdmin(req)) {
    return false;
  }

  const newSessionToken = createAdminSessionToken();
  setAdminSessionCookie(res, newSessionToken);
  return true;
}

function resolveManagedDataTarget(key) {
  const normalizedKey = String(key || "").trim();
  const fileURL = MANAGED_DATA_TARGETS[normalizedKey];
  if (!fileURL) {
    throw new Error(`Unsupported snapshot key: ${normalizedKey}`);
  }
  return { key: normalizedKey, fileURL };
}

function snapshotDirectoryURLForKey(key) {
  return new URL(`./${key}/`, SNAPSHOT_DIRECTORY_URL);
}

function isSnapshotDataFile(name = "") {
  return name.endsWith(".json") && !name.endsWith(".meta.json");
}

function snapshotMetaId(snapshotId = "") {
  return snapshotId.replace(/\.json$/i, ".meta.json");
}

function computeSnapshotIntegrity(rawJSON = "") {
  const sha256 = crypto.createHash("sha256").update(rawJSON, "utf8").digest("hex");
  const hmacSha256 = SNAPSHOT_SIGNING_SECRET
    ? crypto.createHmac("sha256", SNAPSHOT_SIGNING_SECRET).update(rawJSON, "utf8").digest("hex")
    : null;
  return { sha256, hmacSha256 };
}

function readSnapshotMetadata(key, snapshotId) {
  const keyDirectoryURL = snapshotDirectoryURLForKey(key);
  const metadataURL = new URL(`./${snapshotMetaId(snapshotId)}`, keyDirectoryURL);
  const metadataPath = fileURLToPath(metadataURL);
  if (!existsSync(metadataPath)) return null;
  try {
    return JSON.parse(readFileSync(metadataPath, "utf8"));
  } catch {
    return null;
  }
}

function createSnapshotId(label = "autosave") {
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const safeLabel = String(label || "autosave")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "") || "autosave";
  return `${ts}--${safeLabel}.json`;
}

function pruneSnapshotsForKey(key) {
  const directoryURL = snapshotDirectoryURLForKey(key);
  const directoryPath = fileURLToPath(directoryURL);
  if (!existsSync(directoryPath)) return;

  const files = readdirSync(directoryPath)
    .filter((name) => isSnapshotDataFile(name))
    .sort((lhs, rhs) => rhs.localeCompare(lhs));

  if (files.length <= SNAPSHOT_RETENTION_PER_KEY) return;

  for (const staleFile of files.slice(SNAPSHOT_RETENTION_PER_KEY)) {
    try {
      const staleDataURL = new URL(`./${staleFile}`, directoryURL);
      unlinkSync(fileURLToPath(staleDataURL));
      const staleMetaURL = new URL(`./${snapshotMetaId(staleFile)}`, directoryURL);
      const staleMetaPath = fileURLToPath(staleMetaURL);
      if (existsSync(staleMetaPath)) {
        unlinkSync(staleMetaPath);
      }
    } catch {
      // ignore snapshot pruning failures
    }
  }
}

function createDataSnapshot(key, label = "autosave") {
  const { key: normalizedKey, fileURL } = resolveManagedDataTarget(key);
  const sourcePath = fileURLToPath(fileURL);
  if (!existsSync(sourcePath)) return null;

  const keyDirectoryURL = snapshotDirectoryURLForKey(normalizedKey);
  ensureDirectory(SNAPSHOT_DIRECTORY_URL);
  ensureDirectory(keyDirectoryURL);

  const snapshotId = createSnapshotId(label);
  const snapshotURL = new URL(`./${snapshotId}`, keyDirectoryURL);
  copyFileSync(fileURL, snapshotURL);
  try {
    const raw = readFileSync(fileURLToPath(snapshotURL), "utf8");
    const integrity = computeSnapshotIntegrity(raw);
    const metadata = {
      snapshotId,
      key: normalizedKey,
      createdAt: new Date().toISOString(),
      label: String(label || "autosave"),
      sizeBytes: Buffer.byteLength(raw, "utf8"),
      ...integrity,
    };
    const metadataURL = new URL(`./${snapshotMetaId(snapshotId)}`, keyDirectoryURL);
    writeFileSync(metadataURL, JSON.stringify(metadata, null, 2));
  } catch {
    // snapshot data is still valid even if metadata write fails
  }
  pruneSnapshotsForKey(normalizedKey);
  return snapshotId;
}

function writeManagedJSON(key, payload) {
  const { fileURL } = resolveManagedDataTarget(key);
  createDataSnapshot(key, "autosave");
  writeFileSync(fileURL, JSON.stringify(payload, null, 2));
  DOCUMENT_MEMORY_CACHE.set(key, payload);
  if (isPgEnabled()) {
    void upsertDocumentRow(key, payload).catch((err) =>
      console.error("Postgres upsert failed:", key, err.message)
    );
    void upsertRelationalForManagedDocument(key, payload).catch((err) =>
      console.error("Postgres relational upsert failed:", key, err.message)
    );
  }
  void syncPhase1AfterJsonWrite(key);
}

function listDataSnapshots(key, limit = 50) {
  const { key: normalizedKey } = resolveManagedDataTarget(key);
  const keyDirectoryURL = snapshotDirectoryURLForKey(normalizedKey);
  const keyDirectoryPath = fileURLToPath(keyDirectoryURL);
  if (!existsSync(keyDirectoryPath)) return [];

  const cappedLimit = Math.max(1, Math.min(500, Number(limit) || 50));
  return readdirSync(keyDirectoryPath)
    .filter((name) => isSnapshotDataFile(name))
    .sort((lhs, rhs) => rhs.localeCompare(lhs))
    .slice(0, cappedLimit)
    .map((name) => {
      const filePath = fileURLToPath(new URL(`./${name}`, keyDirectoryURL));
      let createdAt = null;
      let sizeBytes = 0;
      const metadata = readSnapshotMetadata(normalizedKey, name);
      try {
        const stats = statSync(filePath);
        createdAt = stats.mtime.toISOString();
        sizeBytes = stats.size;
      } catch {
        // ignore stat read failures
      }
      return {
        snapshotId: name,
        createdAt,
        sizeBytes,
        sha256: metadata?.sha256 || null,
        hmacSha256: metadata?.hmacSha256 || null,
      };
    });
}

function readManagedRawJSON(key) {
  const { fileURL } = resolveManagedDataTarget(key);
  const filePath = fileURLToPath(fileURL);
  return existsSync(filePath) ? readFileSync(filePath, "utf8") : "";
}

function readSnapshotRawJSON(key, snapshotId) {
  const { key: normalizedKey } = resolveManagedDataTarget(key);
  const safeSnapshotId = String(snapshotId || "").trim();
  if (!/^[a-zA-Z0-9._-]+\.json$/.test(safeSnapshotId)) {
    throw new Error("Invalid snapshot id");
  }
  const keyDirectoryURL = snapshotDirectoryURLForKey(normalizedKey);
  const snapshotURL = new URL(`./${safeSnapshotId}`, keyDirectoryURL);
  const snapshotPath = fileURLToPath(snapshotURL);
  if (!existsSync(snapshotPath)) {
    throw new Error("Snapshot not found");
  }
  return {
    key: normalizedKey,
    snapshotId: safeSnapshotId,
    snapshotURL,
    raw: readFileSync(snapshotPath, "utf8"),
  };
}

function verifySnapshotIntegrity(key, snapshotId, raw) {
  const metadata = readSnapshotMetadata(key, snapshotId);
  if (!metadata) return { ok: true, metadata: null };

  const computed = computeSnapshotIntegrity(raw);
  if (metadata.sha256 && metadata.sha256 !== computed.sha256) {
    throw new Error("Snapshot integrity check failed (sha256 mismatch)");
  }
  if (metadata.hmacSha256 && computed.hmacSha256 && metadata.hmacSha256 !== computed.hmacSha256) {
    throw new Error("Snapshot integrity check failed (signature mismatch)");
  }
  return { ok: true, metadata };
}

function summarizeJSONDiff(beforeRaw, afterRaw) {
  const changed = beforeRaw !== afterRaw;
  const summary = {
    changed,
    beforeBytes: Buffer.byteLength(beforeRaw || "", "utf8"),
    afterBytes: Buffer.byteLength(afterRaw || "", "utf8"),
    topLevelAdded: [],
    topLevelRemoved: [],
    topLevelChanged: [],
  };

  let beforeJSON = null;
  let afterJSON = null;
  try { beforeJSON = beforeRaw ? JSON.parse(beforeRaw) : null; } catch {}
  try { afterJSON = afterRaw ? JSON.parse(afterRaw) : null; } catch {}

  const beforeIsObject = beforeJSON && typeof beforeJSON === "object" && !Array.isArray(beforeJSON);
  const afterIsObject = afterJSON && typeof afterJSON === "object" && !Array.isArray(afterJSON);
  if (beforeIsObject && afterIsObject) {
    const beforeKeys = new Set(Object.keys(beforeJSON));
    const afterKeys = new Set(Object.keys(afterJSON));
    for (const key of afterKeys) {
      if (!beforeKeys.has(key)) summary.topLevelAdded.push(key);
    }
    for (const key of beforeKeys) {
      if (!afterKeys.has(key)) summary.topLevelRemoved.push(key);
    }
    for (const key of beforeKeys) {
      if (afterKeys.has(key)) {
        const beforeVal = JSON.stringify(beforeJSON[key]);
        const afterVal = JSON.stringify(afterJSON[key]);
        if (beforeVal !== afterVal) summary.topLevelChanged.push(key);
      }
    }
  }
  return summary;
}

function restoreDataSnapshot(key, snapshotId) {
  const { key: normalizedKey, fileURL } = resolveManagedDataTarget(key);
  const snapshot = readSnapshotRawJSON(normalizedKey, snapshotId);
  verifySnapshotIntegrity(normalizedKey, snapshot.snapshotId, snapshot.raw);

  createDataSnapshot(normalizedKey, "pre-restore");
  copyFileSync(snapshot.snapshotURL, fileURL);
}

function buildSnapshotRestorePreview(key, snapshotId) {
  const snapshot = readSnapshotRawJSON(key, snapshotId);
  const integrity = verifySnapshotIntegrity(snapshot.key, snapshot.snapshotId, snapshot.raw);
  const currentRaw = readManagedRawJSON(snapshot.key);
  return {
    key: snapshot.key,
    snapshotId: snapshot.snapshotId,
    integrity: {
      ok: true,
      sha256: integrity.metadata?.sha256 || computeSnapshotIntegrity(snapshot.raw).sha256,
      hasSignature: Boolean(integrity.metadata?.hmacSha256),
    },
    diff: summarizeJSONDiff(currentRaw, snapshot.raw),
  };
}

function buildSnapshotComparePreview(key, leftSnapshotId, rightSnapshotId) {
  const left = readSnapshotRawJSON(key, leftSnapshotId);
  const right = readSnapshotRawJSON(key, rightSnapshotId);
  const leftIntegrity = verifySnapshotIntegrity(left.key, left.snapshotId, left.raw);
  const rightIntegrity = verifySnapshotIntegrity(right.key, right.snapshotId, right.raw);

  return {
    key: left.key,
    leftSnapshot: {
      snapshotId: left.snapshotId,
      integrity: {
        ok: true,
        sha256: leftIntegrity.metadata?.sha256 || computeSnapshotIntegrity(left.raw).sha256,
        hasSignature: Boolean(leftIntegrity.metadata?.hmacSha256),
      },
    },
    rightSnapshot: {
      snapshotId: right.snapshotId,
      integrity: {
        ok: true,
        sha256: rightIntegrity.metadata?.sha256 || computeSnapshotIntegrity(right.raw).sha256,
        hasSignature: Boolean(rightIntegrity.metadata?.hmacSha256),
      },
    },
    diff: summarizeJSONDiff(left.raw, right.raw),
  };
}

function incidentIdForAuditEntry(entry = {}) {
  const action = String(entry?.action || "incident");
  const code = String(entry?.code || entry?.snapshotId || "generic");
  const ts = String(entry?.ts || "unknown");
  return `${action}:${code}:${ts}`;
}

function incidentStateDetails(entries = [], incidentId = "") {
  const normalizedIncidentId = String(incidentId || "").trim();
  if (!normalizedIncidentId) {
    return {
      currentState: "open",
      acknowledgedAt: null,
      acknowledgedNote: "",
      resolvedAt: null,
      resolvedNote: "",
      closedAt: null,
      closedNote: "",
    };
  }

  const stateEntries = entries.filter((entry) => String(entry?.incidentId || "").trim() === normalizedIncidentId);
  const latestForAction = (action) =>
    stateEntries.find((entry) => String(entry?.action || "").trim() === action) || null;

  const acknowledged = latestForAction("security_incident_acknowledged");
  const resolved = latestForAction("security_incident_resolved");
  const closed = latestForAction("security_incident_closed");

  let currentState = "open";
  if (closed) currentState = "closed";
  else if (resolved) currentState = "resolved";
  else if (acknowledged) currentState = "acknowledged";

  return {
    currentState,
    acknowledgedAt: acknowledged?.ts || null,
    acknowledgedNote: acknowledged?.note || "",
    resolvedAt: resolved?.ts || null,
    resolvedNote: resolved?.note || "",
    closedAt: closed?.ts || null,
    closedNote: closed?.note || "",
  };
}

function buildSecurityAlerts(events) {
  const now = Date.now();
  const recentEvents = events.filter((entry) => {
    const ts = new Date(entry?.ts || 0).getTime();
    return Number.isFinite(ts) && now - ts <= SECURITY_ALERT_WINDOW_MS;
  });

  const recentAuthFailures = recentEvents.filter((entry) => {
    const action = String(entry?.action || "");
    return (
      action === "admin_auth_failed" ||
      action === "app_client_auth_failed" ||
      action === "user_session_missing_or_invalid" ||
      action === "buyer_session_missing_or_invalid" ||
      action === "seller_session_missing_or_invalid" ||
      action === "admin_login_failed"
    );
  }).length;

  const recentOwnershipMismatches = recentEvents.filter(
    (entry) => String(entry?.action || "") === "ownership_mismatch"
  ).length;

  const alerts = [];
  if (recentAuthFailures >= SECURITY_ALERT_AUTH_FAILURE_THRESHOLD) {
    alerts.push({
      severity: "high",
      code: "auth_failures_spike",
      count: recentAuthFailures,
      threshold: SECURITY_ALERT_AUTH_FAILURE_THRESHOLD,
      windowMs: SECURITY_ALERT_WINDOW_MS,
      message: "Auth failures exceeded threshold in the recent window.",
    });
  }

  if (recentOwnershipMismatches >= SECURITY_ALERT_OWNERSHIP_MISMATCH_THRESHOLD) {
    alerts.push({
      severity: "high",
      code: "ownership_mismatch_spike",
      count: recentOwnershipMismatches,
      threshold: SECURITY_ALERT_OWNERSHIP_MISMATCH_THRESHOLD,
      windowMs: SECURITY_ALERT_WINDOW_MS,
      message: "Ownership mismatch denials exceeded threshold in the recent window.",
    });
  }

  return {
    alerts,
    recentWindow: {
      windowMs: SECURITY_ALERT_WINDOW_MS,
      authFailures: recentAuthFailures,
      ownershipMismatches: recentOwnershipMismatches,
    },
  };
}

function isSecurityRelevantAction(action = "") {
  return (
    action === "ownership_mismatch" ||
    action === "admin_auth_failed" ||
    action === "app_client_auth_failed" ||
    action === "user_session_missing_or_invalid" ||
    action === "buyer_session_missing_or_invalid" ||
    action === "seller_session_missing_or_invalid" ||
    action === "admin_login_failed"
  );
}

function resolveSecurityAlertDestinations(severity = "high") {
  const normalizedSeverity = String(severity || "high").trim().toLowerCase();
  return {
    webhookURL:
      (normalizedSeverity === "high" ? SECURITY_ALERT_WEBHOOK_URL_HIGH : SECURITY_ALERT_WEBHOOK_URL_MEDIUM) ||
      SECURITY_ALERT_WEBHOOK_URL,
    slackWebhookURL:
      (normalizedSeverity === "high" ? SLACK_ALERT_WEBHOOK_URL_HIGH : SLACK_ALERT_WEBHOOK_URL_MEDIUM) ||
      SECURITY_ALERT_SLACK_WEBHOOK_URL,
  };
}

async function postWebhookJSON(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new Error(`Webhook ${url} failed (${response.status})`);
  }
}

async function dispatchSecurityAlert(payload, { bypassCooldown = false } = {}) {
  const severity = String(payload?.severity || "high").trim().toLowerCase();
  const code = String(payload?.code || "unknown_alert");
  const { webhookURL, slackWebhookURL } = resolveSecurityAlertDestinations(severity);

  const now = Date.now();
  const cooldownKey = `${severity}:${code}`;
  const lastEscalatedAt = securityAlertEscalationState.get(cooldownKey) || 0;
  if (!bypassCooldown && now - lastEscalatedAt < SECURITY_ALERT_COOLDOWN_MS) {
    return;
  }

  const fullPayload = {
    at: new Date(now).toISOString(),
    ...payload,
    severity,
    code,
  };

  if (!webhookURL && !slackWebhookURL) {
    securityAlertEscalationState.set(cooldownKey, now);
    auditLog({
      ts: fullPayload.at,
      action: "security_alert_escalated",
      code: fullPayload.code,
      severity: fullPayload.severity,
      count: fullPayload.count ?? null,
      threshold: fullPayload.threshold ?? null,
      trigger: fullPayload.trigger || null,
      destinations: {
        webhook: false,
        slack: false,
      },
      delivery: "no_destination_configured",
    });
    return;
  }

  try {
    if (webhookURL) {
      await postWebhookJSON(webhookURL, fullPayload);
    }
    if (slackWebhookURL) {
      await postWebhookJSON(slackWebhookURL, {
        text:
          `TenBelow security alert (${fullPayload.severity}) ${fullPayload.code}\n` +
          `${fullPayload.message || "No message provided."}\n` +
          `count=${fullPayload.count ?? "n/a"} threshold=${fullPayload.threshold ?? "n/a"} windowMs=${fullPayload.windowMs ?? "n/a"}\n` +
          `trigger=${fullPayload.trigger || "manual"}`,
      });
    }
    securityAlertEscalationState.set(cooldownKey, now);
    auditLog({
      ts: fullPayload.at,
      action: "security_alert_escalated",
      code: fullPayload.code,
      severity: fullPayload.severity,
      count: fullPayload.count ?? null,
      threshold: fullPayload.threshold ?? null,
      trigger: fullPayload.trigger || null,
      destinations: {
        webhook: Boolean(webhookURL),
        slack: Boolean(slackWebhookURL),
      },
    });
  } catch (err) {
    auditLog({
      ts: new Date(now).toISOString(),
      action: "security_alert_escalation_failed",
      code: fullPayload.code,
      severity: fullPayload.severity,
      error: err?.message || String(err),
    });
  }
}

async function escalateSecurityAlertsIfNeeded(trigger = "") {
  const defaultDestinations = resolveSecurityAlertDestinations("high");
  const mediumDestinations = resolveSecurityAlertDestinations("medium");
  if (!defaultDestinations.webhookURL && !defaultDestinations.slackWebhookURL &&
      !mediumDestinations.webhookURL && !mediumDestinations.slackWebhookURL) return;

  const entries = readAuditLogTail(4000, { maxCap: AUDIT_LOG_SCAN_MAX });
  const relevant = entries.filter((entry) => isSecurityRelevantAction(String(entry?.action || "")));
  const alertSummary = buildSecurityAlerts(relevant);
  if (!Array.isArray(alertSummary.alerts) || !alertSummary.alerts.length) return;

  for (const alert of alertSummary.alerts) {
    await dispatchSecurityAlert({
      severity: alert.severity,
      code: alert.code,
      message: alert.message,
      count: alert.count,
      threshold: alert.threshold,
      windowMs: alert.windowMs,
      trigger,
      recentWindow: alertSummary.recentWindow,
    });
  }
}

function recordSecurityAudit(req, details) {
  const action = String(details?.action || "security_event");
  auditLog(auditContext(req, details));
  if (isSecurityRelevantAction(action)) {
    void escalateSecurityAlertsIfNeeded(action);
  }
}

function incidentHistoryMatchesQuery(inc, q) {
  if (!q) return true;
  const needle = q.toLowerCase();
  const hay = [
    inc.incidentId,
    inc.code,
    inc.trigger,
    inc.currentState,
    inc.acknowledgmentNote,
    inc.resolvedNote,
    inc.closedNote,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return hay.includes(needle);
}

function restoreHistoryMatchesQuery(item, q) {
  if (!q) return true;
  const needle = q.toLowerCase();
  const diff = item.diff || {};
  const hay = [
    item.key,
    item.snapshotId,
    item.leftSnapshotId,
    item.rightSnapshotId,
    item.action,
    ...(diff.topLevelChanged || []),
    ...(diff.topLevelAdded || []),
    ...(diff.topLevelRemoved || []),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return hay.includes(needle);
}

/**
 * Scans the newest audit lines (up to scanLines, capped by AUDIT_LOG_SCAN_MAX), then filters and paginates.
 */
function buildIncidentHistory(options = {}) {
  const {
    scanLines = AUDIT_LOG_SCAN_MAX,
    incidentsPage = 1,
    incidentsPageSize = 20,
    incidentsQ = "",
    incidentsState = "",
    restoresPage = 1,
    restoresPageSize = 20,
    restoresQ = "",
    restoresAction = "",
  } = options;

  const linesToRead = Math.max(1000, Math.min(AUDIT_LOG_SCAN_MAX, Number(scanLines) || AUDIT_LOG_SCAN_MAX));
  const entries = readAuditLogTail(linesToRead, { maxCap: AUDIT_LOG_SCAN_MAX });

  const allEscalations = entries.filter((entry) => {
    const action = String(entry?.action || "");
    return action === "security_alert_escalated" || action === "security_alert_escalation_failed";
  });

  const incidentsFull = allEscalations.map((entry) => {
    const incidentId = incidentIdForAuditEntry(entry);
    const state = incidentStateDetails(entries, incidentId);
    return {
      incidentId,
      ts: entry.ts || null,
      action: entry.action,
      code: entry.code || null,
      severity: entry.severity || "high",
      trigger: entry.trigger || null,
      count: entry.count ?? null,
      threshold: entry.threshold ?? null,
      error: entry.error || null,
      currentState: state.currentState,
      acknowledged: state.currentState !== "open",
      acknowledgedAt: state.acknowledgedAt,
      acknowledgmentNote: state.acknowledgmentNote,
      resolvedAt: state.resolvedAt,
      resolvedNote: state.resolvedNote,
      closedAt: state.closedAt,
      closedNote: state.closedNote,
    };
  });

  const qIncidents = String(incidentsQ || "").trim();
  const stateNorm = String(incidentsState || "").trim().toLowerCase();
  const filteredIncidents = incidentsFull.filter((inc) => {
    if (stateNorm && String(inc.currentState || "").toLowerCase() !== stateNorm) return false;
    return incidentHistoryMatchesQuery(inc, qIncidents);
  });

  const ip = Math.max(0, Number(incidentsPage) - 1);
  const iSize = Math.max(1, Number(incidentsPageSize) || 20);
  const incidentsTotal = filteredIncidents.length;
  const incidents = filteredIncidents.slice(ip * iSize, ip * iSize + iSize);

  const allRestores = entries
    .filter((entry) => {
      const action = String(entry?.action || "");
      return (
        action === "admin_snapshot_restore" ||
        action === "admin_snapshot_restore_dry_run" ||
        action === "admin_snapshot_compare"
      );
    })
    .map((entry) => ({
      historyId: incidentIdForAuditEntry(entry),
      ts: entry.ts || null,
      action: entry.action,
      key: entry.key || null,
      snapshotId: entry.snapshotId || null,
      leftSnapshotId: entry.leftSnapshotId || null,
      rightSnapshotId: entry.rightSnapshotId || null,
      changed: entry.changed === true,
      diff: entry.diff || null,
    }));

  const qRestores = String(restoresQ || "").trim();
  const actionNorm = String(restoresAction || "").trim();
  const filteredRestores = allRestores.filter((item) => {
    if (actionNorm && item.action !== actionNorm) return false;
    return restoreHistoryMatchesQuery(item, qRestores);
  });

  const rp = Math.max(0, Number(restoresPage) - 1);
  const rSize = Math.max(1, Number(restoresPageSize) || 20);
  const restoresTotal = filteredRestores.length;
  const restoreHistory = filteredRestores.slice(rp * rSize, rp * rSize + rSize);

  return {
    incidents,
    incidentsTotal,
    incidentsPage: Math.max(1, Number(incidentsPage) || 1),
    incidentsPageSize: iSize,
    restoreHistory,
    restoresTotal,
    restoresPage: Math.max(1, Number(restoresPage) || 1),
    restoresPageSize: rSize,
    auditLinesScanned: entries.length,
    auditScanCap: AUDIT_LOG_SCAN_MAX,
  };
}


function saveCatalog(catalog = {}) {
  const normalizedProducts = Array.isArray(catalog.products)
    ? catalog.products.map((product) => normalizeCatalogProduct(product))
    : [];
  const payload = {
    version: Math.max(1, asFiniteNumber(catalog.version, 1)),
    updatedAt: new Date().toISOString(),
    products: normalizedProducts,
  };
  writeManagedJSON("products", payload);
}

function loadProductReviewsFile() {
  const cached = getCachedDocument("productReviews");
  if (cached !== undefined) {
    return Array.isArray(cached) ? cached : [];
  }
  try {
    const parsed = JSON.parse(readFileSync(PRODUCT_REVIEWS_PATH, "utf-8"));
    const arr = Array.isArray(parsed) ? parsed : [];
    setCachedDocument("productReviews", arr);
    return arr;
  } catch {
    setCachedDocument("productReviews", []);
    return [];
  }
}

function saveProductReviewsFile(reviews) {
  writeManagedJSON("productReviews", Array.isArray(reviews) ? reviews : []);
}

function buildProductReviewSummaryMap(reviews = []) {
  const summaryMap = new Map();

  for (const review of reviews) {
    const productId = String(review.productId || "").trim();
    const rating = Math.max(1, Math.min(5, asFiniteNumber(review.rating, 0)));
    if (!productId || !rating) continue;

    const current = summaryMap.get(productId) || { total: 0, count: 0 };
    current.total += rating;
    current.count += 1;
    summaryMap.set(productId, current);
  }

  return summaryMap;
}

function hydrateCatalogWithProductReviews(catalog = {}, reviews = []) {
  const summaryMap = buildProductReviewSummaryMap(reviews);
  const products = Array.isArray(catalog.products) ? catalog.products : [];

  return {
    ...catalog,
    products: products.map((product) => {
      const summary = summaryMap.get(product.id);
      if (!summary || summary.count <= 0) {
        return {
          ...product,
          averageRating: 0,
          reviewCount: 0,
        };
      }

      return {
        ...product,
        averageRating: Number((summary.total / summary.count).toFixed(1)),
        reviewCount: summary.count,
      };
    }),
  };
}

function orderContainsDeliveredProductForBuyer(order, buyerEmail, productId) {
  const normalizedBuyerEmail = String(buyerEmail || "").trim().toLowerCase();
  if (!normalizedBuyerEmail || !productId) return false;

  const orderBuyerEmail = String(order?.buyerEmail || "").trim().toLowerCase();
  if (orderBuyerEmail !== normalizedBuyerEmail) return false;

  return (order?.shipments || []).some((shipment) => {
    const isDelivered = shipment?.status === "delivered" || order?.status === "delivered";
    return isDelivered && (shipment?.items || []).some((item) => item.productId === productId);
  });
}

function normalizeSellerPublicProfile(profile = {}, sellerId = "", businessName = "") {
  const trimmedSellerId = String(sellerId || "").trim();
  const normalizedHandleBase = String(profile.handle || trimmedSellerId).trim().replace(/^@+/, "");
  const customInfoRaw =
    profile.customOrderInfoURL != null && profile.customOrderInfoURL !== ""
      ? String(profile.customOrderInfoURL).trim()
      : "";

  return {
    displayName: String(profile.displayName || businessName || trimmedSellerId || "TenBelow Seller").trim(),
    handle: `@${normalizedHandleBase || "tenbelowseller"}`,
    bio: String(profile.bio || "Independent TenBelow seller creating 3D-printed products.").trim(),
    avatarURL: normalizeHostedMediaReference(profile.avatarURL),
    bannerURL: normalizeHostedMediaReference(profile.bannerURL),
    websiteURL: profile.websiteURL || null,
    location: String(profile.location || "TenBelow").trim(),
    materials: Array.isArray(profile.materials) ? profile.materials.filter(Boolean) : [],
    processingTime: String(profile.processingTime || "Printed fresh to order").trim(),
    productCount: Math.max(0, asFiniteNumber(profile.productCount, 0)),
    orderCount: Math.max(0, asFiniteNumber(profile.orderCount, 0)),
    totalReviewCount: Math.max(0, asFiniteNumber(profile.totalReviewCount, 0)),
    positiveReviewCount: Math.max(0, asFiniteNumber(profile.positiveReviewCount, 0)),
    rating: Math.max(0, asFiniteNumber(profile.rating, 0)),
    likeCount: Math.max(0, asFiniteNumber(profile.likeCount, 0)),
    pageViewCount: Math.max(0, asFiniteNumber(profile.pageViewCount, 0)),
    designLicense: String(profile.designLicense || "Original Designs").trim(),
    isVerified: profile.isVerified === true,
    joinedAt: profile.joinedAt || new Date().toISOString(),
    shipsInMinDays: Math.max(1, asFiniteNumber(profile.shipsInMinDays, 2)),
    shipsInMaxDays: Math.max(1, asFiniteNumber(profile.shipsInMaxDays, 5)),
    acceptsCustomOrders: profile.acceptsCustomOrders === true,
    customOrderInfoURL: customInfoRaw || null,
  };
}

function normalizeSellerRecord(record = {}, sellerId = "") {
  const founding = normalizeFoundingCreatorFields(record);
  const effectiveMembership = effectiveSellerMembershipStatus(record);
  return {
    stripeAccountId: record.stripeAccountId || "",
    email: record.email || "",
    passwordHash: String(record.passwordHash || "").trim(),
    businessName: record.businessName || "",
    legalName: String(record.legalName || "").trim(),
    shippingOrigin: {
      country: String(record.shippingOrigin?.country || "").trim(),
      state: String(record.shippingOrigin?.state || "").trim(),
    },
    sellerAgreement: {
      accepted: record.sellerAgreement?.accepted === true,
      acceptedAt: record.sellerAgreement?.acceptedAt || null,
      version: record.sellerAgreement?.version || "seller-agreement-2026-04-24",
    },
    sellerPoliciesAcknowledged: record.sellerPoliciesAcknowledged === true,
    membership: normalizeMembership(record.membership),
    isFoundingCreator: founding.isFoundingCreator,
    foundingCreatorAccessStartsAt: founding.foundingCreatorAccessStartsAt,
    foundingCreatorAccessEndsAt: founding.foundingCreatorAccessEndsAt,
    creatorBadge: founding.creatorBadge,
    membershipStatus: effectiveMembership.membershipStatus,
    profile: normalizeSellerPublicProfile(record.profile, sellerId, record.businessName),
  };
}

function isStripeConnectConfigured() {
  return Boolean(STRIPE_SECRET_KEY && !STRIPE_SECRET_KEY.includes("REPLACE") && !STRIPE_SECRET_KEY.includes("YOUR_"));
}

function stripePendingSellerStatus(sellerId, seller = {}) {
  const membership = effectiveSellerMembershipStatus(seller);
  return {
    sellerId,
    stripeAccountId: seller.stripeAccountId || "",
    chargesEnabled: false,
    payoutsEnabled: false,
    detailsSubmitted: false,
    onboardingComplete: false,
    payoutSetupPending: true,
    payoutSetupActionRequired: true,
    payoutSetupMessage: STRIPE_CONNECT_SETUP_MESSAGE,
    hasActiveSubscription: membership.hasActiveSubscription,
    hasPaidSubscription: membership.membership.hasActiveSubscription,
    subscriptionExpiresAt: membership.membership.expiresAt || null,
    subscriptionProductId: membership.membership.productId || SELLER_SUBSCRIPTION_PRODUCT_ID,
    membershipStatus: membership.membershipStatus,
    isFoundingCreator: membership.founding.isFoundingCreator,
    foundingCreatorAccessStartsAt: membership.founding.foundingCreatorAccessStartsAt,
    foundingCreatorAccessEndsAt: membership.founding.foundingCreatorAccessEndsAt,
    creatorBadge: membership.founding.creatorBadge,
  };
}

function normalizeSellerMap(sellers = {}) {
  return Object.fromEntries(
    Object.entries(sellers).map(([sellerId, record]) => [sellerId, normalizeSellerRecord(record, sellerId)])
  );
}

function buildSellerProfile(sellerId, sellerRecord = {}, catalogProducts = [], orders = []) {
  const publicProfile = normalizeSellerPublicProfile(
    sellerRecord.profile,
    sellerId,
    sellerRecord.businessName
  );
  const activeProducts = catalogProducts.filter(
    (product) => product.sellerId === sellerId && product.isActive && product.isApproved
  );
  const materialSet = new Set([
    ...publicProfile.materials,
    ...activeProducts.map((product) => product.material).filter(Boolean),
  ]);
  const shipMinDays = activeProducts.length
    ? Math.min(...activeProducts.map((product) => asFiniteNumber(product.shipsInMinDays, publicProfile.shipsInMinDays)))
    : publicProfile.shipsInMinDays;
  const shipMaxDays = activeProducts.length
    ? Math.max(...activeProducts.map((product) => asFiniteNumber(product.shipsInMaxDays, publicProfile.shipsInMaxDays)))
    : publicProfile.shipsInMaxDays;
  const shipmentCount = orders.reduce(
    (count, order) => count + (order.shipments || []).filter((shipment) => shipment.sellerId === sellerId).length,
    0
  );

  return {
    id: sellerId,
    displayName: publicProfile.displayName,
    handle: publicProfile.handle,
    bio: publicProfile.bio,
    avatarURL: publicProfile.avatarURL,
    bannerURL: publicProfile.bannerURL,
    websiteURL: publicProfile.websiteURL,
    location: publicProfile.location,
    shipsInMinDays: Math.min(shipMinDays, shipMaxDays),
    shipsInMaxDays: Math.max(shipMinDays, shipMaxDays),
    materials: Array.from(materialSet),
    processingTime: publicProfile.processingTime,
    productCount: activeProducts.length || publicProfile.productCount,
    orderCount: Math.max(publicProfile.orderCount, shipmentCount),
    totalReviewCount: publicProfile.totalReviewCount,
    positiveReviewCount: publicProfile.positiveReviewCount,
    rating: publicProfile.rating,
    likeCount: publicProfile.likeCount,
    pageViewCount: publicProfile.pageViewCount,
    designLicense: publicProfile.designLicense,
    isVerified: publicProfile.isVerified,
    joinedAt: publicProfile.joinedAt,
    acceptsCustomOrders: publicProfile.acceptsCustomOrders,
    customOrderInfoURL: publicProfile.customOrderInfoURL,
  };
}

function sellerQualifiesForVerifiedMarketplaceAccess(sellerId, sellers = {}, catalogProducts = [], orders = []) {
  const profile = buildSellerProfile(sellerId, sellers[sellerId], catalogProducts, orders);
  const joinedAt = new Date(profile.joinedAt || Date.now());
  const activeDays = Math.max(
    0,
    Math.floor((Date.now() - joinedAt.getTime()) / (1000 * 60 * 60 * 24))
  );

  if (profile.isVerified === true) {
    return true;
  }

  return (
    profile.orderCount >= SELLER_VERIFICATION_MIN_SALES &&
    profile.positiveReviewCount >= SELLER_VERIFICATION_MIN_POSITIVE_REVIEWS &&
    profile.rating >= SELLER_VERIFICATION_MIN_AVERAGE_RATING &&
    activeDays >= SELLER_VERIFICATION_MIN_ACTIVE_DAYS
  );
}

function buildSellerProfiles(sellers = {}, catalogProducts = [], orders = []) {
  const sellerIds = new Set([
    ...Object.keys(sellers),
    ...catalogProducts.map((product) => product.sellerId).filter(Boolean),
  ]);

  return Array.from(sellerIds)
    .map((sellerId) => buildSellerProfile(sellerId, sellers[sellerId], catalogProducts, orders))
    .sort((lhs, rhs) => lhs.displayName.localeCompare(rhs.displayName));
}

function escapeHtml(text = "") {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalizeCustomOrderRequest(entry = {}) {
  const statusRaw = String(entry.status || "pending").trim().toLowerCase();
  const status = ["accepted", "declined"].includes(statusRaw) ? statusRaw : "pending";
  return {
    id: String(entry.id || ""),
    sellerId: String(entry.sellerId || ""),
    buyerName: String(entry.buyerName || ""),
    buyerEmail: String(entry.buyerEmail || "").trim().toLowerCase(),
    description: String(entry.description || ""),
    referenceImageURLs: Array.isArray(entry.referenceImageURLs)
      ? entry.referenceImageURLs.map((u) => String(u || "")).filter(Boolean)
      : [],
    createdAt: entry.createdAt || new Date().toISOString(),
    clientIp: entry.clientIp != null ? String(entry.clientIp) : null,
    status,
    statusUpdatedAt: entry.statusUpdatedAt || null,
  };
}

function loadCustomOrderRequestsFile() {
  const cached = getCachedDocument("customOrderRequests");
  if (cached !== undefined) {
    const arr = Array.isArray(cached) ? cached : [];
    return arr.map((row) => normalizeCustomOrderRequest(row));
  }
  try {
    const raw = JSON.parse(readFileSync(fileURLToPath(CUSTOM_ORDER_REQUESTS_PATH), "utf-8"));
    const arr = Array.isArray(raw) ? raw : [];
    setCachedDocument("customOrderRequests", arr);
    return arr.map((row) => normalizeCustomOrderRequest(row));
  } catch {
    setCachedDocument("customOrderRequests", []);
    return [];
  }
}

function saveCustomOrderRequestsFile(rows) {
  writeManagedJSON("customOrderRequests", Array.isArray(rows) ? rows : []);
}

function loadSellerInquiriesFile() {
  const cached = getCachedDocument("sellerInquiries");
  if (cached !== undefined) {
    const arr = Array.isArray(cached) ? cached : [];
    return arr.map((row) => normalizeInquiryThread(row));
  }
  try {
    const raw = JSON.parse(readFileSync(fileURLToPath(SELLER_INQUIRIES_PATH), "utf-8"));
    const arr = Array.isArray(raw) ? raw : [];
    setCachedDocument("sellerInquiries", arr);
    return arr.map((row) => normalizeInquiryThread(row));
  } catch {
    setCachedDocument("sellerInquiries", []);
    return [];
  }
}

function saveSellerInquiriesFile(rows) {
  writeManagedJSON("sellerInquiries", Array.isArray(rows) ? rows : []);
}

function getOrCreateInquiryThreadForBuyer(sellerId, auth, buyerName = null) {
  const normalizedSellerId = String(sellerId || "").trim();
  if (auth?.role !== "buyer" || !auth.buyerEmail || !normalizedSellerId) {
    return { ok: false, error: "Buyer session required" };
  }
  const threads = loadSellerInquiriesFile();
  const { threads: nextThreads, thread } = upsertInquiryThread(threads, {
    sellerId: normalizedSellerId,
    buyerEmail: auth.buyerEmail,
    buyerName,
  });
  if (thread && !findInquiryThread(threads, auth.buyerEmail, normalizedSellerId)) {
    saveSellerInquiriesFile(nextThreads);
  }
  return { ok: true, thread: thread || findInquiryThread(nextThreads, auth.buyerEmail, normalizedSellerId) };
}

function isAllowedCustomOrderReference(ref, sellerId) {
  const trimmedSellerId = String(sellerId || "").trim();
  const t = String(ref || "").trim();
  if (!t) return false;
  const expectedPrefix = `/media/custom-order-ref/${trimmedSellerId}/`;
  if (t.startsWith("/media/")) {
    return t.startsWith(expectedPrefix);
  }
  try {
    const u = new URL(t);
    return u.pathname.startsWith(expectedPrefix);
  } catch {
    return false;
  }
}

function sellerMembershipResponse(sellerId, seller) {
  const membership = effectiveSellerMembershipStatus(seller);
  return {
    sellerId,
    requiresSubscription: membership.membershipStatus !== "complimentary",
    hasActiveSubscription: membership.hasActiveSubscription,
    hasPaidSubscription: membership.membership.hasActiveSubscription,
    productId: membership.membership.productId,
    source: membership.membership.source,
    expiresAt: membership.membership.expiresAt,
    lastSyncedAt: membership.membership.lastSyncedAt,
    membershipStatus: membership.membershipStatus,
    isFoundingCreator: membership.founding.isFoundingCreator,
    foundingCreatorAccessStartsAt: membership.founding.foundingCreatorAccessStartsAt,
    foundingCreatorAccessEndsAt: membership.founding.foundingCreatorAccessEndsAt,
    creatorBadge: membership.founding.creatorBadge,
  };
}

async function applyStripeSubscriptionToSeller(sellerId, subscription) {
  if (!sellerId || !subscription) return;
  const sellers = loadSellersFile();
  const seller = sellers[sellerId];
  if (!seller) return;
  const active = subscription.status === "active" || subscription.status === "trialing";
  const expiresAt = subscription.current_period_end
    ? new Date(subscription.current_period_end * 1000).toISOString()
    : null;
  const customerId =
    typeof subscription.customer === "string"
      ? subscription.customer
      : subscription.customer?.id || null;
  seller.membership = normalizeMembership({
    ...seller.membership,
    hasActiveSubscription: active,
    expiresAt,
    lastSyncedAt: new Date().toISOString(),
    source: "stripe",
    productId: SELLER_SUBSCRIPTION_PRODUCT_ID,
    stripeSubscriptionId: subscription.id,
    stripeCustomerId: customerId,
    transactionId: subscription.latest_invoice || seller.membership?.transactionId || null,
  });
  sellers[sellerId] = seller;
  saveSellersFile(sellers);
}

function loadOrdersFile() {
  const cached = getCachedDocument("orders");
  if (cached !== undefined) {
    return Array.isArray(cached) ? cached : [];
  }
  try {
    const parsed = JSON.parse(readFileSync(ORDERS_PATH, "utf-8"));
    const arr = Array.isArray(parsed) ? parsed : [];
    setCachedDocument("orders", arr);
    return arr;
  } catch {
    setCachedDocument("orders", []);
    return [];
  }
}

function loadExchangeRequestsFile() {
  const cached = getCachedDocument("exchangeRequests");
  if (cached !== undefined) {
    return normalizeExchangeRequests(cached);
  }
  try {
    const parsed = normalizeExchangeRequests(JSON.parse(readFileSync(EXCHANGE_REQUESTS_PATH, "utf-8")));
    setCachedDocument("exchangeRequests", parsed);
    return parsed;
  } catch {
    setCachedDocument("exchangeRequests", []);
    return [];
  }
}

function normalizeBuyerRecord(record = {}, email = "") {
  const normalizedEmail = String(email || record.email || "").trim().toLowerCase();
  return {
    email: normalizedEmail,
    fullName: String(record.fullName || "").trim(),
    passwordHash: String(record.passwordHash || "").trim(),
    emailVerified: record.emailVerified === true,
    emailVerifiedAt: record.emailVerifiedAt || null,
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || new Date().toISOString(),
  };
}

function isValidBuyerEmail(email = "") {
  const normalized = String(email || "").trim().toLowerCase();
  return /^\S+@\S+\.\S+$/.test(normalized);
}

function hashBuyerPassword(password = "") {
  return crypto.createHash("sha256").update(String(password)).digest("hex");
}

function hashSellerPassword(password = "") {
  return crypto.createHash("sha256").update(String(password)).digest("hex");
}

function transactionalEmailConfigured() {
  return Boolean(resend || smtpConfigured);
}

function emailFromUsesResendSandbox() {
  const raw = String(EMAIL_FROM || "").trim().toLowerCase();
  const match = raw.match(/<([^>]+)>/);
  const address = (match?.[1] || raw).trim();
  return address.endsWith("@resend.dev");
}

let resendProviderStatusCache = { checkedAt: 0, valid: null, detail: "" };

async function getResendProviderStatus() {
  if (!resend) {
    return { valid: null, detail: "not_configured" };
  }

  const now = Date.now();
  if (now - resendProviderStatusCache.checkedAt < 5 * 60 * 1000 && resendProviderStatusCache.valid !== null) {
    return resendProviderStatusCache;
  }

  try {
    const { error } = await resend.domains.list();
    if (error) {
      resendProviderStatusCache = {
        checkedAt: now,
        valid: false,
        detail: error.message || error.name || "Resend API error",
      };
    } else {
      resendProviderStatusCache = { checkedAt: now, valid: true, detail: "ok" };
    }
  } catch (err) {
    resendProviderStatusCache = {
      checkedAt: now,
      valid: false,
      detail: String(err?.message || err || "Resend API error"),
    };
  }

  return resendProviderStatusCache;
}

function emailRecipientsList(to) {
  const entries = Array.isArray(to) ? to : [to];
  return entries
    .map((entry) => String(entry || "").trim().toLowerCase())
    .filter(Boolean);
}

async function sendTransactionalEmail({ to, subject, html }) {
  const recipients = emailRecipientsList(to);
  if (!recipients.length) {
    throw new Error("No email recipient provided");
  }

  if (resend) {
    const resendResult = await resend.emails.send({
      from: EMAIL_FROM,
      to: recipients,
      subject,
      html,
    });
    if (resendResult?.error) {
      const resendMessage =
        resendResult.error?.message ||
        resendResult.error?.name ||
        "Resend email send failed";
      throw new Error(resendMessage);
    }
    if (resendResult?.data?.id) {
      console.log(`Resend message accepted → ${resendResult.data.id}`);
    }
    return recipients;
  }

  if (smtpConfigured) {
    if (!smtpTransporter) {
      smtpTransporter = nodemailer.createTransport({
        host: SMTP_HOST,
        port: SMTP_PORT,
        secure: SMTP_SECURE,
        auth: {
          user: SMTP_USER,
          pass: SMTP_PASS,
        },
      });
    }

    const smtpInfo = await smtpTransporter.sendMail({
      from: EMAIL_FROM,
      to: recipients.join(", "),
      subject,
      html,
    });
    if (process.env.NODE_ENV !== "production") {
      try {
        const previewURL = nodemailer.getTestMessageUrl?.(smtpInfo);
        if (previewURL) {
          console.log(`SMTP preview message URL → ${previewURL}`);
        }
      } catch {
        // ignore preview URL generation failures
      }
    }
    return recipients;
  }

  throw new Error(
    "No transactional email provider configured. Set RESEND_API_KEY or SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS."
  );
}

async function sendBuyerAccountUpdateConfirmation({
  previousEmail,
  updatedEmail,
  emailChanged,
  passwordChanged,
}) {
  const targets = Array.from(
    new Set(
      [String(previousEmail || "").trim().toLowerCase(), String(updatedEmail || "").trim().toLowerCase()].filter(
        Boolean
      )
    )
  );
  if (!targets.length) {
    return [];
  }

  const changeSummary = [
    emailChanged ? "Email was updated." : null,
    passwordChanged ? "Password was updated." : null,
  ]
    .filter(Boolean)
    .join(" ");

  await sendTransactionalEmail({
    to: targets,
    subject: "Your TenBelow account details were updated",
    html: `<h2>Account update confirmed</h2><p>${changeSummary || "Your account details were updated."}</p><p>Updated email on file: <strong>${updatedEmail}</strong></p><p>If this was not you, contact support@tenbelow.com right away.</p>`,
  });

  return targets;
}

function loadBuyersFile() {
  let raw = getCachedDocument("buyers");
  if (raw === undefined) {
    try {
      raw = JSON.parse(readFileSync(BUYERS_PATH, "utf-8"));
      setCachedDocument("buyers", raw);
    } catch {
      raw = {};
      setCachedDocument("buyers", raw);
    }
  }
  const src = raw && typeof raw === "object" ? raw : {};
  const buyers = Object.fromEntries(
    Object.entries(src).map(([email, record]) => [email, normalizeBuyerRecord(record, email)])
  );
  schedulePhase1Compare("buyers-read");
  return buyers;
}

function saveBuyersFile(buyers) {
  const normalized = Object.fromEntries(
    Object.entries(buyers || {}).map(([email, record]) => [email, normalizeBuyerRecord(record, email)])
  );
  writeManagedJSON("buyers", normalized);
}

function saveOrdersFile(orders) {
  writeManagedJSON("orders", orders);
}

function saveExchangeRequestsFile(exchangeRequests) {
  writeManagedJSON("exchangeRequests", normalizeExchangeRequests(exchangeRequests));
}

function exchangeConfigSnapshot() {
  return readConfigDocumentMerged();
}

function resolveOrderItem(order, orderItemId) {
  const normalizedOrderItemId = String(orderItemId || "").trim();
  for (const shipment of Array.isArray(order?.shipments) ? order.shipments : []) {
    const item = (Array.isArray(shipment.items) ? shipment.items : []).find(
      (candidate) => candidate.id === normalizedOrderItemId
    );
    if (item) {
      return { shipment, item };
    }
  }
  return null;
}

function buyerOwnsOrder(order, auth) {
  const buyerEmail = String(order?.buyerEmail || "").trim().toLowerCase();
  return auth?.role === "buyer" && buyerEmail && auth?.buyerEmail === buyerEmail;
}

function sellerCanViewExchange(request, auth) {
  const sellerId = String(request?.sellerUserId || "").replace(/^seller:/, "").trim();
  return auth?.role === "seller" && sellerId && auth?.sellerId === sellerId;
}

function exchangeRequestResponse(request, order = null) {
  return {
    exchangeRequest: request,
    orderId: request.orderId,
    orderItemId: request.orderItemId,
    orderItem: order ? resolveOrderItem(order, request.orderItemId)?.item || null : null,
  };
}

function buildAdminExchangeQueueRecord(request, orders) {
  const order = orders.find((candidate) => candidate.id === request.orderId) || null;
  const resolved = order ? resolveOrderItem(order, request.orderItemId) : null;
  const shipment = resolved?.shipment || null;
  const item = resolved?.item || null;
  return {
    ...request,
    orderNumber: request.orderId,
    buyer: order?.buyerEmail || request.buyerUserId || null,
    seller: shipment?.sellerName || request.sellerUserId || null,
    sellerId: shipment?.sellerId || request.sellerUserId?.replace(/^seller:/, "") || null,
    product: request.productTitle || item?.productName || null,
    submittedDate: request.buyerSubmittedAt || request.createdAt,
    eligibilityResult: {
      eligibleAtSubmission: request.eligibleAtSubmission,
      failureReason: request.eligibilityFailureReason,
    },
    needsAttention:
      request.status === "awaiting_buyer_proof" ||
      request.status === "awaiting_seller_response" ||
      request.status === "under_review",
  };
}

function groupOrderItemsIntoShipments(orderItems, sellers) {
  const bySeller = new Map();

  for (const item of orderItems) {
    const current = bySeller.get(item.sellerId) || [];
    current.push(item);
    bySeller.set(item.sellerId, current);
  }

  return Array.from(bySeller.entries()).map(([sellerId, items]) => {
    const seller = sellers[sellerId];
    const shipByDays = items.reduce((maxDays, item) => Math.max(maxDays, item.shipsInMaxDays || 4), 0);
    const shipByDate = new Date(Date.now() + shipByDays * 24 * 60 * 60 * 1000).toISOString();

    return {
      id: `SHP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
      sellerId,
      sellerName: seller?.businessName || sellerId,
      sellerHandle: null,
      status: "preparing",
      shipByDate,
      carrier: null,
      trackingNumber: null,
      shippedAt: null,
      deliveredAt: null,
      items: items.map((item) => ({
        id: `LI-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
        productId: item.id,
        productName: item.name,
        unitPriceCents: item.priceCents,
        quantity: item.quantity,
        thumbnailURL: item.thumbnailURL || null,
        productionPreviewURL: item.productionPreviewURL || null,
      })),
    };
  });
}

function deriveOrderStatus(shipments, current = "placed") {
  if (!shipments.length) return current;

  const normalized = shipments.map((shipment) => String(shipment?.status || "").trim().toLowerCase());
  if (normalized.every((status) => status === "cancelled")) return "cancelled";

  const active = shipments.filter((shipment) => String(shipment?.status || "").trim().toLowerCase() !== "cancelled");
  if (!active.length) return "cancelled";

  const deliveredCount = active.filter((shipment) => shipment.status === "delivered").length;
  const shippedCount = active.filter((shipment) => shipment.status === "shipped").length;
  const preparingCount = active.filter((shipment) => shipment.status === "preparing").length;

  if (deliveredCount === active.length) return "delivered";
  if (shippedCount + deliveredCount === active.length && shippedCount > 0) return "shipped";
  if (shippedCount > 0 && preparingCount > 0) return "partiallyShipped";
  if (preparingCount > 0) return "processing";
  return current;
}

function hydrateOrderRecord(order = {}) {
  const support = normalizeOrderSupportFields(order);
  return {
    ...order,
    supportRequests: support.supportRequests,
    orderMessages: support.orderMessages,
  };
}

function loadHydratedOrders() {
  return loadOrdersFile().map((order) => hydrateOrderRecord(order));
}

function findOrderForParticipant(orderId, auth) {
  const orders = loadHydratedOrders();
  const order = orders.find((entry) => entry.id === orderId);
  if (!order) return null;
  if (auth?.role === "buyer" && buyerOwnsOrder(order, auth)) return order;
  if (auth?.role === "seller" && sellerCanAccessOrder(order, auth.sellerId)) return order;
  return null;
}

function saveHydratedOrder(updatedOrder) {
  const orders = loadOrdersFile();
  const orderIndex = orders.findIndex((entry) => entry.id === updatedOrder.id);
  const hydrated = hydrateOrderRecord(updatedOrder);
  if (orderIndex < 0) {
    orders.unshift(hydrated);
  } else {
    orders[orderIndex] = hydrated;
  }
  saveOrdersFile(orders);
  return hydrated;
}

function respondWithParticipantOrder(res, order, auth) {
  if (auth?.role === "seller") {
    return res.json({ order: sellerScopedOrder(order, auth.sellerId) });
  }
  return res.json({ order });
}

function sellerCanAccessOrder(order, sellerId) {
  return order.shipments.some((shipment) => String(shipment?.sellerId || "").trim() === String(sellerId || "").trim());
}

function sellerScopedOrder(order, sellerId) {
  const normalizedSellerId = String(sellerId || "").trim();
  const sellerShipments = (Array.isArray(order?.shipments) ? order.shipments : []).filter(
    (shipment) => String(shipment?.sellerId || "").trim() === normalizedSellerId
  );
  const sellerTotalCents = sellerShipments.reduce(
    (sum, shipment) =>
      sum +
      (Array.isArray(shipment.items) ? shipment.items : []).reduce(
        (itemSum, item) => itemSum + Math.max(1, asFiniteNumber(item.quantity, 1)) * Math.max(0, asFiniteNumber(item.unitPriceCents, 0)),
        0
      ),
    0
  );

  return {
    ...order,
    status: deriveOrderStatus(sellerShipments, order?.status || "placed"),
    totalCents: sellerTotalCents,
    shipments: sellerShipments,
  };
}

function upsertPaidOrder({ orderId, buyerEmail, shipping, totalCents, currency = "USD", orderItems, sellers }) {
  const orders = loadOrdersFile();
  const existingIndex = orders.findIndex((order) => order.id === orderId);
  const existingOrder = existingIndex >= 0 ? orders[existingIndex] : null;
  const shipments = existingOrder?.shipments?.length
    ? existingOrder.shipments
    : groupOrderItemsIntoShipments(orderItems, sellers);

  const nextOrder = hydrateOrderRecord({
    id: orderId,
    createdAt: existingOrder?.createdAt || new Date().toISOString(),
    status: deriveOrderStatus(shipments, "placed"),
    buyerEmail: buyerEmail || existingOrder?.buyerEmail || null,
    shipToCity: shipping?.city || existingOrder?.shipToCity || null,
    shipToState: shipping?.state || existingOrder?.shipToState || null,
    currency,
    totalCents,
    shipments,
    supportRequests: existingOrder?.supportRequests || [],
    orderMessages: existingOrder?.orderMessages || [],
  });

  if (existingIndex >= 0) {
    orders[existingIndex] = nextOrder;
  } else {
    orders.unshift(nextOrder);
  }

  saveOrdersFile(orders);
  return nextOrder;
}

// ---------------------------------------------------------------------------
// Stripe webhook (MUST be before express.json())
// ---------------------------------------------------------------------------

app.post("/webhook", express.raw({ type: "application/json" }), async (req, res) => {
  const sig = req.headers["stripe-signature"];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error("Webhook signature verification failed:", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === "payment_intent.succeeded") {
    if (processedWebhookEventIds.has(event.id)) {
      return res.json({ received: true, duplicate: true });
    }
    const pi = event.data.object;
    const meta = pi.metadata;
    const orderId = meta.orderId || crypto.randomUUID();

    try {
      const orderItems = JSON.parse(meta.orderItems || "[]");
      const sellerTotals = JSON.parse(meta.sellerTotals || "{}");
      const shippingTotals = JSON.parse(meta.shippingTotals || "{}");
      const shippingAddress = JSON.parse(meta.shippingAddress || meta.shipping || "{}");
      const sellers = await fetchSellers();
      upsertPaidOrder({
        orderId,
        buyerEmail: meta.buyerEmail,
        shipping: shippingAddress,
        totalCents: pi.amount_received || pi.amount,
        currency: (pi.currency || "usd").toUpperCase(),
        orderItems,
        sellers,
      });

      for (const [sellerId, amountCents] of Object.entries(sellerTotals)) {
        const seller = sellers[sellerId];
        if (!seller?.stripeAccountId) continue;
        const productCents = Math.max(0, Math.floor(Number(amountCents) || 0));
        const shippingCents = Math.max(0, Math.floor(Number(shippingTotals[sellerId]) || 0));
        const platformFee = Math.round(productCents * PLATFORM_PRODUCT_COMMISSION_RATE);
        const transferAmount = productCents - platformFee + shippingCents;
        if (transferAmount <= 0) continue;
        await stripe.transfers.create({
          amount: transferAmount,
          currency: "usd",
          destination: seller.stripeAccountId,
          transfer_group: orderId,
        }, {
          idempotencyKey: `transfer_${pi.id || orderId}_${sellerId}`,
        });
      }

      if (meta.buyerEmail) {
        try {
          await sendTransactionalEmail({
            to: meta.buyerEmail,
            subject: `TenBelow Order Confirmed — ${orderId}`,
            html: `<h2>Thanks for your order!</h2><p>Order <strong>${orderId}</strong></p><p>We'll email tracking when items ship.</p>`,
          });
        } catch (emailErr) {
          console.error("Failed to send order confirmation email:", emailErr?.message || emailErr);
        }
      }

      try {
        await notifyPaymentSucceeded({
          orderId,
          buyerEmail: meta.buyerEmail,
          sellerTotals,
          orderItems,
        });
      } catch (pushErr) {
        console.warn("Order push notification error:", pushErr?.message || pushErr);
      }

      processedWebhookEventIds.add(event.id);
      persistWebhookDedupeIds();
    } catch (err) {
      console.error("Webhook processing error:", err);
    }
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    if (session.mode === "subscription" && session.metadata?.sellerId) {
      const subId = session.subscription;
      if (subId) {
        try {
          const sub = await stripe.subscriptions.retrieve(subId);
          applyStripeSubscriptionToSeller(session.metadata.sellerId, sub);
        } catch (err) {
          console.error("checkout.session.completed subscription error:", err?.message || err);
        }
      }
    }
  } else if (
    event.type === "customer.subscription.updated" ||
    event.type === "customer.subscription.deleted"
  ) {
    const sub = event.data.object;
    const sellerId = sub.metadata?.sellerId;
    if (sellerId) {
      try {
        applyStripeSubscriptionToSeller(sellerId, sub);
      } catch (err) {
        console.error("subscription webhook error:", err?.message || err);
      }
    }
  }

  res.json({ received: true });
});

// ---------------------------------------------------------------------------
// JSON body parser (after webhook)
// ---------------------------------------------------------------------------

app.use(express.json());
app.set("trust proxy", 1);
app.use((req, res, next) => {
  const requestId = crypto.randomUUID();
  req.requestId = requestId;
  res.setHeader("X-Request-Id", requestId);
  next();
});
app.use((req, res, next) => {
  if (req.path === "/health" || req.path === "/ready") {
    return next();
  }
  const started = performance.now();
  res.on("finish", () => {
    const durationMs = Math.max(0, Math.round(performance.now() - started));
    console.log(
      JSON.stringify({
        msg: "http_request",
        requestId: req.requestId,
        method: req.method,
        path: req.path,
        status: res.statusCode,
        durationMs,
        ip: clientIp(req),
      })
    );
  });
  next();
});
app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);
    if (ALLOWED_CORS_ORIGINS.includes(origin)) return callback(null, true);
    auditLog({ action: "cors_origin_rejected", origin });
    return callback(new Error("Not allowed by CORS"));
  },
  credentials: true,
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization", "X-TenBelow-App-Key", "X-Admin-Key", "X-Request-Id"],
  maxAge: 60 * 60,
}));
app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.setHeader("X-DNS-Prefetch-Control", "off");
  if (req.path.startsWith("/admin")) {
    setAdminSecurityHeaders(res);
  }
  if (IS_PRODUCTION) {
    res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload");
  }
  if (req.path.startsWith("/admin") || req.path.startsWith("/auth")) {
    res.setHeader("Cache-Control", "no-store");
  }
  next();
});
app.use((err, req, res, next) => {
  if (err && err.message === "Not allowed by CORS") {
    return res.status(403).json({ error: "Origin not allowed" });
  }
  return next(err);
});
app.use(
  "/media",
  mediaReadLimiter,
  safeMediaServingMiddleware(),
  express.static(MEDIA_DIRECTORY_PATH, {
    index: false,
    fallthrough: false,
    setHeaders(res, filePath) {
      const extension = String(filePath || "").split(".").pop() || "";
      if (!isServableMediaExtension(extension)) {
        res.statusCode = 404;
        return;
      }
      const contentType = safeContentTypeForExtension(extension);
      if (contentType) {
        res.setHeader("Content-Type", contentType);
      }
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("Content-Disposition", "inline");
    },
  })
);
app.use(express.static(PUBLIC_ASSETS_PATH, {
  index: false,
  maxAge: IS_PRODUCTION ? "1h" : 0,
}));
app.use("/admin/assets", (req, res, next) => {
  res.setHeader("Cache-Control", "no-store, max-age=0");
  next();
}, express.static(ADMIN_ASSETS_PATH));

app.get("/", (req, res) => {
  res.setHeader("Cache-Control", IS_PRODUCTION ? "public, max-age=300" : "no-store, max-age=0");
  res.sendFile(PUBLIC_INDEX_HTML_PATH);
});

app.get("/admin/review", (req, res) => {
  ensureLocalAdminSession(req, res);
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.sendFile(ADMIN_REVIEW_HTML_PATH);
});

app.post("/auth/buyer-account", authLimiter, requireAppClient, async (req, res) => {
  try {
    const email = String(req.body?.email || "").trim().toLowerCase();
    const fullName = String(req.body?.fullName || "").trim();
    if (!email || !fullName) {
      return res.status(400).json({ error: "buyer email and fullName are required" });
    }
    if (!isValidBuyerEmail(email)) {
      return res.status(400).json({ error: "Enter a valid email address" });
    }

    const buyers = loadBuyersFile();
    const existing = buyers[email];
    const password = String(req.body?.password || "");
    const passwordHash = password ? hashBuyerPassword(password) : String(existing?.passwordHash || "");
    buyers[email] = normalizeBuyerRecord(
      {
        ...existing,
        email,
        fullName,
        passwordHash,
        emailVerified: existing?.emailVerified === true,
        emailVerifiedAt: existing?.emailVerifiedAt || null,
        createdAt: existing?.createdAt || new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
      email
    );
    saveBuyersFile(buyers);
    let verification = null;
    if (!buyers[email].emailVerified) {
      const challenge = createEmailOtpChallenge({
        req,
        purpose: "buyer_email_verification",
        email,
      });
      await sendEmailOtp({
        to: email,
        code: challenge.code,
        expiresAt: challenge.expiresAt,
        title: "Verify your TenBelow email",
        intro: "Enter this one-time code in TenBelow to verify your buyer account email.",
        warning: "If you did not create a TenBelow buyer account, you can ignore this email.",
      });
      recordSecurityAudit(req, { action: "buyer_email_verification_code_sent", email: maskedEmail(email) });
      verification = {
        required: true,
        challengeId: challenge.challengeId,
        deliveryTarget: maskedEmail(email),
        expiresInSeconds: Math.floor(EMAIL_OTP_TTL_MS / 1000),
      };
    }
    res.json({ ok: true, email, emailVerified: buyers[email].emailVerified, verification });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/buyer-email-verification/request", authLimiter, requireAppClient, async (req, res) => {
  try {
    const email = String(req.body?.email || "").trim().toLowerCase();
    if (!isValidBuyerEmail(email)) {
      return res.status(400).json({ error: "Enter a valid email address" });
    }
    const buyers = loadBuyersFile();
    const buyer = buyers[email];
    if (!buyer) {
      return res.status(404).json({ error: "Buyer account not found" });
    }
    if (buyer.emailVerified === true) {
      return res.json({ ok: true, email, emailVerified: true });
    }

    const challenge = createEmailOtpChallenge({
      req,
      purpose: "buyer_email_verification",
      email,
    });
    await sendEmailOtp({
      to: email,
      code: challenge.code,
      expiresAt: challenge.expiresAt,
      title: "Verify your TenBelow email",
      intro: "Enter this one-time code in TenBelow to verify your buyer account email.",
      warning: "If you did not request this code, reset your password and contact support.",
    });
    recordSecurityAudit(req, { action: "buyer_email_verification_code_sent", email: maskedEmail(email) });
    res.json({
      ok: true,
      email,
      emailVerified: false,
      challengeId: challenge.challengeId,
      deliveryTarget: maskedEmail(email),
      expiresInSeconds: Math.floor(EMAIL_OTP_TTL_MS / 1000),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/buyer-email-verification/verify", authLimiter, requireAppClient, (req, res) => {
  try {
    const email = String(req.body?.email || "").trim().toLowerCase();
    const challengeId = String(req.body?.challengeId || "").trim();
    const code = String(req.body?.code || "").trim();
    if (!isValidBuyerEmail(email) || !challengeId || !code) {
      return res.status(400).json({ error: "Email, challenge, and code are required" });
    }

    const result = verifyEmailOtpChallenge({
      challengeId,
      code,
      purpose: "buyer_email_verification",
      email,
    });
    if (!result.ok) {
      recordSecurityAudit(req, {
        action: "buyer_email_verification_failed",
        reason: result.reason,
        email: maskedEmail(email),
      });
      return res.status(401).json({ error: "Invalid or expired verification code" });
    }

    const buyers = loadBuyersFile();
    const buyer = buyers[email];
    if (!buyer) {
      return res.status(404).json({ error: "Buyer account not found" });
    }
    buyers[email] = normalizeBuyerRecord(
      {
        ...buyer,
        emailVerified: true,
        emailVerifiedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
      email
    );
    saveBuyersFile(buyers);

    const token = issueUserSessionToken({
      role: "buyer",
      buyerEmail: email,
    });
    auditLog(auditContext(req, { action: "buyer_email_verified", email: maskedEmail(email) }));
    res.json({
      ok: true,
      email,
      emailVerified: true,
      token,
      role: "buyer",
      buyerEmail: email,
      fullName: buyers[email].fullName || "",
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/buyer-session", authLimiter, requireAppClient, (req, res) => {
  try {
    const email = String(req.body?.email || "").trim().toLowerCase();
    if (!email) {
      return res.status(400).json({ error: "buyer email is required" });
    }

    const buyers = loadBuyersFile();
    const buyer = buyers[email];
    if (!buyer) {
      return res.status(404).json({ error: "Buyer account not found" });
    }
    if (buyer.emailVerified !== true) {
      return res.status(403).json({
        error: "Buyer email verification required",
        code: "buyer_email_verification_required",
        emailVerified: false,
      });
    }

    const token = issueUserSessionToken({
      role: "buyer",
      buyerEmail: email,
    });

    res.json({
      token,
      role: "buyer",
      buyerEmail: email,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/guest-checkout-session", authLimiter, requireAppClient, (req, res) => {
  try {
    const email = String(req.body?.email || "").trim().toLowerCase();
    const fullName = String(req.body?.fullName || "").trim();
    if (!email || !fullName) {
      return res.status(400).json({ error: "buyer email and fullName are required" });
    }
    if (!isValidBuyerEmail(email)) {
      return res.status(400).json({ error: "Enter a valid email address" });
    }

    const buyers = loadBuyersFile();
    const existing = buyers[email];
    if (existing?.passwordHash && existing.emailVerified === true) {
      return res.status(403).json({
        code: "buyer_account_exists",
        error: "An account already exists for this email. Sign in to checkout.",
      });
    }

    buyers[email] = normalizeBuyerRecord(
      {
        ...existing,
        email,
        fullName,
        emailVerified: true,
        emailVerifiedAt: existing?.emailVerifiedAt || new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
      email
    );
    saveBuyersFile(buyers);

    const token = issueUserSessionToken({
      role: "buyer",
      buyerEmail: email,
    });

    recordSecurityAudit(req, {
      action: "guest_checkout_session_issued",
      email: maskedEmail(email),
    });

    res.json({
      token,
      role: "buyer",
      buyerEmail: email,
      checkoutMode: "guest",
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/buyer-login", authLimiter, requireAppClient, (req, res) => {
  try {
    const email = String(req.body?.email || "").trim().toLowerCase();
    const password = String(req.body?.password || "");
    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required" });
    }
    if (!isValidBuyerEmail(email)) {
      return res.status(400).json({ error: "Enter a valid email address" });
    }

    const buyers = loadBuyersFile();
    const buyer = buyers[email];
    if (!buyer) {
      return res.status(404).json({ error: "Buyer account not found" });
    }
    if (buyer.emailVerified !== true) {
      return res.status(403).json({
        error: "Buyer email verification required",
        code: "buyer_email_verification_required",
        emailVerified: false,
      });
    }

    const passwordHash = hashBuyerPassword(password);
    if (buyer.passwordHash && buyer.passwordHash !== passwordHash) {
      return res.status(401).json({ error: "Incorrect password" });
    }

    if (!buyer.passwordHash) {
      buyers[email] = normalizeBuyerRecord(
        {
          ...buyer,
          passwordHash,
          updatedAt: new Date().toISOString(),
        },
        email
      );
      saveBuyersFile(buyers);
    }

    const signedInBuyer = buyers[email];
    const token = issueUserSessionToken({
      role: "buyer",
      buyerEmail: email,
    });

    res.json({
      token,
      role: "buyer",
      buyerEmail: email,
      fullName: signedInBuyer.fullName || "",
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post(
  "/auth/buyer-account-update",
  authLimiter,
  requireAppClient,
  requireAuthenticatedBuyer,
  async (req, res) => {
    try {
      const currentEmail = String(req.auth?.buyerEmail || "").trim().toLowerCase();
      if (!currentEmail) {
        return res.status(401).json({ error: "Authenticated buyer session required" });
      }

      const requestedEmail = String(req.body?.newEmail || "").trim().toLowerCase();
      const requestedPassword = String(req.body?.newPassword || "");
      const emailChanged = requestedEmail && requestedEmail !== currentEmail;
      const passwordChanged = requestedPassword.length > 0;

      if (!emailChanged && !passwordChanged) {
        return res.status(400).json({ error: "Provide a new email or password to update" });
      }

      if (emailChanged && !isValidBuyerEmail(requestedEmail)) {
        return res.status(400).json({ error: "Enter a valid email address" });
      }

      if (passwordChanged && requestedPassword.length < 8) {
        return res.status(400).json({ error: "Password must be at least 8 characters" });
      }

      const buyers = loadBuyersFile();
      const currentBuyer = buyers[currentEmail];
      if (!currentBuyer) {
        return res.status(404).json({ error: "Buyer account not found" });
      }

      const nextEmail = emailChanged ? requestedEmail : currentEmail;
      if (emailChanged && buyers[nextEmail]) {
        return res.status(409).json({ error: "That email is already in use" });
      }

      if (!transactionalEmailConfigured()) {
        return res.status(503).json({
          error:
            "Account updates require email confirmation, but no email provider is configured. Set RESEND_API_KEY or SMTP settings on the backend.",
        });
      }

      const updatedBuyer = normalizeBuyerRecord(
        {
          ...currentBuyer,
          email: nextEmail,
          passwordHash: passwordChanged
            ? hashBuyerPassword(requestedPassword)
            : String(currentBuyer.passwordHash || ""),
          emailVerified: emailChanged ? false : currentBuyer.emailVerified === true,
          emailVerifiedAt: emailChanged ? null : currentBuyer.emailVerifiedAt || null,
          updatedAt: new Date().toISOString(),
        },
        nextEmail
      );

      if (emailChanged) {
        delete buyers[currentEmail];
      }
      buyers[nextEmail] = updatedBuyer;
      saveBuyersFile(buyers);

      if (emailChanged) {
        const orders = loadOrdersFile();
        let ordersUpdated = false;
        for (const order of orders) {
          const orderBuyerEmail = String(order?.buyerEmail || "").trim().toLowerCase();
          if (orderBuyerEmail === currentEmail) {
            order.buyerEmail = nextEmail;
            ordersUpdated = true;
          }
        }
        if (ordersUpdated) {
          saveOrdersFile(orders);
        }

        const exchangeRequests = loadExchangeRequestsFile();
        let exchangeRequestsUpdated = false;
        const previousBuyerUserId = exchangeBuyerUserId(currentEmail);
        const nextBuyerUserId = exchangeBuyerUserId(nextEmail);
        for (const request of exchangeRequests) {
          if (request.buyerUserId === previousBuyerUserId) {
            request.buyerUserId = nextBuyerUserId;
            exchangeRequestsUpdated = true;
          }
        }
        if (exchangeRequestsUpdated) {
          saveExchangeRequestsFile(exchangeRequests);
        }
      }

      const confirmationTargets = await sendBuyerAccountUpdateConfirmation({
        previousEmail: currentEmail,
        updatedEmail: nextEmail,
        emailChanged: Boolean(emailChanged),
        passwordChanged,
      });

      let verification = null;
      if (emailChanged) {
        const challenge = createEmailOtpChallenge({
          req,
          purpose: "buyer_email_verification",
          email: nextEmail,
        });
        await sendEmailOtp({
          to: nextEmail,
          code: challenge.code,
          expiresAt: challenge.expiresAt,
          title: "Verify your new TenBelow email",
          intro: "Enter this one-time code in TenBelow to verify your new buyer account email.",
          warning: "If you did not request this email change, reset your password and contact support.",
        });
        recordSecurityAudit(req, { action: "buyer_email_verification_code_sent", email: maskedEmail(nextEmail) });
        verification = {
          required: true,
          challengeId: challenge.challengeId,
          deliveryTarget: maskedEmail(nextEmail),
          expiresInSeconds: Math.floor(EMAIL_OTP_TTL_MS / 1000),
        };
      }

      const token = emailChanged
        ? ""
        : issueUserSessionToken({
            role: "buyer",
            buyerEmail: nextEmail,
          });

      res.json({
        ok: true,
        email: nextEmail,
        token,
        emailVerified: updatedBuyer.emailVerified === true,
        verification,
        emailChanged: Boolean(emailChanged),
        passwordChanged,
        confirmationTargets,
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  }
);

app.post("/auth/seller-session", authLimiter, requireAppClient, requireAuthenticatedSeller, (req, res) => {
  try {
    const sellerId = String(req.body?.sellerId || "").trim();
    const email = String(req.body?.email || "").trim().toLowerCase();
    if (!sellerId) {
      return res.status(400).json({ error: "sellerId is required" });
    }
    if (req.auth.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_session_refresh",
        expectedSellerId: sellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller session refresh denied" });
    }

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) {
      return res.status(404).json({ error: "Seller not found" });
    }

    if (seller.email && email && String(seller.email).trim().toLowerCase() !== email) {
      auditOwnershipMismatch(req, {
        scope: "seller_session_email_check",
        expectedSellerId: sellerId,
        expectedEmail: String(seller.email).trim().toLowerCase(),
        actualEmail: email,
      });
      return res.status(403).json({ error: "Seller email does not match this account" });
    }

    const token = issueUserSessionToken({
      role: "seller",
      sellerId,
      sellerEmail: email || String(seller.email || "").trim().toLowerCase(),
    });

    res.json({
      token,
      role: "seller",
      sellerId,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/seller-login", authLimiter, requireAppClient, (req, res) => {
  try {
    const identifier = String(req.body?.identifier || "").trim().toLowerCase();
    const password = String(req.body?.password || "");
    if (!identifier || !password) {
      return res.status(400).json({ error: "Seller ID/email and password are required" });
    }

    const sellers = loadSellersFile();
    const entry = Object.entries(sellers).find(([sellerId, seller]) =>
      sellerId.toLowerCase() === identifier ||
      String(seller.email || "").trim().toLowerCase() === identifier
    );
    if (!entry) {
      return res.status(404).json({ error: "Seller account not found" });
    }

    const [sellerId, seller] = entry;
    const passwordHash = hashSellerPassword(password);
    if (seller.passwordHash && seller.passwordHash !== passwordHash) {
      return res.status(401).json({ error: "Incorrect seller password" });
    }

    // Legacy seller accounts were created before password sign-in existed. The first successful
    // credential sign-in claims a password so future sign-ins are protected.
    if (!seller.passwordHash) {
      seller.passwordHash = passwordHash;
      sellers[sellerId] = seller;
      saveSellersFile(sellers);
    }

    const sellerEmail = String(seller.email || "").trim().toLowerCase();
    const token = issueUserSessionToken({
      role: "seller",
      sellerId,
      sellerEmail,
    });

    res.json({
      token,
      role: "seller",
      sellerId,
      sellerEmail,
      businessName: seller.businessName || seller.profile?.displayName || sellerId,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/seller-password-reset/request", authLimiter, requireAppClient, async (req, res) => {
  try {
    const identifier = String(req.body?.identifier || "").trim().toLowerCase();
    if (!identifier) {
      return res.status(400).json({ error: "Seller ID or email is required" });
    }

    const sellers = loadSellersFile();
    const entry = Object.entries(sellers).find(([sellerId, seller]) =>
      sellerId.toLowerCase() === identifier ||
      String(seller.email || "").trim().toLowerCase() === identifier
    );

    if (entry && transactionalEmailConfigured()) {
      const [sellerId, seller] = entry;
      const email = String(seller.email || "").trim().toLowerCase();
      if (email) {
        const challenge = createEmailOtpChallenge({
          req,
          purpose: "seller_password_reset",
          email,
          subjectId: sellerId,
        });
        await sendEmailOtp({
          to: email,
          code: challenge.code,
          expiresAt: challenge.expiresAt,
          title: "Reset your TenBelow seller password",
          intro: "Enter this one-time code in TenBelow to reset your seller password.",
          warning: "If you did not request this code, contact support and review your seller account.",
        });
        auditLog(auditContext(req, {
          action: "seller_password_reset_code_sent",
          sellerId,
          email: maskedEmail(email),
        }));
        return res.json({
          ok: true,
          challengeId: challenge.challengeId,
          deliveryTarget: maskedEmail(email),
          expiresInSeconds: Math.floor(EMAIL_OTP_TTL_MS / 1000),
        });
      }
    }

    if (entry && !transactionalEmailConfigured()) {
      return res.status(503).json({
        error: "Password resets require RESEND_API_KEY or SMTP settings on the backend.",
      });
    }

    // Do not reveal whether the seller exists.
    recordSecurityAudit(req, { action: "seller_password_reset_requested_unknown" });
    return res.json({
      ok: true,
      challengeId: "",
      deliveryTarget: "the seller email on file",
      expiresInSeconds: Math.floor(EMAIL_OTP_TTL_MS / 1000),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/auth/seller-password-reset/verify", authLimiter, requireAppClient, (req, res) => {
  try {
    const identifier = String(req.body?.identifier || "").trim().toLowerCase();
    const challengeId = String(req.body?.challengeId || "").trim();
    const code = String(req.body?.code || "").trim();
    const newPassword = String(req.body?.newPassword || "");
    if (!identifier || !challengeId || !code || newPassword.length < 8) {
      return res.status(400).json({ error: "Seller ID/email, code, and an 8+ character password are required" });
    }

    const sellers = loadSellersFile();
    const entry = Object.entries(sellers).find(([sellerId, seller]) =>
      sellerId.toLowerCase() === identifier ||
      String(seller.email || "").trim().toLowerCase() === identifier
    );
    if (!entry) {
      return res.status(401).json({ error: "Invalid or expired reset code" });
    }

    const [sellerId, seller] = entry;
    const email = String(seller.email || "").trim().toLowerCase();
    const result = verifyEmailOtpChallenge({
      challengeId,
      code,
      purpose: "seller_password_reset",
      email,
      subjectId: sellerId,
    });
    if (!result.ok) {
      recordSecurityAudit(req, {
        action: "seller_password_reset_failed",
        reason: result.reason,
        sellerId,
        email: maskedEmail(email),
      });
      return res.status(401).json({ error: "Invalid or expired reset code" });
    }

    seller.passwordHash = hashSellerPassword(newPassword);
    sellers[sellerId] = seller;
    saveSellersFile(sellers);
    auditLog(auditContext(req, {
      action: "seller_password_reset_success",
      sellerId,
      email: maskedEmail(email),
    }));
    res.json({ ok: true, sellerId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/session", (req, res) => {
  if (!ADMIN_API_KEY) {
    return res.status(503).json({ authenticated: false, error: "Admin auth is not configured" });
  }

  const authenticated = ensureLocalAdminSession(req, res);
  res.json({ authenticated });
});

app.post("/admin/login", adminLoginLimiter, (req, res) => {
  if (!ADMIN_API_KEY) {
    return res.status(503).json({ authenticated: false, error: "Admin auth is not configured" });
  }

  const key = String(req.body?.key || "").trim();
  if (!key || !constantTimeEquals(key, ADMIN_API_KEY)) {
    recordSecurityAudit(req, { action: "admin_login_failed" });
    return res.status(401).json({ authenticated: false, error: "Invalid admin key" });
  }

  const sessionToken = createAdminSessionToken();
  if (!sessionToken) {
    return res.status(503).json({ authenticated: false, error: "Admin session signing is not configured" });
  }

  setAdminSessionCookie(res, sessionToken);
  auditLog(auditContext(req, { action: "admin_login_success", method: "admin_key" }));
  return res.json({ authenticated: true });
});

app.post("/admin/logout", (req, res) => {
  const sessionToken = readCookieValue(req.headers.cookie, ADMIN_SESSION_COOKIE_NAME);
  destroyAdminSessionToken(sessionToken);
  clearAdminCookies(res);
  auditLog(auditContext(req, { action: "admin_logout" }));
  res.json({ authenticated: false });
});

app.get("/admin/audit-log", adminMutationLimiter, requireAdmin, (req, res) => {
  const limit = Math.max(1, Math.min(500, Number(req.query.limit) || 150));
  const entries = readAuditLogTail(limit);
  res.json({ entries });
});

function auditEntryMatchesExportQuery(entry, query = "") {
  const normalized = String(query || "").trim().toLowerCase();
  if (!normalized) return true;
  return [
    entry?.action,
    entry?.requestId,
    entry?.method,
    entry?.path,
    entry?.ip,
    entry?.sellerId,
    entry?.buyerEmail,
    entry?.email,
  ].some((value) => String(value || "").toLowerCase().includes(normalized));
}

function csvCell(value) {
  const raw = value == null ? "" : String(value);
  return `"${raw.replaceAll('"', '""')}"`;
}

function auditEntriesToCsv(entries) {
  const columns = ["ts", "action", "requestId", "method", "path", "ip", "sellerId", "email", "reason"];
  const rows = entries.map((entry) =>
    columns.map((column) => csvCell(entry?.[column])).join(",")
  );
  return [columns.join(","), ...rows].join("\n");
}

app.get("/admin/audit-log/export", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const format = String(req.query.format || "json").trim().toLowerCase();
    const limit = Math.max(1, Math.min(AUDIT_LOG_SCAN_MAX, Number(req.query.limit) || 1000));
    const query = String(req.query.q || "").trim();
    const entries = readAuditLogTail(limit, { maxCap: AUDIT_LOG_SCAN_MAX })
      .filter((entry) => auditEntryMatchesExportQuery(entry, query));

    auditLog(
      auditContext(req, {
        action: "admin_audit_exported",
        format,
        limit,
        query: query || null,
        exportedCount: entries.length,
      })
    );

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    if (format === "csv") {
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader("Content-Disposition", `attachment; filename="tenbelow-audit-${timestamp}.csv"`);
      return res.send(auditEntriesToCsv(entries));
    }

    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("Content-Disposition", `attachment; filename="tenbelow-audit-${timestamp}.json"`);
    return res.send(JSON.stringify({ exportedAt: new Date().toISOString(), entries }, null, 2));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.get("/admin/data-snapshots", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const key = String(req.query.key || "").trim();
    const limit = Math.max(1, Math.min(500, Number(req.query.limit) || 50));
    if (!key) {
      return res.status(400).json({
        error: "Snapshot key is required",
        allowedKeys: Object.keys(MANAGED_DATA_TARGETS),
      });
    }
    const snapshots = listDataSnapshots(key, limit);
    res.json({ key, snapshots, retention: SNAPSHOT_RETENTION_PER_KEY });
  } catch (err) {
    res.status(400).json({ error: err.message, allowedKeys: Object.keys(MANAGED_DATA_TARGETS) });
  }
});

app.post("/admin/data-snapshots/compare", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const key = String(req.body?.key || "").trim();
    const leftSnapshotId = String(req.body?.leftSnapshotId || "").trim();
    const rightSnapshotId = String(req.body?.rightSnapshotId || "").trim();
    if (!key || !leftSnapshotId || !rightSnapshotId) {
      return res.status(400).json({ error: "key, leftSnapshotId, and rightSnapshotId are required" });
    }

    const preview = buildSnapshotComparePreview(key, leftSnapshotId, rightSnapshotId);
    auditLog(
      auditContext(req, {
        action: "admin_snapshot_compare",
        key,
        leftSnapshotId,
        rightSnapshotId,
        changed: preview.diff.changed,
        diff: preview.diff,
      })
    );
    res.json({ ok: true, ...preview });
  } catch (err) {
    res.status(400).json({ error: err.message, allowedKeys: Object.keys(MANAGED_DATA_TARGETS) });
  }
});

app.post("/admin/data-snapshots/restore", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const key = String(req.body?.key || "").trim();
    const snapshotId = String(req.body?.snapshotId || "").trim();
    const dryRun = req.body?.dryRun === true;
    if (!key || !snapshotId) {
      return res.status(400).json({ error: "key and snapshotId are required" });
    }
    const preview = buildSnapshotRestorePreview(key, snapshotId);
    if (dryRun) {
      auditLog(
        auditContext(req, {
          action: "admin_snapshot_restore_dry_run",
          key,
          snapshotId,
          changed: preview.diff.changed,
          diff: preview.diff,
        })
      );
      return res.json({ ok: true, dryRun: true, ...preview });
    }

    restoreDataSnapshot(key, snapshotId);
    auditLog(
      auditContext(req, {
        action: "admin_snapshot_restore",
        key,
        snapshotId,
        changed: preview.diff.changed,
        diff: preview.diff,
      })
    );
    res.json({ ok: true, dryRun: false, ...preview });
  } catch (err) {
    res.status(400).json({ error: err.message, allowedKeys: Object.keys(MANAGED_DATA_TARGETS) });
  }
});

app.post("/admin/security-alert-test", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const severity = String(req.body?.severity || "medium").trim().toLowerCase();
    if (!["medium", "high"].includes(severity)) {
      return res.status(400).json({ error: "severity must be medium or high" });
    }

    const code = String(req.body?.code || `synthetic_${severity}_alert`).trim();
    const message = String(req.body?.message || "Synthetic admin-triggered security alert test.").trim();
    const count = Number(req.body?.count || 1);
    const threshold = Number(req.body?.threshold || 1);

    auditLog(
      auditContext(req, {
        action: "security_alert_test_triggered",
        severity,
        code,
        message,
      })
    );

    await dispatchSecurityAlert(
      {
        severity,
        code,
        message,
        count,
        threshold,
        windowMs: SECURITY_ALERT_WINDOW_MS,
        trigger: "admin_security_alert_test",
        recentWindow: {
          windowMs: SECURITY_ALERT_WINDOW_MS,
          authFailures: 0,
          ownershipMismatches: 0,
        },
      },
      { bypassCooldown: true }
    );

    res.json({ ok: true, severity, code, message });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/incident-history", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const legacyLimit = req.query.limit;
    const hasNewPagination =
      req.query.incidentsPage != null ||
      req.query.incidentsPageSize != null ||
      req.query.restoresPage != null ||
      req.query.restoresPageSize != null ||
      req.query.incidentsQ != null ||
      req.query.incidentsState != null ||
      req.query.restoresQ != null ||
      req.query.restoresAction != null ||
      req.query.scanLines != null;

    if (legacyLimit != null && !hasNewPagination) {
      const limit = Math.max(1, Math.min(200, Number(legacyLimit) || 50));
      const scanLines = Math.max(1000, Math.min(AUDIT_LOG_SCAN_MAX, limit * 10));
      const payload = buildIncidentHistory({
        scanLines,
        incidentsPage: 1,
        incidentsPageSize: limit,
        restoresPage: 1,
        restoresPageSize: limit,
      });
      return res.json(payload);
    }

    const incidentsPage = Math.max(1, Number(req.query.incidentsPage) || 1);
    const incidentsPageSize = Math.max(1, Math.min(100, Number(req.query.incidentsPageSize) || 20));
    const restoresPage = Math.max(1, Number(req.query.restoresPage) || 1);
    const restoresPageSize = Math.max(1, Math.min(100, Number(req.query.restoresPageSize) || 20));
    const incidentsQ = String(req.query.incidentsQ || "").trim();
    const incidentsState = String(req.query.incidentsState || "").trim();
    const restoresQ = String(req.query.restoresQ || "").trim();
    const restoresAction = String(req.query.restoresAction || "").trim();
    const scanLines = Math.max(
      1000,
      Math.min(AUDIT_LOG_SCAN_MAX, Number(req.query.scanLines) || AUDIT_LOG_SCAN_MAX)
    );

    res.json(
      buildIncidentHistory({
        scanLines,
        incidentsPage,
        incidentsPageSize,
        incidentsQ,
        incidentsState,
        restoresPage,
        restoresPageSize,
        restoresQ,
        restoresAction,
      })
    );
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/admin/incidents/acknowledge", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const incidentId = String(req.body?.incidentId || "").trim();
    const note = String(req.body?.note || "").trim();
    if (!incidentId) {
      return res.status(400).json({ error: "incidentId is required" });
    }
    auditLog(
      auditContext(req, {
        action: "security_incident_acknowledged",
        incidentId,
        note,
      })
    );
    res.json({ ok: true, incidentId, note });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/admin/incidents/state", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const incidentId = String(req.body?.incidentId || "").trim();
    const note = String(req.body?.note || "").trim();
    const state = String(req.body?.state || "").trim().toLowerCase();
    const actionMap = {
      acknowledged: "security_incident_acknowledged",
      resolved: "security_incident_resolved",
      closed: "security_incident_closed",
    };
    const action = actionMap[state];
    if (!incidentId) {
      return res.status(400).json({ error: "incidentId is required" });
    }
    if (!action) {
      return res.status(400).json({ error: "state must be acknowledged, resolved, or closed" });
    }

    auditLog(
      auditContext(req, {
        action,
        incidentId,
        note,
      })
    );
    res.json({ ok: true, incidentId, state, note });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/security-metrics", adminMutationLimiter, requireAdmin, (req, res) => {
  const limit = Math.max(1, Math.min(5000, Number(req.query.limit) || 2000));
  const entries = readAuditLogTail(limit, { maxCap: AUDIT_LOG_SCAN_MAX });
  const relevant = entries.filter((entry) => isSecurityRelevantAction(String(entry?.action || "")));

  const countsByAction = relevant.reduce((acc, entry) => {
    const action = String(entry?.action || "unknown");
    acc[action] = (acc[action] || 0) + 1;
    return acc;
  }, {});

  const countsByReason = relevant.reduce((acc, entry) => {
    const reason = String(entry?.reason || "unspecified");
    acc[reason] = (acc[reason] || 0) + 1;
    return acc;
  }, {});

  const countsByScope = relevant.reduce((acc, entry) => {
    const scope = String(entry?.scope || "unspecified");
    acc[scope] = (acc[scope] || 0) + 1;
    return acc;
  }, {});
  const alertSummary = buildSecurityAlerts(relevant);

  res.json({
    scannedEntries: entries.length,
    matchedSecurityEvents: relevant.length,
    countsByAction,
    countsByReason,
    countsByScope,
    latestEvents: relevant.slice(0, 50),
    alerts: alertSummary.alerts,
    recentWindow: alertSummary.recentWindow,
  });
});

app.get("/catalog", publicReadLimiter, async (req, res) => {
  try {
    const catalog = await fetchCatalog();
    const etag = process.env.CATALOG_URL
      ? weakEtagFromString(`${process.env.CATALOG_URL}:${catalog?.version ?? ""}:${catalog?.updatedAt ?? ""}`)
      : `"cat-${etagFromFileURL(PRODUCTS_PATH).slice(1, -1)}-${etagFromFileURL(PRODUCT_REVIEWS_PATH).slice(1, -1)}"`;
    const rev = `${catalog?.version ?? 0}:${catalog?.updatedAt ?? ""}`;
    return sendPublicJsonWithCache(req, res, catalog, {
      maxAgeSeconds: 30,
      etag,
      extraHeaders: { "X-Catalog-Revision": rev },
    });
  } catch (err) {
    console.error("catalog error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/config", publicReadLimiter, async (req, res) => {
  try {
    const config = await fetchConfig();
    const body = {
      ...config,
      minimumOrderCents: PLATFORM_MINIMUM_ORDER_CENTS,
      freeShippingThresholdCents: FREE_SHIPPING_THRESHOLD_CENTS,
    };
    const etag = process.env.CONFIG_URL
      ? weakEtagFromString(`${process.env.CONFIG_URL}:${JSON.stringify(body)}`)
      : etagFromFileURL(CONFIG_PATH);
    return sendPublicJsonWithCache(req, res, body, {
      maxAgeSeconds: 60,
      etag,
      extraHeaders: { "X-Config-Revision": String(body?.version ?? config?.version ?? "") },
    });
  } catch (err) {
    console.error("config error:", err);
    res.status(500).json({ error: err.message });
  }
});

function pushUserKeyForAuth(auth = {}) {
  if (auth.role === "seller" && auth.sellerId) {
    return `seller:${String(auth.sellerId).trim()}`;
  }
  if (auth.role === "buyer" && auth.buyerEmail) {
    return `buyer:${String(auth.buyerEmail).trim().toLowerCase()}`;
  }
  return null;
}

app.post("/register-push-device", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const { deviceToken } = req.body || {};
    if (!deviceToken) return res.status(400).json({ error: "deviceToken required" });
    const userKey = pushUserKeyForAuth(req.auth);
    if (!userKey) return res.status(401).json({ error: "Authenticated buyer or seller required" });
    registerPushDevice(userKey, deviceToken);
    res.json({ ok: true, userKey });
  } catch (e) {
    console.warn("register-push-device:", e.message);
    res.status(400).json({ error: e.message });
  }
});

app.delete("/register-push-device", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const { deviceToken } = req.body || {};
    if (!deviceToken) return res.status(400).json({ error: "deviceToken required" });
    const userKey = pushUserKeyForAuth(req.auth);
    if (!userKey) return res.status(401).json({ error: "Authenticated buyer or seller required" });
    const removed = unregisterPushDevice(userKey, deviceToken);
    res.json({ ok: true, removed });
  } catch (e) {
    console.warn("unregister-push-device:", e.message);
    res.status(400).json({ error: e.message });
  }
});

app.post("/push/test", requireAppClient, requireAuthenticatedUser, async (req, res) => {
  try {
    const title = "TenBelow test alert";
    const body = "Your iPhone push notifications are connected.";
    const result = await notifyOrderStatusChanged({
      buyerEmail: req.auth.role === "buyer" ? req.auth.buyerEmail : undefined,
      sellerId: req.auth.role === "seller" ? req.auth.sellerId : undefined,
      title,
      body,
    });
    res.json({ ok: true, result });
  } catch (e) {
    console.warn("push-test:", e.message);
    res.status(500).json({ error: e.message });
  }
});

// ---------------------------------------------------------------------------
// Create Payment Intent
// ---------------------------------------------------------------------------

app.post("/create-payment-intent", paymentLimiter, requireAppClient, requireAuthenticatedBuyer, async (req, res) => {
  try {
    const { email, shipping, items } = req.body;
    if (!email || !items?.length) return res.status(400).json({ error: "Missing email or items" });
    const normalizedEmail = String(email || "").trim().toLowerCase();
    const authenticatedBuyerEmail = String(req.auth.buyerEmail || "").trim().toLowerCase();
    if (!normalizedEmail || normalizedEmail !== authenticatedBuyerEmail) {
      auditOwnershipMismatch(req, {
        scope: "payment_intent_buyer_email",
        expectedBuyerEmail: normalizedEmail || null,
        actualBuyerEmail: authenticatedBuyerEmail || null,
      });
      return res.status(403).json({ error: "Checkout email must match the signed-in buyer account" });
    }

    const catalog = await fetchCatalog();
    const productMap = Object.fromEntries(
      catalog.products
        .filter((p) => p.isActive && p.isApproved)
        .map((p) => [p.id, p])
    );

    let subtotalCents = 0;
    const sellerTotals = {};
    const orderItems = [];

    for (const item of items) {
      const quantity = Number(item.quantity);
      if (!item.productId || !Number.isInteger(quantity) || quantity <= 0) {
        return res.status(400).json({
          code: "invalid_cart_item",
          error: "Your cart has an invalid item quantity. Please review your cart and try again.",
        });
      }

      const product = productMap[item.productId];
      if (!product) {
        return res.status(409).json({
          code: "product_unavailable",
          error: "One or more products in your cart are no longer available. Please review your cart and try again.",
          productId: item.productId,
        });
      }

      const lineCents = product.priceCents * quantity;
      subtotalCents += lineCents;
      sellerTotals[product.sellerId] = (sellerTotals[product.sellerId] || 0) + lineCents;
      orderItems.push({
        id: product.id,
        name: product.name,
        sellerId: product.sellerId,
        priceCents: product.priceCents,
        quantity,
        thumbnailURL: product.imageURLs?.[0] || null,
        productionPreviewURL: product.productionPreviewURL || null,
        shipsInMaxDays: product.shipsInMaxDays || 4,
      });
    }

    if (!orderItems.length) {
      return res.status(400).json({
        code: "empty_valid_cart",
        error: "Your cart is empty. Add an item before checking out.",
      });
    }

    const minimumOrderCents = PLATFORM_MINIMUM_ORDER_CENTS;
    if (subtotalCents < minimumOrderCents) {
      return res.status(400).json({
        code: "minimum_order_not_met",
        error: `Minimum order is $${(minimumOrderCents / 100).toFixed(2)}`,
        minimumOrderCents,
      });
    }

    const { shippingTotals, totalShippingCents } = computeShippingTotalsBySeller(orderItems);
    const totalCents = subtotalCents + totalShippingCents;
    const orderId = crypto.randomUUID();

    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalCents,
      currency: "usd",
      payment_method_types: ["card"],
      metadata: {
        orderId,
        buyerEmail: authenticatedBuyerEmail,
        subtotalCents: String(subtotalCents),
        shippingCents: String(totalShippingCents),
        orderItems: JSON.stringify(orderItems),
        sellerTotals: JSON.stringify(sellerTotals),
        shippingTotals: JSON.stringify(shippingTotals),
        shippingAddress: JSON.stringify({
          name: shipping?.name || null,
          line1: shipping?.line1 || null,
          line2: shipping?.line2 || null,
          city: shipping?.city || null,
          state: shipping?.state || null,
          postalCode: shipping?.postalCode || null,
          country: shipping?.country || null,
        }),
      },
    });

    auditLog(
      auditContext(req, {
        action: "payment_intent_created",
        orderId,
        itemCount: orderItems.length,
        subtotalCents,
        shippingCents: totalShippingCents,
        totalCents,
      })
    );

    res.json({ clientSecret: paymentIntent.client_secret, orderId, totalCents });
  } catch (err) {
    console.error("create-payment-intent error:", err);
    res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Seller Onboarding (Stripe Connect Express)
// ---------------------------------------------------------------------------

function loadSellersFile() {
  const cached = getCachedDocument("sellers");
  if (cached !== undefined) {
    try {
      const sellers = normalizeSellerMap(cached);
      schedulePhase1Compare("sellers-read");
      return sellers;
    } catch {
      return {};
    }
  }
  try {
    const parsed = JSON.parse(readFileSync(SELLERS_PATH, "utf-8"));
    setCachedDocument("sellers", parsed);
    const sellers = normalizeSellerMap(parsed);
    schedulePhase1Compare("sellers-read");
    return sellers;
  } catch {
    setCachedDocument("sellers", {});
    schedulePhase1Compare("sellers-read");
    return {};
  }
}

function saveSellersFile(sellers) {
  writeManagedJSON("sellers", normalizeSellerMap(sellers));
}

app.post("/orders/buyer", requireAppClient, requireAuthenticatedBuyer, (req, res) => {
  try {
    const bodyEmail = String(req.body?.buyerEmail || "").trim().toLowerCase();
    const authEmail = String(req.auth.buyerEmail || "").trim().toLowerCase();
    if (!bodyEmail || bodyEmail !== authEmail) {
      return res.status(403).json({ error: "Buyer email must match the signed-in buyer session" });
    }
    const orderId = String(req.body?.orderId || "").trim();
    const config = exchangeConfigSnapshot();
    const exchangeRequests = loadExchangeRequestsFile();
    let orders = attachExchangeSummariesToOrders(loadHydratedOrders(), exchangeRequests, config);
    if (orderId) {
      orders = orders.filter((order) => order.id === orderId);
    }
    orders = orders.filter((order) => (order.buyerEmail || "").trim().toLowerCase() === authEmail);
    orders.sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime());
    res.json({ orders: orders.map((order) => hydrateOrderRecord(order)) });
  } catch (err) {
    console.error("orders buyer lookup error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/orders", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const buyerEmail = (req.query.buyerEmail || "").toString().trim().toLowerCase();
    const sellerId = (req.query.sellerId || "").toString().trim();
    const orderId = (req.query.orderId || "").toString().trim();

    if (buyerEmail) {
      return res.status(400).json({
        code: "use_post_orders_buyer",
        error: "Buyer orders must be fetched with POST /orders/buyer (signed-in session).",
      });
    } else if (sellerId) {
      if (req.auth.role !== "seller" || req.auth.sellerId !== sellerId) {
        auditOwnershipMismatch(req, {
          scope: "orders_seller_query",
          expectedRole: "seller",
          expectedSellerId: sellerId,
          actualRole: req.auth.role || null,
          actualSellerId: req.auth.sellerId || null,
        });
        return res.status(403).json({ error: "Seller order access denied" });
      }
    } else {
      return res.status(400).json({ error: "sellerId is required (buyers should POST /orders/buyer)" });
    }

    const config = exchangeConfigSnapshot();
    const exchangeRequests = loadExchangeRequestsFile();
    let orders = attachExchangeSummariesToOrders(loadHydratedOrders(), exchangeRequests, config);
    if (orderId) {
      orders = orders.filter((order) => order.id === orderId);
    }
    if (sellerId) {
      orders = orders.filter((order) => order.shipments.some((shipment) => shipment.sellerId === sellerId));
      orders = orders.map((order) => sellerScopedOrder(hydrateOrderRecord(order), sellerId));
    } else {
      orders = orders.map((order) => hydrateOrderRecord(order));
    }

    orders.sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime());
    res.json({ orders });
  } catch (err) {
    console.error("orders fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/exchange-requests/eligibility-check", requireAppClient, requireAuthenticatedBuyer, (req, res) => {
  try {
    const { orderId, orderItemId, requestedResolution, isAdminOverride } = req.body || {};
    const result = evaluateExchangeEligibility({
      orders: loadOrdersFile(),
      exchangeRequests: loadExchangeRequestsFile(),
      buyerEmail: req.auth.buyerEmail,
      orderId,
      orderItemId,
      requestedResolution,
      config: exchangeConfigSnapshot(),
      isAdminOverride: Boolean(isAdminOverride),
    });

    auditLog(
      auditContext(req, {
        action: "exchange_eligibility_checked",
        orderId: String(orderId || "").trim() || null,
        orderItemId: String(orderItemId || "").trim() || null,
        result: result.isEligible ? "eligible" : result.failureCode || "ineligible",
      })
    );

    res.json({ result });
  } catch (err) {
    console.error("exchange eligibility check error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/exchange-requests", requireAppClient, requireAuthenticatedBuyer, async (req, res) => {
  try {
    const {
      orderId,
      orderItemId,
      reasonCode,
      buyerExplanation,
      requestedResolution,
      originalVariantSnapshot,
      isAdminOverride,
    } = req.body || {};

    const normalizedOrderId = String(orderId || "").trim();
    const normalizedOrderItemId = String(orderItemId || "").trim();
    const normalizedExplanation = String(buyerExplanation || "").trim();
    const normalizedReasonCode = String(reasonCode || "").trim().toLowerCase();
    const normalizedResolution = String(requestedResolution || "same_item_exchange").trim().toLowerCase();

    if (!normalizedOrderId || !normalizedOrderItemId || !normalizedExplanation || !normalizedReasonCode) {
      return res.status(400).json({ error: "orderId, orderItemId, reasonCode, and buyerExplanation are required" });
    }

    const orders = loadOrdersFile();
    const exchangeRequests = loadExchangeRequestsFile();
    const config = exchangeConfigSnapshot();
    const eligibilityResult = evaluateExchangeEligibility({
      orders,
      exchangeRequests,
      buyerEmail: req.auth.buyerEmail,
      orderId: normalizedOrderId,
      orderItemId: normalizedOrderItemId,
      requestedResolution: normalizedResolution,
      config,
      isAdminOverride: Boolean(isAdminOverride),
    });

    if (!eligibilityResult.isEligible && !Boolean(isAdminOverride)) {
      return res.status(400).json({ error: eligibilityResult.failureMessage, result: eligibilityResult });
    }

    const order = orders.find((candidate) => candidate.id === normalizedOrderId);
    const resolved = order ? resolveOrderItem(order, normalizedOrderItemId) : null;
    if (!order || !resolved) {
      return res.status(404).json({ error: "Order item not found" });
    }

    const now = new Date().toISOString();
    const orderExchangeNumber = exchangeRequests.filter((request) => request.orderId === normalizedOrderId).length + 1;
    const nextRequest = normalizeExchangeRequest({
      id: `EX-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
      orderId: normalizedOrderId,
      orderItemId: normalizedOrderItemId,
      buyerUserId: exchangeBuyerUserId(req.auth.buyerEmail),
      sellerUserId: exchangeSellerUserId(resolved.shipment.sellerId),
      productId: resolved.item.productId,
      productTitle: resolved.item.productName,
      productImageURL: resolved.item.thumbnailURL || null,
      originalVariantSnapshot,
      reasonCode: normalizedReasonCode,
      buyerExplanation: normalizedExplanation,
      requestedResolution: normalizedResolution,
      status: config.minProofImages > 0 ? "awaiting_buyer_proof" : "submitted",
      buyerSubmittedAt: config.minProofImages > 0 ? null : now,
      eligibilityCheckedAt: now,
      eligibleAtSubmission: eligibilityResult.isEligible,
      eligibilityFailureReason: eligibilityResult.failureMessage,
      exchangeNumberForOrder: orderExchangeNumber,
      isAdminOverride: Boolean(isAdminOverride),
      timelineEvents: [
        createExchangeTimelineEvent(
          "request_created",
          "Exchange request created.",
          "buyer",
          exchangeBuyerUserId(req.auth.buyerEmail)
        ),
      ],
      createdAt: now,
      updatedAt: now,
    });

    if (nextRequest.status === "submitted") {
      nextRequest.timelineEvents.push(
        createExchangeTimelineEvent(
          "request_submitted",
          "Exchange request submitted.",
          "buyer",
          nextRequest.buyerUserId
        )
      );
    }

    exchangeRequests.unshift(nextRequest);
    saveExchangeRequestsFile(exchangeRequests);

    auditLog(
      auditContext(req, {
        action: "exchange_request_created",
        exchangeRequestId: nextRequest.id,
        orderId: nextRequest.orderId,
        orderItemId: nextRequest.orderItemId,
        reasonCode: nextRequest.reasonCode,
      })
    );

    try {
      await notifyOrderStatusChanged({
        sellerId: resolved.shipment.sellerId,
        title: "Exchange request submitted",
        body: `${resolved.item.productName || "An item"} has a new exchange request to review.`,
      });
    } catch (pushErr) {
      console.warn("Exchange request push notification error:", pushErr?.message || pushErr);
    }

    res.status(201).json({
      exchangeRequest: nextRequest,
      result: eligibilityResult,
    });
  } catch (err) {
    console.error("exchange request create error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post(
  "/exchange-requests/:id/proof",
  requireAppClient,
  requireAuthenticatedBuyer,
  mediaUploadLimiter,
  express.raw({ type: "*/*", limit: exchangeProofRawLimit }),
  async (req, res) => {
    try {
      const exchangeRequestId = String(req.params.id || "").trim();
      const exchangeRequests = loadExchangeRequestsFile();
      const requestIndex = exchangeRequests.findIndex((request) => request.id === exchangeRequestId);
      if (requestIndex < 0) {
        return res.status(404).json({ error: "Exchange request not found" });
      }

      const exchangeRequest = exchangeRequests[requestIndex];
      if (exchangeRequest.buyerUserId !== exchangeBuyerUserId(req.auth.buyerEmail)) {
        auditOwnershipMismatch(req, {
          scope: "exchange_proof_upload",
          expectedBuyerEmail: req.auth.buyerEmail || null,
          exchangeRequestId,
        });
        return res.status(403).json({ error: "Exchange proof upload denied" });
      }

      if (!["awaiting_buyer_proof", "submitted"].includes(exchangeRequest.status)) {
        return res.status(400).json({ error: "Proof uploads are not allowed for this exchange status" });
      }

      const config = exchangeConfigSnapshot();
      const proofType = String(req.headers["x-proof-type"] || "image").trim().toLowerCase();
      const contentType = String(req.headers["content-type"] || "").trim().toLowerCase();
      const fileExtension = sanitizeFileExtension(req.headers["x-file-extension"], proofType === "video" ? "mp4" : "jpg");
      const videoDurationSeconds = Number.parseInt(String(req.headers["x-video-duration-seconds"] || "0"), 10);
      const body = req.body;

      const mediaValidation = validateExchangeProofUpload({
        buffer: body,
        contentType,
        fileExtension,
        proofType,
      });
      if (!mediaValidation.ok) {
        recordSecurityAudit(req, {
          action: "media_upload_rejected",
          scope: "exchange_proof_upload",
          reason: mediaValidation.error,
          proofType,
        });
        return res.status(400).json({ error: mediaValidation.error });
      }

      if (proofType === "video" && !config.allowProofVideo) {
        return res.status(400).json({ error: "Video proof is not enabled" });
      }

      if (
        proofType === "video" &&
        Number.isFinite(videoDurationSeconds) &&
        videoDurationSeconds > config.maxVideoDurationSeconds
      ) {
        return res.status(400).json({ error: `Video proof must be ${config.maxVideoDurationSeconds} seconds or less` });
      }

      const existingImageCount = exchangeRequest.buyerProofAssets.filter((asset) => asset.type === "image").length;
      const existingVideoCount = exchangeRequest.buyerProofAssets.filter((asset) => asset.type === "video").length;
      if (proofType === "image" && existingImageCount >= config.maxProofImages) {
        return res.status(400).json({ error: `You can upload up to ${config.maxProofImages} images.` });
      }
      if (proofType === "video" && existingVideoCount >= 1) {
        return res.status(400).json({ error: "Only one proof video is allowed." });
      }

      const assetId = crypto.randomUUID();
      const relativeKey = `exchanges/${exchangeRequestId}/proof/${assetId}.${mediaValidation.extension}`;
      const { url: publicURL } = await storeMediaBytes({
        relativeKey,
        buffer: body,
        contentType: mediaValidation.contentType,
      });
      const asset = normalizeExchangeProofAsset({
        id: assetId,
        type: proofType,
        url: publicURL,
        storagePath: `exchanges/${exchangeRequestId}/proof/${assetId}.${mediaValidation.extension}`,
        thumbnailURL: proofType === "image" ? publicURL : null,
        uploadedAt: new Date().toISOString(),
        uploadedByUserId: exchangeRequest.buyerUserId,
      });

      exchangeRequest.buyerProofAssets.push(asset);
      exchangeRequest.timelineEvents.push(
        createExchangeTimelineEvent(
          "proof_uploaded",
          proofType === "video" ? "Buyer uploaded a proof video." : "Buyer uploaded proof photos.",
          "buyer",
          exchangeRequest.buyerUserId
        )
      );

      const uploadedImageCount = exchangeRequest.buyerProofAssets.filter((entry) => entry.type === "image").length;
      if (exchangeRequest.status === "awaiting_buyer_proof" && uploadedImageCount >= config.minProofImages) {
        exchangeRequest.status = "submitted";
        exchangeRequest.buyerSubmittedAt = exchangeRequest.buyerSubmittedAt || new Date().toISOString();
        exchangeRequest.timelineEvents.push(
          createExchangeTimelineEvent(
            "request_submitted",
            "Exchange request submitted.",
            "buyer",
            exchangeRequest.buyerUserId
          )
        );
      }

      exchangeRequest.updatedAt = new Date().toISOString();
      exchangeRequests[requestIndex] = normalizeExchangeRequest(exchangeRequest);
      saveExchangeRequestsFile(exchangeRequests);

      auditLog(
        auditContext(req, {
          action: "exchange_proof_uploaded",
          exchangeRequestId,
          orderId: exchangeRequest.orderId,
          orderItemId: exchangeRequest.orderItemId,
          proofType,
        })
      );

      res.json({ exchangeRequest: exchangeRequests[requestIndex], asset });
    } catch (err) {
      console.error("exchange proof upload error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.get("/exchange-requests/:id", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const exchangeRequestId = String(req.params.id || "").trim();
    const exchangeRequest = loadExchangeRequestsFile().find((request) => request.id === exchangeRequestId);
    if (!exchangeRequest) {
      return res.status(404).json({ error: "Exchange request not found" });
    }

    const orders = loadOrdersFile();
    const order = orders.find((candidate) => candidate.id === exchangeRequest.orderId) || null;
    const buyerAccess = buyerOwnsOrder(order, req.auth);
    const sellerAccess = sellerCanViewExchange(exchangeRequest, req.auth);

    if (!buyerAccess && !sellerAccess) {
      auditOwnershipMismatch(req, {
        scope: "exchange_request_fetch",
        exchangeRequestId,
        expectedBuyerEmail: order?.buyerEmail || null,
        expectedSellerId: exchangeRequest.sellerUserId || null,
      });
      return res.status(403).json({ error: "Exchange request access denied" });
    }

    res.json(exchangeRequestResponse(exchangeRequest, order));
  } catch (err) {
    console.error("exchange request fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/orders/:orderId/exchange-requests", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const orderId = String(req.params.orderId || "").trim();
    const orders = loadOrdersFile();
    const order = orders.find((candidate) => candidate.id === orderId);
    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (!buyerOwnsOrder(order, req.auth) && req.auth.role !== "seller") {
      auditOwnershipMismatch(req, {
        scope: "order_exchange_requests",
        orderId,
        expectedBuyerEmail: order.buyerEmail || null,
      });
      return res.status(403).json({ error: "Exchange request access denied" });
    }

    let exchangeRequests = loadExchangeRequestsFile().filter((request) => request.orderId === orderId);
    if (req.auth.role === "seller") {
      exchangeRequests = exchangeRequests.filter((request) => sellerCanViewExchange(request, req.auth));
    }

    exchangeRequests.sort(
      (lhs, rhs) => new Date(rhs.updatedAt || rhs.createdAt).getTime() - new Date(lhs.updatedAt || lhs.createdAt).getTime()
    );

    res.json({ exchangeRequests });
  } catch (err) {
    console.error("order exchange requests fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/exchange-requests/:id/cancel", requireAppClient, requireAuthenticatedBuyer, (req, res) => {
  try {
    const exchangeRequestId = String(req.params.id || "").trim();
    const exchangeRequests = loadExchangeRequestsFile();
    const requestIndex = exchangeRequests.findIndex((request) => request.id === exchangeRequestId);
    if (requestIndex < 0) {
      return res.status(404).json({ error: "Exchange request not found" });
    }

    const exchangeRequest = exchangeRequests[requestIndex];
    if (exchangeRequest.buyerUserId !== exchangeBuyerUserId(req.auth.buyerEmail)) {
      auditOwnershipMismatch(req, {
        scope: "exchange_request_cancel",
        exchangeRequestId,
        expectedBuyerEmail: req.auth.buyerEmail || null,
      });
      return res.status(403).json({ error: "Exchange request cancel denied" });
    }

    if (!["awaiting_buyer_proof", "submitted"].includes(exchangeRequest.status)) {
      return res.status(400).json({ error: "This exchange request can no longer be cancelled." });
    }

    const now = new Date().toISOString();
    exchangeRequest.status = "cancelled";
    exchangeRequest.closedAt = now;
    exchangeRequest.updatedAt = now;
    exchangeRequest.timelineEvents.push(
      createExchangeTimelineEvent(
        "request_cancelled",
        "Buyer cancelled the exchange request.",
        "buyer",
        exchangeRequest.buyerUserId
      )
    );

    exchangeRequests[requestIndex] = normalizeExchangeRequest(exchangeRequest);
    saveExchangeRequestsFile(exchangeRequests);

    auditLog(
      auditContext(req, {
        action: "exchange_request_cancelled",
        exchangeRequestId,
        orderId: exchangeRequest.orderId,
        orderItemId: exchangeRequest.orderItemId,
      })
    );

    res.json({ exchangeRequest: exchangeRequests[requestIndex] });
  } catch (err) {
    console.error("exchange request cancel error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/orders/shipment-action", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const { orderId, shipmentId, sellerId, action, carrier, trackingNumber } = req.body || {};
    if (!orderId || !shipmentId || !sellerId || !action) {
      return res.status(400).json({ error: "orderId, shipmentId, sellerId, and action are required" });
    }
    if (req.auth.sellerId !== String(sellerId).trim()) {
      auditOwnershipMismatch(req, {
        scope: "shipment_action",
        expectedSellerId: String(sellerId).trim(),
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller shipment action denied" });
    }

    const orders = loadOrdersFile();
    const orderIndex = orders.findIndex((order) => order.id === orderId);
    if (orderIndex < 0) return res.status(404).json({ error: "Order not found" });

    const shipmentIndex = orders[orderIndex].shipments.findIndex(
      (shipment) => shipment.id === shipmentId && shipment.sellerId === sellerId
    );
    if (shipmentIndex < 0) return res.status(404).json({ error: "Shipment not found" });

    const timestamp = new Date().toISOString();
    const shipment = orders[orderIndex].shipments[shipmentIndex];

    switch (action) {
      case "startProcessing":
        orders[orderIndex].status = "processing";
        break;
      case "markShipped": {
        const trimmedCarrier = String(carrier || "").trim();
        const trimmedTrackingNumber = String(trackingNumber || "").trim();
        if (!trimmedCarrier || !trimmedTrackingNumber) {
          return res.status(400).json({ error: "carrier and trackingNumber are required to mark a shipment as shipped" });
        }
        shipment.status = "shipped";
        shipment.shippedAt = timestamp;
        shipment.carrier = trimmedCarrier;
        shipment.trackingNumber = trimmedTrackingNumber;
        break;
      }
      case "markDelivered":
        shipment.status = "delivered";
        shipment.deliveredAt = timestamp;
        break;
      case "updateTracking": {
        const trimmedCarrier = String(carrier || "").trim();
        const trimmedTrackingNumber = String(trackingNumber || "").trim();
        if (!trimmedCarrier || !trimmedTrackingNumber) {
          return res.status(400).json({ error: "carrier and trackingNumber are required to update tracking" });
        }
        if (!["shipped", "delivered"].includes(String(shipment.status || "").trim().toLowerCase())) {
          return res.status(400).json({ error: "Tracking can only be updated after a shipment is marked shipped" });
        }
        shipment.carrier = trimmedCarrier;
        shipment.trackingNumber = trimmedTrackingNumber;
        break;
      }
      default:
        return res.status(400).json({ error: "Unknown shipment action" });
    }

    orders[orderIndex].status = deriveOrderStatus(orders[orderIndex].shipments, orders[orderIndex].status);
    const updatedOrder = saveHydratedOrder(orders[orderIndex]);

    try {
      const firstItemName = shipment.items?.[0]?.productName || "your item";
      if (updatedOrder.buyerEmail && ["startProcessing", "markShipped", "markDelivered"].includes(action)) {
        await notifyShipmentStatusToBuyer({
          buyerEmail: updatedOrder.buyerEmail,
          action,
          itemName: firstItemName,
          carrier: shipment.carrier,
          trackingNumber: shipment.trackingNumber,
        });
      }
    } catch (pushErr) {
      console.warn("Shipment status push notification error:", pushErr?.message || pushErr);
    }
    res.json({ order: sellerScopedOrder(updatedOrder, sellerId) });
  } catch (err) {
    console.error("shipment action error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post(
  "/orders/:orderId/support-requests",
  requireAppClient,
  requireAuthenticatedUser,
  express.json({ limit: "32kb" }),
  async (req, res) => {
    try {
      const orderId = String(req.params.orderId || "").trim();
      const sellerId = String(req.body?.sellerId || "").trim();
      const shipmentId = String(req.body?.shipmentId || "").trim();
      const type = String(req.body?.type || "").trim().toLowerCase();
      const reason = String(req.body?.reason || "").trim();

      const order = findOrderForParticipant(orderId, req.auth);
      if (!order) return res.status(404).json({ error: "Order not found" });

      if (req.auth.role === "seller" && req.auth.sellerId !== sellerId) {
        return res.status(403).json({ error: "Seller support request denied" });
      }
      if (!sellerCanAccessOrder(order, sellerId)) {
        return res.status(404).json({ error: "Seller shipment not found in this order" });
      }

      const shipment = order.shipments.find((entry) => entry.id === shipmentId && entry.sellerId === sellerId);
      const validation = validateSupportRequestCreate({
        type,
        reason,
        shipment,
        sellerId,
        existingRequests: order.supportRequests,
      });
      if (!validation.ok) {
        return res.status(400).json({ error: validation.error });
      }

      const request = normalizeSupportRequest({
        id: crypto.randomUUID(),
        type: validation.type,
        status: "pending",
        sellerId,
        shipmentId: shipment?.id || null,
        reason: validation.reason,
        requestedBy: req.auth.role === "seller" ? "seller" : "buyer",
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      order.supportRequests = [...order.supportRequests, request];
      const updatedOrder = saveHydratedOrder(order);

      auditLog(
        auditContext(req, {
          action: "order_support_request_created",
          orderId,
          requestId: request.id,
          type: request.type,
          sellerId,
        })
      );

      try {
        const itemName = shipment?.items?.[0]?.productName || "an item";
        const typeLabel = request.type === "refund" ? "refund" : "cancellation";
        if (request.requestedBy === "buyer") {
          await notifyOrderSupportEvent({
            sellerId,
            notifySeller: true,
            title: "New buyer request",
            body: `A buyer submitted a ${typeLabel} request for ${itemName} on order ${orderId}.`,
          });
        }
      } catch (pushErr) {
        console.warn("Support request push error:", pushErr?.message || pushErr);
      }

      respondWithParticipantOrder(res, updatedOrder, req.auth);
    } catch (err) {
      console.error("support request create error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.patch(
  "/orders/:orderId/support-requests/:requestId",
  requireAppClient,
  requireAuthenticatedUser,
  express.json({ limit: "32kb" }),
  async (req, res) => {
    try {
      const orderId = String(req.params.orderId || "").trim();
      const requestId = String(req.params.requestId || "").trim();
      const status = String(req.body?.status || "").trim().toLowerCase();
      const resolutionNote = String(req.body?.resolutionNote || "").trim();

      const order = findOrderForParticipant(orderId, req.auth);
      if (!order) return res.status(404).json({ error: "Order not found" });

      const requestIndex = order.supportRequests.findIndex((entry) => entry.id === requestId);
      if (requestIndex < 0) return res.status(404).json({ error: "Support request not found" });

      const existing = order.supportRequests[requestIndex];
      if (req.auth.role === "buyer") {
        if (!buyerOwnsOrder(order, req.auth)) {
          return res.status(403).json({ error: "Buyer support update denied" });
        }
        if (status !== "withdrawn" || existing.requestedBy !== "buyer") {
          return res.status(400).json({ error: "Buyers can only withdraw their own pending requests" });
        }
      } else if (req.auth.role === "seller") {
        if (req.auth.sellerId !== existing.sellerId) {
          return res.status(403).json({ error: "Seller support update denied" });
        }
        if (!["approved", "denied"].includes(status)) {
          return res.status(400).json({ error: "Sellers can approve or deny support requests" });
        }
      } else {
        return res.status(403).json({ error: "Support update denied" });
      }

      if (existing.status !== "pending") {
        return res.status(400).json({ error: "Only pending requests can be updated" });
      }

      const updatedRequest = normalizeSupportRequest({
        ...existing,
        status,
        resolutionNote: resolutionNote || existing.resolutionNote,
        updatedAt: new Date().toISOString(),
      });
      order.supportRequests[requestIndex] = updatedRequest;
      let nextOrder = saveHydratedOrder(order);
      if (status === "approved") {
        nextOrder = saveHydratedOrder(applyApprovedSupportRequest(nextOrder, updatedRequest));
      }

      auditLog(
        auditContext(req, {
          action: "order_support_request_updated",
          orderId,
          requestId,
          status,
          sellerId: existing.sellerId,
        })
      );

      try {
        const itemName =
          nextOrder.shipments
            ?.find((entry) => entry.id === existing.shipmentId)
            ?.items?.[0]?.productName || "your item";
        if (req.auth.role === "seller") {
          const typeLabel = existing.type === "refund" ? "Refund" : "Cancel";
          const title =
            status === "approved" ? `${typeLabel} request approved` : `${typeLabel} request denied`;
          const body =
            status === "approved"
              ? `Your ${existing.type} request for ${itemName} was approved.`
              : `Your ${existing.type} request for ${itemName} was denied.`;
          await notifyOrderSupportEvent({
            buyerEmail: nextOrder.buyerEmail,
            notifyBuyer: true,
            title,
            body,
          });
        } else if (status === "withdrawn") {
          await notifyOrderSupportEvent({
            sellerId: existing.sellerId,
            notifySeller: true,
            title: "Request withdrawn",
            body: `The buyer withdrew their ${existing.type} request for order ${orderId}.`,
          });
        }
      } catch (pushErr) {
        console.warn("Support request update push error:", pushErr?.message || pushErr);
      }

      respondWithParticipantOrder(res, nextOrder, req.auth);
    } catch (err) {
      console.error("support request update error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.post(
  "/orders/:orderId/support-requests/:requestId/evidence",
  requireAppClient,
  requireAuthenticatedUser,
  mediaUploadLimiter,
  express.raw({ type: "*/*", limit: exchangeProofRawLimit }),
  async (req, res) => {
    try {
      const orderId = String(req.params.orderId || "").trim();
      const requestId = String(req.params.requestId || "").trim();

      const order = findOrderForParticipant(orderId, req.auth);
      if (!order) return res.status(404).json({ error: "Order not found" });

      const requestIndex = order.supportRequests.findIndex((entry) => entry.id === requestId);
      if (requestIndex < 0) return res.status(404).json({ error: "Support request not found" });

      const supportRequest = order.supportRequests[requestIndex];

      if (req.auth.role === "buyer" && !buyerOwnsOrder(order, req.auth)) {
        return res.status(403).json({ error: "Evidence upload denied" });
      }
      if (req.auth.role === "seller" && req.auth.sellerId !== supportRequest.sellerId) {
        return res.status(403).json({ error: "Evidence upload denied" });
      }
      if (supportRequest.type !== "refund") {
        return res.status(400).json({ error: "Evidence uploads are only allowed for refund requests" });
      }
      if ((supportRequest.evidenceAssets || []).length >= 3) {
        return res.status(400).json({ error: "You can attach up to 3 evidence files." });
      }

      const proofType = String(req.headers["x-proof-type"] || "image").trim().toLowerCase() === "video" ? "video" : "image";
      const contentType = String(req.headers["content-type"] || "").trim().toLowerCase();
      const fileExtension = sanitizeFileExtension(req.headers["x-file-extension"], proofType === "video" ? "mp4" : "jpg");
      const body = req.body;

      const mediaValidation = validateExchangeProofUpload({
        buffer: body,
        contentType,
        fileExtension,
        proofType,
      });
      if (!mediaValidation.ok) {
        return res.status(400).json({ error: mediaValidation.error });
      }

      const assetId = crypto.randomUUID();
      const relativeKey = `orders/${orderId}/support-evidence/${requestId}/${assetId}.${mediaValidation.extension}`;
      const { url: publicURL } = await storeMediaBytes({
        relativeKey,
        buffer: body,
        contentType: mediaValidation.contentType,
      });

      const asset = {
        id: assetId,
        type: proofType,
        url: publicURL,
        uploadedAt: new Date().toISOString(),
      };

      order.supportRequests[requestIndex] = normalizeSupportRequest({
        ...supportRequest,
        evidenceAssets: [...(supportRequest.evidenceAssets || []), asset],
        updatedAt: new Date().toISOString(),
      });
      const updatedOrder = saveHydratedOrder(order);

      auditLog(
        auditContext(req, {
          action: "order_support_evidence_uploaded",
          orderId,
          requestId,
          proofType,
          sellerId: supportRequest.sellerId,
        })
      );

      respondWithParticipantOrder(res, updatedOrder, req.auth);
    } catch (err) {
      console.error("support evidence upload error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.get("/orders/:orderId/support-thread", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const orderId = String(req.params.orderId || "").trim();
    const sellerId = String(req.query.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });

    const order = findOrderForParticipant(orderId, req.auth);
    if (!order) return res.status(404).json({ error: "Order not found" });
    if (!sellerCanAccessOrder(order, sellerId)) {
      return res.status(404).json({ error: "Seller not found in this order" });
    }
    if (req.auth.role === "seller" && req.auth.sellerId !== sellerId) {
      return res.status(403).json({ error: "Seller thread access denied" });
    }

    res.json({
      orderId,
      sellerId,
      messages: orderMessagesForSeller(order.orderMessages, sellerId),
    });
  } catch (err) {
    console.error("support thread fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post(
  "/orders/:orderId/support-thread",
  requireAppClient,
  requireAuthenticatedUser,
  express.json({ limit: "16kb" }),
  async (req, res) => {
    try {
      const orderId = String(req.params.orderId || "").trim();
      const sellerId = String(req.body?.sellerId || "").trim();
      const text = String(req.body?.text || "").trim();
      if (!sellerId || text.length < 1) {
        return res.status(400).json({ error: "sellerId and message text are required" });
      }
      if (text.length > 2000) {
        return res.status(400).json({ error: "Message is too long" });
      }

      const order = findOrderForParticipant(orderId, req.auth);
      if (!order) return res.status(404).json({ error: "Order not found" });
      if (!sellerCanAccessOrder(order, sellerId)) {
        return res.status(404).json({ error: "Seller not found in this order" });
      }
      if (req.auth.role === "seller" && req.auth.sellerId !== sellerId) {
        return res.status(403).json({ error: "Seller thread access denied" });
      }

      const message = normalizeOrderMessage({
        id: crypto.randomUUID(),
        sellerId,
        senderRole: req.auth.role === "seller" ? "seller" : "buyer",
        senderEmail:
          req.auth.role === "buyer"
            ? req.auth.buyerEmail
            : null,
        senderName: String(req.body?.senderName || "").trim() || null,
        text,
        createdAt: new Date().toISOString(),
      });

      order.orderMessages = [...order.orderMessages, message];
      const updatedOrder = saveHydratedOrder(order);

      auditLog(
        auditContext(req, {
          action: "order_support_message_sent",
          orderId,
          sellerId,
          messageId: message.id,
          senderRole: message.senderRole,
        })
      );

      try {
        const preview = text.length > 140 ? `${text.slice(0, 137)}…` : text;
        if (message.senderRole === "buyer") {
          await notifyOrderSupportEvent({
            sellerId,
            notifySeller: true,
            title: "Buyer message",
            body: `New message on order ${orderId}: ${preview}`,
          });
        } else {
          await notifyOrderSupportEvent({
            buyerEmail: updatedOrder.buyerEmail,
            notifyBuyer: true,
            title: "Seller update",
            body: `Reply on order ${orderId}: ${preview}`,
          });
        }
      } catch (pushErr) {
        console.warn("Support message push error:", pushErr?.message || pushErr);
      }

      res.json({
        orderId,
        sellerId,
        message,
        messages: orderMessagesForSeller(updatedOrder.orderMessages, sellerId),
        order: req.auth.role === "seller" ? sellerScopedOrder(updatedOrder, sellerId) : updatedOrder,
      });
    } catch (err) {
      console.error("support thread post error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.get("/buyer/inquiry-threads", requireAppClient, requireAuthenticatedBuyer, (req, res) => {
  try {
    const buyerEmail = String(req.auth.buyerEmail || "").trim().toLowerCase();
    const threads = loadSellerInquiriesFile()
      .filter((thread) => thread.buyerEmail === buyerEmail)
      .sort((lhs, rhs) => new Date(rhs.updatedAt).getTime() - new Date(lhs.updatedAt).getTime());
    res.json({ threads });
  } catch (err) {
    console.error("buyer inquiry threads list error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller/inquiry-threads", requireAppClient, requireAuthenticatedSeller, (req, res) => {
  try {
    const sellerId = String(req.auth.sellerId || "").trim();
    const threads = loadSellerInquiriesFile()
      .filter((thread) => thread.sellerId === sellerId)
      .sort((lhs, rhs) => new Date(rhs.updatedAt).getTime() - new Date(lhs.updatedAt).getTime());
    res.json({ threads });
  } catch (err) {
    console.error("seller inquiry threads list error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/sellers/:sellerId/inquiry-thread", requireAppClient, requireAuthenticatedUser, (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });

    if (req.auth.role === "seller") {
      if (req.auth.sellerId !== sellerId) {
        return res.status(403).json({ error: "Seller inquiry access denied" });
      }
      const buyerEmail = String(req.query.buyerEmail || "").trim().toLowerCase();
      if (!buyerEmail) {
        return res.status(400).json({ error: "buyerEmail is required for seller inquiry lookup" });
      }
      const threads = loadSellerInquiriesFile();
      const thread = findInquiryThread(threads, buyerEmail, sellerId);
      return res.json({
        sellerId,
        buyerEmail,
        thread: thread || null,
        messages: thread?.messages || [],
      });
    }

    const created = getOrCreateInquiryThreadForBuyer(
      sellerId,
      req.auth,
      String(req.query.buyerName || "").trim() || null
    );
    if (!created.ok) return res.status(401).json({ error: created.error });
    const thread = created.thread;
    res.json({
      sellerId,
      buyerEmail: thread.buyerEmail,
      threadId: thread.id,
      messages: thread.messages,
    });
  } catch (err) {
    console.error("inquiry thread fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post(
  "/sellers/:sellerId/inquiry-thread",
  requireAppClient,
  requireAuthenticatedUser,
  express.json({ limit: "16kb" }),
  async (req, res) => {
    try {
      const sellerId = String(req.params.sellerId || "").trim();
      const text = String(req.body?.text || "").trim();
      if (!sellerId || text.length < 1) {
        return res.status(400).json({ error: "sellerId and message text are required" });
      }
      if (text.length > 2000) {
        return res.status(400).json({ error: "Message is too long" });
      }

      if (req.auth.role === "seller" && req.auth.sellerId !== sellerId) {
        return res.status(403).json({ error: "Seller inquiry access denied" });
      }

      let buyerEmail = "";
      let buyerName = null;
      if (req.auth.role === "buyer") {
        buyerEmail = String(req.auth.buyerEmail || "").trim().toLowerCase();
        buyerName = String(req.body?.senderName || "").trim() || null;
      } else {
        buyerEmail = String(req.body?.buyerEmail || req.query?.buyerEmail || "").trim().toLowerCase();
        if (!buyerEmail) {
          return res.status(400).json({ error: "buyerEmail is required when replying as seller" });
        }
      }

      const message = normalizeOrderMessage({
        id: crypto.randomUUID(),
        sellerId,
        senderRole: req.auth.role === "seller" ? "seller" : "buyer",
        senderEmail: req.auth.role === "buyer" ? req.auth.buyerEmail : null,
        senderName: String(req.body?.senderName || "").trim() || null,
        text,
        createdAt: new Date().toISOString(),
      });

      const threads = loadSellerInquiriesFile();
      const { threads: nextThreads, thread, message: savedMessage } = appendInquiryMessage(threads, {
        sellerId,
        buyerEmail,
        buyerName,
        message,
      });
      if (!thread || !savedMessage) {
        return res.status(500).json({ error: "Failed to save inquiry message" });
      }
      saveSellerInquiriesFile(nextThreads);

      auditLog(
        auditContext(req, {
          action: "seller_inquiry_message_sent",
          sellerId,
          buyerEmail,
          messageId: savedMessage.id,
          senderRole: savedMessage.senderRole,
        })
      );

      try {
        const preview = text.length > 140 ? `${text.slice(0, 137)}…` : text;
        if (savedMessage.senderRole === "buyer") {
          await notifyOrderSupportEvent({
            sellerId,
            notifySeller: true,
            title: "Shop message",
            body: `New message from a buyer: ${preview}`,
          });
        } else {
          await notifyOrderSupportEvent({
            buyerEmail: thread.buyerEmail,
            notifyBuyer: true,
            title: "Seller replied",
            body: `${preview}`,
          });
        }
      } catch (pushErr) {
        console.warn("Inquiry message push error:", pushErr?.message || pushErr);
      }

      res.json({
        sellerId,
        buyerEmail: thread.buyerEmail,
        threadId: thread.id,
        message: savedMessage,
        messages: thread.messages,
      });
    } catch (err) {
      console.error("inquiry thread post error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.post("/orders/production-preview", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const {
      orderId,
      shipmentId,
      sellerId,
      orderItemId,
      productionPreviewURL,
      removeProductionPreview,
    } = req.body || {};

    if (!orderId || !shipmentId || !sellerId || !orderItemId) {
      return res.status(400).json({ error: "orderId, shipmentId, sellerId, and orderItemId are required" });
    }
    if (req.auth.sellerId !== String(sellerId).trim()) {
      auditOwnershipMismatch(req, {
        scope: "order_production_preview",
        expectedSellerId: String(sellerId).trim(),
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller production update denied" });
    }

    const orders = loadOrdersFile();
    const orderIndex = orders.findIndex((order) => order.id === orderId);
    if (orderIndex < 0) return res.status(404).json({ error: "Order not found" });

    const shipmentIndex = orders[orderIndex].shipments.findIndex(
      (shipment) => shipment.id === shipmentId && shipment.sellerId === sellerId
    );
    if (shipmentIndex < 0) return res.status(404).json({ error: "Shipment not found" });

    const itemIndex = (orders[orderIndex].shipments[shipmentIndex].items || []).findIndex(
      (item) => item.id === orderItemId
    );
    if (itemIndex < 0) return res.status(404).json({ error: "Order item not found" });

    const shipment = orders[orderIndex].shipments[shipmentIndex];
    const item = shipment.items[itemIndex];
    const nextProductionPreviewURL = removeProductionPreview
      ? null
      : String(productionPreviewURL || "").trim() || null;

    if (!removeProductionPreview && !nextProductionPreviewURL) {
      return res.status(400).json({ error: "productionPreviewURL is required unless removeProductionPreview is true" });
    }

    const hadProductionPreview = Boolean(String(item.productionPreviewURL || "").trim());
    item.productionPreviewURL = nextProductionPreviewURL;
    saveOrdersFile(orders);
    const updatedOrder = orders[orderIndex];

    if (!hadProductionPreview && nextProductionPreviewURL && updatedOrder.buyerEmail) {
      try {
        await notifyOrderStatusChanged({
          buyerEmail: updatedOrder.buyerEmail,
          title: "Production update is ready",
          body: `A new production update for ${item.productName || "your item"} is now available in your order details.`,
        });
      } catch (pushErr) {
        console.warn("Production preview push notification error:", pushErr?.message || pushErr);
      }
    }

    res.json({ order: sellerScopedOrder(updatedOrder, sellerId) });
  } catch (err) {
    console.error("order production preview error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/product-reviews", requireAppClient, requireAuthenticatedBuyer, (req, res) => {
  try {
    const { orderId, productId, buyerEmail, rating, reviewText } = req.body || {};
    const normalizedOrderId = String(orderId || "").trim();
    const normalizedProductId = String(productId || "").trim();
    const normalizedBuyerEmail = String(buyerEmail || "").trim().toLowerCase();
    const normalizedRating = Math.round(asFiniteNumber(rating, 0));

    if (req.auth.buyerEmail !== normalizedBuyerEmail) {
      auditOwnershipMismatch(req, {
        scope: "product_review_submit",
        expectedBuyerEmail: normalizedBuyerEmail,
        actualBuyerEmail: req.auth.buyerEmail || null,
      });
      return res.status(403).json({ error: "Buyer review submission denied" });
    }

    if (!normalizedOrderId || !normalizedProductId || !normalizedBuyerEmail) {
      return res.status(400).json({ error: "orderId, productId, and buyerEmail are required" });
    }

    if (![1, 2, 3, 4, 5].includes(normalizedRating)) {
      return res.status(400).json({ error: "rating must be an integer from 1 to 5" });
    }

    const orders = loadOrdersFile();
    const order = orders.find((entry) => entry.id === normalizedOrderId);
    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (!orderContainsDeliveredProductForBuyer(order, normalizedBuyerEmail, normalizedProductId)) {
      return res.status(400).json({ error: "Only delivered products from your orders can be rated" });
    }

    const shipment = (order.shipments || []).find((entry) =>
      (entry.items || []).some((item) => item.productId === normalizedProductId)
    );
    const sellerId = shipment?.sellerId || null;

    const reviews = loadProductReviewsFile();
    const existingIndex = reviews.findIndex((entry) =>
      String(entry.orderId || "").trim() === normalizedOrderId &&
      String(entry.productId || "").trim() === normalizedProductId &&
      String(entry.buyerEmail || "").trim().toLowerCase() === normalizedBuyerEmail
    );

    const timestamp = new Date().toISOString();
    const nextReview = {
      id: existingIndex >= 0 ? reviews[existingIndex].id : `REV-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
      orderId: normalizedOrderId,
      productId: normalizedProductId,
      sellerId,
      buyerEmail: normalizedBuyerEmail,
      rating: normalizedRating,
      reviewText: String(reviewText || "").trim() || null,
      createdAt: existingIndex >= 0 ? reviews[existingIndex].createdAt : timestamp,
      updatedAt: timestamp,
    };

    if (existingIndex >= 0) {
      reviews[existingIndex] = nextReview;
    } else {
      reviews.unshift(nextReview);
    }

    saveProductReviewsFile(reviews);

    const summary = buildProductReviewSummaryMap(reviews).get(normalizedProductId) || { total: normalizedRating, count: 1 };
    res.json({
      ok: true,
      productId: normalizedProductId,
      averageRating: Number((summary.total / summary.count).toFixed(1)),
      reviewCount: summary.count,
    });
  } catch (err) {
    console.error("product review error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/product-reviews", publicReadLimiter, (req, res) => {
  try {
    const productId = String(req.query.productId || "").trim();
    if (!productId) {
      return res.status(400).json({ error: "productId is required" });
    }

    const reviews = loadProductReviewsFile()
      .filter((entry) => String(entry.productId || "").trim() === productId)
      .sort((lhs, rhs) => new Date(rhs.updatedAt || rhs.createdAt || 0).getTime() - new Date(lhs.updatedAt || lhs.createdAt || 0).getTime());

    const summary = buildProductReviewSummaryMap(reviews).get(productId) || { total: 0, count: 0 };

    const payload = {
      productId,
      averageRating: summary.count > 0 ? Number((summary.total / summary.count).toFixed(1)) : 0,
      reviewCount: summary.count,
      reviews,
    };
    const etag = `"pr-${productId}-${etagFromFileURL(PRODUCT_REVIEWS_PATH).slice(1, -1)}"`;
    return sendPublicJsonWithCache(req, res, payload, { maxAgeSeconds: 45, etag });
  } catch (err) {
    console.error("product reviews fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/create-seller-account", requireAppClient, async (req, res) => {
  try {
    const rawSellerId = String(req.body.sellerId || "").trim().toLowerCase();
    const sellerId = rawSellerId.replace(/\s+/g, "-");
    const email = String(req.body.email || "").trim().toLowerCase();
    const password = String(req.body.password || "");
    const businessName = req.body.businessName;
    const legalName = String(req.body.legalName || "").trim();
    const shippingOriginCountry = String(req.body.shippingOriginCountry || "").trim();
    const shippingOriginState = String(req.body.shippingOriginState || "").trim().toUpperCase();
    const sellerAgreementAccepted = req.body.sellerAgreementAccepted === true;
    const sellerPoliciesAcknowledged = req.body.sellerPoliciesAcknowledged === true;

    if (!sellerId || !email) return res.status(400).json({ error: "sellerId and email required" });
    if (!password || password.length < 8) return res.status(400).json({ error: "Password must be at least 8 characters" });
    if (!legalName) return res.status(400).json({ error: "Legal name is required" });
    if (!shippingOriginCountry || !shippingOriginState) {
      return res.status(400).json({ error: "Shipping origin country and state are required" });
    }
    if (!sellerAgreementAccepted || !sellerPoliciesAcknowledged) {
      return res.status(400).json({ error: "Seller agreement and seller policy acknowledgement are required" });
    }
    if (!isValidSellerId(sellerId)) {
      return res.status(400).json({ error: "Seller ID must be 3 to 24 characters using letters, numbers, hyphens, or underscores." });
    }
    const sellers = loadSellersFile();
    if (sellers[sellerId]) return res.status(409).json({ error: "Seller already exists" });

    let account = null;
    let onboardingUrl = "";
    if (isStripeConnectConfigured()) {
      account = await stripe.accounts.create({
        type: "express",
        email,
        business_profile: { name: businessName || sellerId },
        capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
      });
    }

    sellers[sellerId] = {
      stripeAccountId: account?.id || "",
      email,
      passwordHash: hashSellerPassword(password),
      businessName: businessName || "",
      legalName,
      shippingOrigin: {
        country: shippingOriginCountry,
        state: shippingOriginState,
      },
      sellerAgreement: {
        accepted: true,
        acceptedAt: new Date().toISOString(),
        version: "seller-agreement-2026-04-24",
      },
      sellerPoliciesAcknowledged: true,
      membership: normalizeMembership(),
      profile: normalizeSellerPublicProfile({}, sellerId, businessName || sellerId),
    };
    saveSellersFile(sellers);

    if (account?.id) {
      const link = await stripe.accountLinks.create({
        account: account.id,
        refresh_url: `${BACKEND_URL}/seller-onboarding-refresh?sellerId=${sellerId}`,
        return_url: `${BACKEND_URL}/seller-onboarding-complete?sellerId=${sellerId}`,
        type: "account_onboarding",
      });
      onboardingUrl = link.url;
    }

    const token = issueUserSessionToken({
      role: "seller",
      sellerId,
      sellerEmail: email,
    });

    res.json({
      sellerId,
      stripeAccountId: account?.id || "",
      onboardingUrl,
      token,
      payoutSetupPending: !account?.id,
      payoutSetupMessage: account?.id ? null : STRIPE_CONNECT_SETUP_MESSAGE,
    });
  } catch (err) {
    console.error("create-seller-account error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-link/:sellerId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const requestedSellerId = String(req.params.sellerId || "").trim();
    if (req.auth.sellerId !== requestedSellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_onboarding_link",
        expectedSellerId: requestedSellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller onboarding access denied" });
    }
    const sellers = loadSellersFile();
    const seller = sellers[requestedSellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    if (!isStripeConnectConfigured() || !seller.stripeAccountId) {
      return res.status(503).json({
        error: STRIPE_CONNECT_SETUP_MESSAGE,
        payoutSetupPending: true,
      });
    }
    const link = await stripe.accountLinks.create({
      account: seller.stripeAccountId,
      refresh_url: `${BACKEND_URL}/seller-onboarding-refresh?sellerId=${requestedSellerId}`,
      return_url: `${BACKEND_URL}/seller-onboarding-complete?sellerId=${requestedSellerId}`,
      type: "account_onboarding",
    });
    res.json({ sellerId: requestedSellerId, onboardingUrl: link.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-status/:sellerId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const requestedSellerId = String(req.params.sellerId || "").trim();
    if (req.auth.sellerId !== requestedSellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_onboarding_status",
        expectedSellerId: requestedSellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller status access denied" });
    }
    const sellers = loadSellersFile();
    const seller = sellers[requestedSellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const membership = effectiveSellerMembershipStatus(seller);
    if (!isStripeConnectConfigured() || !seller.stripeAccountId) {
      return res.json(stripePendingSellerStatus(requestedSellerId, seller));
    }
    const account = await stripe.accounts.retrieve(seller.stripeAccountId);
    res.json({
      sellerId: requestedSellerId,
      stripeAccountId: seller.stripeAccountId,
      chargesEnabled: account.charges_enabled,
      payoutsEnabled: account.payouts_enabled,
      detailsSubmitted: account.details_submitted,
      onboardingComplete: account.charges_enabled && account.payouts_enabled && account.details_submitted,
      payoutSetupPending: false,
      payoutSetupActionRequired: !(account.charges_enabled && account.payouts_enabled && account.details_submitted),
      payoutSetupMessage: null,
      hasActiveSubscription: membership.hasActiveSubscription,
      hasPaidSubscription: membership.membership.hasActiveSubscription,
      subscriptionExpiresAt: membership.membership.expiresAt,
      subscriptionProductId: membership.membership.productId,
      membershipStatus: membership.membershipStatus,
      isFoundingCreator: membership.founding.isFoundingCreator,
      foundingCreatorAccessStartsAt: membership.founding.foundingCreatorAccessStartsAt,
      foundingCreatorAccessEndsAt: membership.founding.foundingCreatorAccessEndsAt,
      creatorBadge: membership.founding.creatorBadge,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-dashboard-link/:sellerId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const requestedSellerId = String(req.params.sellerId || "").trim();
    if (req.auth.sellerId !== requestedSellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_dashboard_link",
        expectedSellerId: requestedSellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller dashboard access denied" });
    }
    const sellers = loadSellersFile();
    const seller = sellers[requestedSellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    if (!isStripeConnectConfigured() || !seller.stripeAccountId) {
      return res.status(503).json({
        error: STRIPE_CONNECT_SETUP_MESSAGE,
        payoutSetupPending: true,
      });
    }
    const link = await stripe.accounts.createLoginLink(seller.stripeAccountId);
    res.json({ sellerId: requestedSellerId, dashboardUrl: link.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-complete", (req, res) => {
  res.send("<html><body><h1>Onboarding complete!</h1><p>You can close this window and return to the app.</p></body></html>");
});

app.get("/seller-onboarding-refresh", (req, res) => {
  res.send("<html><body><h1>Session expired</h1><p>Please go back to the app and try again.</p></body></html>");
});

app.get("/sellers", requireAdmin, (_, res) => res.json(loadSellersFile()));

app.get("/seller-profiles", publicReadLimiter, async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const catalog = await fetchCatalog();
    const orders = loadOrdersFile();
    const payload = {
      sellers: buildSellerProfiles(sellers, catalog.products || [], orders),
    };
    const etag = `"sp-all-${etagFromFileURL(SELLERS_PATH).slice(1, -1)}-${etagFromFileURL(PRODUCTS_PATH).slice(1, -1)}-${etagFromFileURL(ORDERS_PATH).slice(1, -1)}"`;
    return sendPublicJsonWithCache(req, res, payload, { maxAgeSeconds: 45, etag });
  } catch (err) {
    console.error("seller-profiles error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-profiles/:sellerId", publicReadLimiter, async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "Seller id is required" });

    const sellers = loadSellersFile();
    const catalog = await fetchCatalog();
    const orders = loadOrdersFile();
    const hasCatalogProducts = (catalog.products || []).some((product) => product.sellerId === sellerId);
    if (!sellers[sellerId] && !hasCatalogProducts) {
      return res.status(404).json({ error: "Seller not found" });
    }

    const payload = {
      seller: buildSellerProfile(sellerId, sellers[sellerId], catalog.products || [], orders),
    };
    const etag = `"sp-${sellerId}-${etagFromFileURL(SELLERS_PATH).slice(1, -1)}-${etagFromFileURL(PRODUCTS_PATH).slice(1, -1)}-${etagFromFileURL(ORDERS_PATH).slice(1, -1)}"`;
    return sendPublicJsonWithCache(req, res, payload, { maxAgeSeconds: 45, etag });
  } catch (err) {
    console.error("seller-profile error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put("/seller-profiles/:sellerId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "Seller id is required" });
    if (req.auth.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_profile_update",
        expectedSellerId: sellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller profile update denied" });
    }

    const sellers = loadSellersFile();
    let seller = sellers[sellerId];
    if (!seller) {
      sellers[sellerId] = normalizeSellerRecord(
        {
          businessName: String(req.body?.displayName || "").trim() || sellerId,
          profile: normalizeSellerPublicProfile({}, sellerId, sellerId),
        },
        sellerId
      );
      seller = sellers[sellerId];
      saveSellersFile(sellers);
    }

    const body = req.body || {};
    // Only overwrite media/website when the client explicitly sends those keys.
    // Omitting them (common when editing text-only fields) must keep existing storefront images.
    const hasAvatarURL = Object.prototype.hasOwnProperty.call(body, "avatarURL");
    const hasBannerURL = Object.prototype.hasOwnProperty.call(body, "bannerURL");
    const hasWebsiteURL = Object.prototype.hasOwnProperty.call(body, "websiteURL");
    const mergedProfile = normalizeSellerPublicProfile(
      {
        ...(seller.profile || {}),
        displayName: body.displayName,
        handle: body.handle,
        bio: body.bio,
        ...(hasAvatarURL ? { avatarURL: body.avatarURL } : {}),
        ...(hasBannerURL ? { bannerURL: body.bannerURL } : {}),
        ...(hasWebsiteURL ? { websiteURL: body.websiteURL } : {}),
        location: body.location,
        materials: Array.isArray(body.materials) ? body.materials : seller.profile?.materials,
        processingTime: body.processingTime,
        designLicense: body.designLicense,
        isVerified: body.isVerified,
        joinedAt: seller.profile?.joinedAt,
        shipsInMinDays: body.shipsInMinDays,
        shipsInMaxDays: body.shipsInMaxDays,
        productCount: seller.profile?.productCount,
        orderCount: seller.profile?.orderCount,
        totalReviewCount: seller.profile?.totalReviewCount,
        positiveReviewCount: seller.profile?.positiveReviewCount,
        rating: seller.profile?.rating,
        likeCount: seller.profile?.likeCount,
        pageViewCount: seller.profile?.pageViewCount,
        acceptsCustomOrders:
          typeof body.acceptsCustomOrders === "boolean"
            ? body.acceptsCustomOrders
            : seller.profile?.acceptsCustomOrders === true,
        customOrderInfoURL:
          body.customOrderInfoURL !== undefined
            ? body.customOrderInfoURL === null || body.customOrderInfoURL === ""
              ? null
              : String(body.customOrderInfoURL).trim() || null
            : seller.profile?.customOrderInfoURL ?? null,
      },
      sellerId,
      body.displayName || seller.businessName || seller.profile?.displayName
    );

    seller.businessName = mergedProfile.displayName;
    seller.profile = mergedProfile;
    sellers[sellerId] = seller;
    saveSellersFile(sellers);

    const catalog = await fetchCatalog();
    const orders = loadOrdersFile();
    res.json({
      seller: buildSellerProfile(sellerId, seller, catalog.products || [], orders),
    });
  } catch (err) {
    console.error("update seller-profile error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post(
  "/custom-order-reference/:sellerId",
  requireAppClient,
  customOrderLimiter,
  mediaUploadLimiter,
  express.raw({ type: "*/*", limit: customOrderRefRawLimit }),
  async (req, res) => {
    try {
      const sellerId = sanitizePathSegment(req.params.sellerId, "seller");
      const sellers = loadSellersFile();
      if (!sellers[sellerId]) {
        return res.status(404).json({ error: "Seller not found" });
      }
      const profile = normalizeSellerPublicProfile(
        sellers[sellerId].profile,
        sellerId,
        sellers[sellerId].businessName
      );
      if (!profile.acceptsCustomOrders) {
        return res.status(403).json({ error: "This seller is not accepting custom order uploads" });
      }

      const body = req.body;
      const contentType = String(req.headers["content-type"] || "").trim().toLowerCase();
      const extension = sanitizeFileExtension(req.headers["x-file-extension"], "jpg");
      const mediaValidation = validateCustomOrderReferenceUpload({
        buffer: body,
        contentType,
        fileExtension: extension,
      });
      if (!mediaValidation.ok) {
        recordSecurityAudit(req, {
          action: "media_upload_rejected",
          scope: "custom_order_reference_upload",
          reason: mediaValidation.error,
          sellerId,
        });
        return res.status(400).json({ error: mediaValidation.error });
      }

      const assetId = crypto.randomUUID();
      const relativeKey = `custom-order-ref/${sellerId}/${assetId}.${mediaValidation.extension}`;
      const { url } = await storeMediaBytes({
        relativeKey,
        buffer: body,
        contentType: mediaValidation.contentType,
      });
      const storageProvider = String(process.env.S3_MEDIA_BUCKET || "").trim() ? "object_storage" : "local_disk";
      if (isPgEnabled()) {
        void recordSellerMediaUpload({
          id: `custom-order-ref:${assetId}`,
          sellerId,
          productId: null,
          mediaKind: "custom-order-reference",
          url,
          storageProvider,
          source: "custom_order_reference_upload",
          payload: {
            sellerId,
            mediaKind: "custom-order-reference",
            relativeKey,
            url,
          },
        }).catch((err) => {
          console.error("seller_media relational upsert failed (custom-order-reference):", err.message || err);
        });
      }

      res.json({ url });
    } catch (err) {
      console.error("custom-order-reference upload error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.post("/custom-order-requests", requireAppClient, customOrderLimiter, express.json({ limit: "256kb" }), async (req, res) => {
  try {
    const sellerId = String(req.body?.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });

    const profile = normalizeSellerPublicProfile(seller.profile, sellerId, seller.businessName);
    if (!profile.acceptsCustomOrders) {
      return res.status(403).json({ error: "This seller is not accepting custom orders" });
    }

    const buyerEmail = String(req.body?.buyerEmail || "").trim().toLowerCase();
    const buyerName = String(req.body?.buyerName || "").trim().slice(0, 120);
    const description = String(req.body?.description || "").trim();
    const referenceImageURLs = Array.isArray(req.body?.referenceImageURLs)
      ? req.body.referenceImageURLs.map((u) => String(u || "").trim()).filter(Boolean)
      : [];

    if (!isValidBuyerEmail(buyerEmail)) {
      return res.status(400).json({ error: "A valid email address is required" });
    }
    if (description.length < 10) {
      return res.status(400).json({ error: "Please describe your request in a bit more detail (at least 10 characters)." });
    }
    if (description.length > 8000) {
      return res.status(400).json({ error: "Description is too long" });
    }
    if (referenceImageURLs.length > 5) {
      return res.status(400).json({ error: "You can attach up to 5 reference images" });
    }
    for (const ref of referenceImageURLs) {
      if (!isAllowedCustomOrderReference(ref, sellerId)) {
        return res.status(400).json({ error: "Invalid reference image URL" });
      }
    }

    const entry = normalizeCustomOrderRequest({
      id: crypto.randomUUID(),
      sellerId,
      buyerName,
      buyerEmail,
      description,
      referenceImageURLs,
      createdAt: new Date().toISOString(),
      clientIp: clientIp(req),
      status: "pending",
      statusUpdatedAt: null,
    });

    const rows = loadCustomOrderRequestsFile();
    rows.unshift(entry);
    saveCustomOrderRequestsFile(rows);

    const sellerEmail = String(seller.email || "").trim().toLowerCase();
    const subject = `[TenBelow] Custom order request · ${profile.displayName}`;
    const imageList = referenceImageURLs
      .map((path) => {
        const abs = path.startsWith("http")
          ? path
          : `${String(BACKEND_URL).replace(/\/$/, "")}${path.startsWith("/") ? path : `/${path}`}`;
        return `<li><a href="${escapeHtml(abs)}">${escapeHtml(abs)}</a></li>`;
      })
      .join("");

    const htmlBody = `
<p><strong>New custom order request</strong></p>
<p><strong>Store:</strong> ${escapeHtml(profile.displayName)} (${escapeHtml(sellerId)})<br/>
<strong>From:</strong> ${escapeHtml(buyerName || "—")} &lt;${escapeHtml(buyerEmail)}&gt;</p>
<p><strong>Request:</strong></p>
<p style="white-space:pre-wrap;font-family:system-ui,sans-serif">${escapeHtml(description)}</p>
${imageList ? `<p><strong>Reference images</strong></p><ul>${imageList}</ul>` : ""}
<p style="font-size:12px;color:#555">Request id: ${escapeHtml(entry.id)}</p>
`;

    if (transactionalEmailConfigured()) {
      if (sellerEmail) {
        try {
          await sendTransactionalEmail({ to: sellerEmail, subject, html: htmlBody });
        } catch (emailErr) {
          console.error("custom order seller email error:", emailErr);
        }
      }
      if (CUSTOM_ORDER_ADMIN_EMAIL) {
        try {
          await sendTransactionalEmail({
            to: CUSTOM_ORDER_ADMIN_EMAIL,
            subject: `${subject} [admin copy]`,
            html: htmlBody,
          });
        } catch (emailErr) {
          console.error("custom order admin email error:", emailErr);
        }
      }
    } else {
      console.warn("custom order request stored but transactional email is not configured");
    }

    try {
      await notifyOrderStatusChanged({
        sellerId,
        title: "New custom order request",
        body: `${buyerName || "A buyer"} sent a custom order request for ${profile.displayName}.`,
      });
    } catch (pushErr) {
      console.warn("Custom order push notification error:", pushErr?.message || pushErr);
    }

    auditLog(
      auditContext(req, {
        action: "custom_order_request_created",
        customOrderRequestId: entry.id,
        sellerId,
      })
    );

    res.status(201).json({ ok: true, id: entry.id });
  } catch (err) {
    console.error("custom-order-requests error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-custom-orders/:sellerId", requireAppClient, requireAuthenticatedSeller, (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "Seller id is required" });
    if (req.auth.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_custom_order_requests_list",
        expectedSellerId: sellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Access denied" });
    }

    const rows = loadCustomOrderRequestsFile()
      .filter((r) => r.sellerId === sellerId)
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

    res.json({ requests: rows });
  } catch (err) {
    console.error("seller-custom-orders list error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.patch(
  "/custom-order-request/:requestId",
  requireAppClient,
  requireAuthenticatedSeller,
  sellerWriteLimiter,
  express.json({ limit: "32kb" }),
  async (req, res) => {
    try {
      const requestId = String(req.params.requestId || "").trim();
      if (!requestId) return res.status(400).json({ error: "Request id is required" });

      const status = String(req.body?.status || "").trim().toLowerCase();
      if (!["accepted", "declined", "pending"].includes(status)) {
        return res.status(400).json({ error: "status must be pending, accepted, or declined" });
      }

      const rows = loadCustomOrderRequestsFile();
      const idx = rows.findIndex((r) => r.id === requestId);
      if (idx < 0) return res.status(404).json({ error: "Request not found" });

      if (rows[idx].sellerId !== req.auth.sellerId) {
        auditOwnershipMismatch(req, {
          scope: "seller_custom_order_request_patch",
          customOrderRequestId: requestId,
          expectedSellerId: rows[idx].sellerId,
          actualSellerId: req.auth.sellerId || null,
        });
        return res.status(403).json({ error: "Access denied" });
      }

      const next = normalizeCustomOrderRequest({
        ...rows[idx],
        status,
        statusUpdatedAt: new Date().toISOString(),
      });
      rows[idx] = next;
      saveCustomOrderRequestsFile(rows);

      auditLog(
        auditContext(req, {
          action: "custom_order_request_status_updated",
          customOrderRequestId: requestId,
          status,
          sellerId: next.sellerId,
        })
      );

      if (next.buyerEmail && ["accepted", "declined"].includes(status)) {
        try {
          await notifyOrderStatusChanged({
            buyerEmail: next.buyerEmail,
            title: status === "accepted" ? "Custom order accepted" : "Custom order update",
            body: status === "accepted"
              ? "Your custom order request was accepted. Check TenBelow for the next steps."
              : "Your custom order request was declined. Open TenBelow for details.",
          });
        } catch (pushErr) {
          console.warn("Custom order status push notification error:", pushErr?.message || pushErr);
        }
      }

      res.json({ request: next });
    } catch (err) {
      console.error("custom-order-request patch error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.get(
  "/seller-products/:sellerId",
  sellerInventoryLimiter,
  requireAppClient,
  requireAuthenticatedSeller,
  async (req, res) => {
    try {
      const sellerId = String(req.params.sellerId || "").trim();
      if (!sellerId) {
        return res.status(400).json({ error: "sellerId is required" });
      }
      if (req.auth.sellerId !== sellerId) {
        auditOwnershipMismatch(req, {
          scope: "seller_products_list",
          expectedSellerId: sellerId,
          actualSellerId: req.auth.sellerId || null,
        });
        return res.status(403).json({ error: "Seller inventory access denied" });
      }

      const catalog = await fetchCatalog();
      const list = Array.isArray(catalog.products) ? catalog.products : [];
      const products = list
        .filter((product) => product.sellerId === sellerId)
        .map((product) => normalizeCatalogProduct(product))
        .filter((product) => String(product.approvalStatus || "").trim().toLowerCase() !== "archived");

      res.setHeader("Cache-Control", "no-store, max-age=0");
      res.json({ products });
    } catch (err) {
      console.error("seller-products list error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.put("/seller-products/:sellerId/:productId", sellerWriteLimiter, requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    const productId = String(req.params.productId || "").trim();
    if (!sellerId || !productId) {
      return res.status(400).json({ error: "sellerId and productId are required" });
    }
    if (req.auth.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_product_upsert",
        expectedSellerId: sellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller product update denied" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) {
      sellers[sellerId] = normalizeSellerRecord(
        {
          businessName: sellerId,
          profile: normalizeSellerPublicProfile({}, sellerId, sellerId),
        },
        sellerId
      );
      saveSellersFile(sellers);
    }

    const body = req.body || {};
    const catalog = await fetchCatalog();
    const orders = loadOrdersFile();
    const nowISO = new Date().toISOString();
    const requestedPriceCents = Math.max(0, asFiniteNumber(body.priceCents, 0));
    const existingProducts = Array.isArray(catalog.products) ? catalog.products : [];
    const existingIndex = existingProducts.findIndex((product) => product.id === productId);
    const existingProduct = existingIndex >= 0 ? existingProducts[existingIndex] : null;

    if (existingProduct && existingProduct.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_product_upsert_owner",
        expectedSellerId: existingProduct.sellerId || null,
        actualSellerId: sellerId,
        productId,
      });
      return res.status(403).json({ error: "Seller product update denied" });
    }

    if (
      requestedPriceCents >= PREMIUM_LISTING_MIN_PRICE_CENTS &&
      !sellerQualifiesForVerifiedMarketplaceAccess(sellerId, sellers, catalog.products || [], orders)
    ) {
      return res.status(403).json({
        error: "Seller verification is required before submitting premium-priced marketplace listings.",
      });
    }

    const nextProduct = normalizeCatalogProduct({
      id: productId,
      sellerId,
      name: body.name,
      priceCents: requestedPriceCents,
      previousPriceCents:
        existingProduct?.priceCents != null && existingProduct.priceCents !== requestedPriceCents
          ? existingProduct.priceCents
          : existingProduct?.previousPriceCents || null,
      category: body.category,
      imageURLs: body.imageURLs,
      demoVideoURL: body.demoVideoURL,
      productionPreviewURL: body.productionPreviewURL,
      material: body.material,
      durabilityNote: body.durabilityNote,
      careWarnings: body.careWarnings,
      shipsInMinDays: body.shipsInMinDays,
      shipsInMaxDays: body.shipsInMaxDays,
      isDrop: body.isDrop,
      isActive: false,
      isApproved: false,
      approvalStatus: "submitted",
      submittedAt: nowISO,
      reviewedAt: null,
      reviewNotes: "",
      rightsOwnershipType: body.rightsOwnershipType,
      rightsReferenceFlags: body.rightsReferenceFlags,
      rightsCertificationAccepted: body.rightsCertificationAccepted,
      rightsCertificationAcceptedAt: body.rightsCertificationAcceptedAt,
      requiresManualReview: body.requiresManualReview,
      reviewReason: body.reviewReason,
    });

    if (!nextProduct.name) {
      return res.status(400).json({ error: "Product name is required" });
    }

    const mergedProduct = existingIndex >= 0
      ? normalizeCatalogProduct({
          ...existingProducts[existingIndex],
          ...nextProduct,
          id: productId,
          sellerId,
        })
      : nextProduct;

    const updatedProducts = [...existingProducts];
    if (existingIndex >= 0) {
      updatedProducts[existingIndex] = mergedProduct;
    } else {
      updatedProducts.unshift(mergedProduct);
    }

    saveCatalog({
      version: catalog.version,
      products: updatedProducts,
    });

    auditLog(
      auditContext(req, {
        action: "seller_product_upsert",
        sellerId,
        productId,
      })
    );

    res.json({ product: mergedProduct });
  } catch (err) {
    console.error("update seller-product error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/seller-products/:sellerId/:productId/remove", sellerWriteLimiter, requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    const productId = String(req.params.productId || "").trim();
    const reason = String(req.body?.reason || "seller_removed").trim();
    if (!sellerId || !productId) {
      return res.status(400).json({ error: "sellerId and productId are required" });
    }
    if (req.auth.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_product_remove",
        expectedSellerId: sellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller product removal denied" });
    }

    const catalog = await fetchCatalog();
    const existingProducts = Array.isArray(catalog.products) ? catalog.products : [];
    const existingProduct = existingProducts.find((product) => product.id === productId);
    if (!existingProduct) {
      return res.status(404).json({ error: "Product not found" });
    }
    if (existingProduct.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_product_remove_owner",
        expectedSellerId: existingProduct.sellerId,
        actualSellerId: sellerId,
      });
      return res.status(403).json({ error: "Seller product removal denied" });
    }

    saveCatalog({
      version: catalog.version,
      products: existingProducts.filter((product) => product.id !== productId),
    });

    auditLog(
      auditContext(req, {
        action: "seller_product_remove",
        sellerId,
        productId,
        reason,
      })
    );

    res.json({ removed: true, productId, reason });
  } catch (err) {
    console.error("seller product remove error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/products/review-queue", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const catalog = await fetchCatalog();
    const sellers = await fetchSellers();
    const requestedStatus = String(req.query.status || "submitted").trim().toLowerCase();
    const products = Array.isArray(catalog.products) ? catalog.products : [];

    const queue = products
      .filter((product) => {
        const status = String(product.approvalStatus || "").trim().toLowerCase();
        if (!requestedStatus) return status !== "approved";
        return status === requestedStatus;
      })
      .map((product) => ({
        ...product,
        sellerDisplayName:
          sellers[product.sellerId]?.profile?.displayName ||
          sellers[product.sellerId]?.businessName ||
          product.sellerId,
      }))
      .sort((lhs, rhs) => {
        const lhsSubmittedAt = new Date(lhs.submittedAt || 0).getTime();
        const rhsSubmittedAt = new Date(rhs.submittedAt || 0).getTime();
        return rhsSubmittedAt - lhsSubmittedAt;
      });

    res.json({ products: queue });
  } catch (err) {
    console.error("review queue error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/sellers", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const catalog = await fetchCatalog();
    const sellers = await fetchSellers();
    const orders = loadOrdersFile();
    const products = Array.isArray(catalog.products)
      ? catalog.products.map((product) => normalizeCatalogProduct(product))
      : [];
    const profiles = buildSellerProfiles(sellers, products, orders);
    const productsBySeller = new Map();

    for (const product of products) {
      const sellerId = String(product.sellerId || "").trim();
      if (!sellerId) continue;
      const current = productsBySeller.get(sellerId) || [];
      current.push(product);
      productsBySeller.set(sellerId, current);
    }

    const directory = profiles.map((profile) => {
      const sellerProducts = productsBySeller.get(profile.id) || [];
      const counts = {
        submitted: 0,
        approved: 0,
        rejected: 0,
        archived: 0,
        other: 0,
      };

      for (const product of sellerProducts) {
        const status = String(product.approvalStatus || "submitted").trim().toLowerCase();
        if (Object.prototype.hasOwnProperty.call(counts, status)) {
          counts[status] += 1;
        } else {
          counts.other += 1;
        }
      }

      const latestSubmittedAt = sellerProducts.reduce((latest, product) => {
        const submittedAt = new Date(product.submittedAt || 0).getTime();
        return Math.max(latest, Number.isFinite(submittedAt) ? submittedAt : 0);
      }, 0);

      return {
        id: profile.id,
        displayName: profile.displayName,
        handle: profile.handle,
        email: sellers[profile.id]?.email || "",
        productCounts: counts,
        totalProducts: sellerProducts.length,
        totalValueCents: sellerProducts.reduce((sum, product) => sum + asFiniteNumber(product.priceCents, 0), 0),
        latestSubmittedAt: latestSubmittedAt ? new Date(latestSubmittedAt).toISOString() : null,
        membershipStatus: effectiveSellerMembershipStatus(sellers[profile.id] || {}).membershipStatus,
        isFoundingCreator: sellers[profile.id]?.isFoundingCreator === true,
        foundingCreatorAccessStartsAt: sellers[profile.id]?.foundingCreatorAccessStartsAt || null,
        foundingCreatorAccessEndsAt: sellers[profile.id]?.foundingCreatorAccessEndsAt || null,
        creatorBadge: sellers[profile.id]?.creatorBadge || "Founding Creator",
      };
    }).sort((lhs, rhs) => {
      const lhsTime = new Date(lhs.latestSubmittedAt || 0).getTime();
      const rhsTime = new Date(rhs.latestSubmittedAt || 0).getTime();
      if (lhsTime !== rhsTime) return rhsTime - lhsTime;
      return lhs.displayName.localeCompare(rhs.displayName);
    });

    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.json({ sellers: directory });
  } catch (err) {
    console.error("admin sellers directory error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/sellers/:sellerId/founding", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    return res.json({
      sellerId,
      ...sellerMembershipResponse(sellerId, seller),
    });
  } catch (err) {
    console.error("admin seller founding status error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put("/admin/sellers/:sellerId/founding", adminMutationLimiter, requireAdmin, express.json({ limit: "256kb" }), async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });

    const body = req.body || {};
    const normalizedStart = body.foundingCreatorAccessStartsAt === null
      ? null
      : asISODateOrNull(body.foundingCreatorAccessStartsAt);
    const normalizedEnd = body.foundingCreatorAccessEndsAt === null
      ? null
      : asISODateOrNull(body.foundingCreatorAccessEndsAt);
    if (body.foundingCreatorAccessStartsAt && !normalizedStart) {
      return res.status(400).json({ error: "foundingCreatorAccessStartsAt must be an ISO-8601 timestamp" });
    }
    if (body.foundingCreatorAccessEndsAt && !normalizedEnd) {
      return res.status(400).json({ error: "foundingCreatorAccessEndsAt must be an ISO-8601 timestamp" });
    }
    if (normalizedStart && normalizedEnd && new Date(normalizedEnd).getTime() < new Date(normalizedStart).getTime()) {
      return res.status(400).json({ error: "foundingCreatorAccessEndsAt must be after foundingCreatorAccessStartsAt" });
    }

    seller.isFoundingCreator = body.isFoundingCreator === true;
    seller.foundingCreatorAccessStartsAt = normalizedStart;
    seller.foundingCreatorAccessEndsAt = normalizedEnd;
    seller.creatorBadge = String(body.creatorBadge || seller.creatorBadge || "Founding Creator").trim() || "Founding Creator";
    sellers[sellerId] = normalizeSellerRecord(seller, sellerId);
    saveSellersFile(sellers);

    auditLog(auditContext(req, {
      action: "admin_seller_founding_updated",
      sellerId,
      isFoundingCreator: sellers[sellerId].isFoundingCreator === true,
      foundingCreatorAccessStartsAt: sellers[sellerId].foundingCreatorAccessStartsAt,
      foundingCreatorAccessEndsAt: sellers[sellerId].foundingCreatorAccessEndsAt,
      creatorBadge: sellers[sellerId].creatorBadge,
    }));

    return res.json({
      sellerId,
      ...sellerMembershipResponse(sellerId, sellers[sellerId]),
    });
  } catch (err) {
    console.error("admin seller founding update error:", err);
    res.status(500).json({ error: err.message });
  }
});

function adminAccountPageParams(req) {
  const page = Math.max(1, Math.floor(asFiniteNumber(req.query.page, 1)));
  const pageSize = Math.max(5, Math.min(50, Math.floor(asFiniteNumber(req.query.pageSize, 12))));
  const q = String(req.query.q || "").trim().toLowerCase();
  return { page, pageSize, q };
}

function sellerAccountActivity(sellerId, products, orders, exchangeRequests, customOrderRequests, productReviews) {
  const normalizedSellerId = String(sellerId || "").trim();
  const productCount = products.filter((product) => product.sellerId === normalizedSellerId).length;
  const orderCount = orders.filter((order) =>
    (order.shipments || []).some((shipment) => shipment.sellerId === normalizedSellerId)
  ).length;
  const exchangeCount = exchangeRequests.filter((request) =>
    String(request.sellerUserId || "").replace(/^seller:/, "").trim() === normalizedSellerId
  ).length;
  const customOrderCount = customOrderRequests.filter((request) => request.sellerId === normalizedSellerId).length;
  const reviewCount = productReviews.filter((review) => String(review.sellerId || "").trim() === normalizedSellerId).length;
  const blockers = [];
  if (productCount) blockers.push(`${productCount} product${productCount === 1 ? "" : "s"}`);
  if (orderCount) blockers.push(`${orderCount} order${orderCount === 1 ? "" : "s"}`);
  if (exchangeCount) blockers.push(`${exchangeCount} exchange${exchangeCount === 1 ? "" : "s"}`);
  if (customOrderCount) blockers.push(`${customOrderCount} custom request${customOrderCount === 1 ? "" : "s"}`);
  if (reviewCount) blockers.push(`${reviewCount} review${reviewCount === 1 ? "" : "s"}`);
  return { productCount, orderCount, exchangeCount, customOrderCount, reviewCount, canDelete: true, blockers };
}

function buyerAccountActivity(email, orders, exchangeRequests, customOrderRequests, productReviews) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  const buyerUserId = exchangeBuyerUserId(normalizedEmail);
  const orderCount = orders.filter((order) => String(order.buyerEmail || "").trim().toLowerCase() === normalizedEmail).length;
  const exchangeCount = exchangeRequests.filter((request) =>
    request.buyerUserId === buyerUserId || String(request.buyerEmail || "").trim().toLowerCase() === normalizedEmail
  ).length;
  const customOrderCount = customOrderRequests.filter((request) =>
    String(request.buyerEmail || "").trim().toLowerCase() === normalizedEmail
  ).length;
  const reviewCount = productReviews.filter((review) =>
    String(review.buyerEmail || "").trim().toLowerCase() === normalizedEmail
  ).length;
  const blockers = [];
  if (orderCount) blockers.push(`${orderCount} order${orderCount === 1 ? "" : "s"}`);
  if (exchangeCount) blockers.push(`${exchangeCount} exchange${exchangeCount === 1 ? "" : "s"}`);
  if (customOrderCount) blockers.push(`${customOrderCount} custom request${customOrderCount === 1 ? "" : "s"}`);
  if (reviewCount) blockers.push(`${reviewCount} review${reviewCount === 1 ? "" : "s"}`);
  return { orderCount, exchangeCount, customOrderCount, reviewCount, canDelete: true, blockers };
}

function paginateAdminAccounts(accounts, page, pageSize) {
  const total = accounts.length;
  const pages = Math.max(1, Math.ceil(total / pageSize) || 1);
  const safePage = Math.min(page, pages);
  const start = (safePage - 1) * pageSize;
  return { accounts: accounts.slice(start, start + pageSize), page: safePage, pageSize, total, pages };
}

app.get("/admin/accounts", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const kind = String(req.query.kind || "sellers").trim().toLowerCase();
    const { page, pageSize, q } = adminAccountPageParams(req);
    const catalog = await fetchCatalog();
    const products = Array.isArray(catalog.products)
      ? catalog.products.map((product) => normalizeCatalogProduct(product))
      : [];
    const orders = loadOrdersFile();
    const exchangeRequests = loadExchangeRequestsFile();
    const customOrderRequests = loadCustomOrderRequestsFile();
    const productReviews = loadProductReviewsFile();

    let accounts;
    if (kind === "buyers") {
      const buyers = loadBuyersFile();
      accounts = Object.entries(buyers).map(([email, buyer]) => ({
        kind: "buyer",
        id: email,
        email,
        displayName: buyer.fullName || email,
        createdAt: buyer.createdAt || null,
        updatedAt: buyer.updatedAt || null,
        activity: buyerAccountActivity(email, orders, exchangeRequests, customOrderRequests, productReviews),
      }));
    } else {
      const sellers = await fetchSellers();
      const profiles = buildSellerProfiles(sellers, products, orders);
      accounts = profiles.map((profile) => {
        const sellerRecord = sellers[profile.id] || {};
        return {
          kind: "seller",
          id: profile.id,
          email: sellerRecord.email || "",
          displayName: profile.displayName,
          handle: profile.handle,
          legalName: sellerRecord.legalName || "",
          shippingOrigin: sellerRecord.shippingOrigin || { country: "", state: "" },
          sellerAgreement: sellerRecord.sellerAgreement || {
            accepted: false,
            acceptedAt: null,
            version: null,
          },
          sellerPoliciesAcknowledged: sellerRecord.sellerPoliciesAcknowledged === true,
          createdAt: profile.joinedAt || null,
          updatedAt: sellerRecord.membership?.lastSyncedAt || null,
          activity: sellerAccountActivity(
            profile.id,
            products,
            orders,
            exchangeRequests,
            customOrderRequests,
            productReviews
          ),
        };
      });
    }

    if (q) {
      accounts = accounts.filter((account) =>
        [
          account.id,
          account.displayName,
          account.email,
          account.handle,
          account.legalName,
          account.shippingOrigin?.country,
          account.shippingOrigin?.state,
        ].some((value) => String(value || "").toLowerCase().includes(q))
      );
    }

    accounts.sort((lhs, rhs) => {
      const lhsActivity = Object.values(lhs.activity || {}).filter((value) => typeof value === "number").reduce((sum, value) => sum + value, 0);
      const rhsActivity = Object.values(rhs.activity || {}).filter((value) => typeof value === "number").reduce((sum, value) => sum + value, 0);
      if (lhsActivity !== rhsActivity) return lhsActivity - rhsActivity;
      return String(lhs.displayName || lhs.id).localeCompare(String(rhs.displayName || rhs.id));
    });

    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.json({ kind: kind === "buyers" ? "buyers" : "sellers", ...paginateAdminAccounts(accounts, page, pageSize) });
  } catch (err) {
    console.error("admin accounts fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.delete("/admin/accounts/:kind/:accountId", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const kind = String(req.params.kind || "").trim().toLowerCase();
    const accountId = String(req.params.accountId || "").trim();
    const orders = loadOrdersFile();
    const exchangeRequests = loadExchangeRequestsFile();
    const customOrderRequests = loadCustomOrderRequestsFile();
    const productReviews = loadProductReviewsFile();

    if (kind === "buyers") {
      const email = accountId.toLowerCase();
      const buyers = loadBuyersFile();
      if (!buyers[email]) return res.status(404).json({ error: "Buyer account not found" });
      const activity = buyerAccountActivity(email, orders, exchangeRequests, customOrderRequests, productReviews);
      delete buyers[email];
      saveBuyersFile(buyers);
      auditLog(auditContext(req, { action: "admin_buyer_account_deleted", buyerEmail: email, activity }));
      return res.json({ deleted: true, kind: "buyer", id: email, activity });
    }

    if (kind === "sellers") {
      const sellerId = accountId;
      const sellers = loadSellersFile();
      const catalog = await fetchCatalog();
      const products = Array.isArray(catalog.products)
        ? catalog.products.map((product) => normalizeCatalogProduct(product))
        : [];
      const sellerProducts = products.filter((product) => product.sellerId === sellerId);
      if (!sellers[sellerId] && sellerProducts.length === 0) {
        return res.status(404).json({ error: "Seller account not found" });
      }
      const activity = sellerAccountActivity(sellerId, products, orders, exchangeRequests, customOrderRequests, productReviews);
      if (sellerProducts.length > 0) {
        saveCatalog({
          version: catalog.version,
          products: products.filter((product) => product.sellerId !== sellerId),
        });
      }
      delete sellers[sellerId];
      saveSellersFile(sellers);
      auditLog(auditContext(req, {
        action: "admin_seller_account_deleted",
        sellerId,
        activity,
        deletedProductCount: sellerProducts.length,
      }));
      return res.json({
        deleted: true,
        kind: "seller",
        id: sellerId,
        activity,
        deletedProductCount: sellerProducts.length,
      });
    }

    return res.status(400).json({ error: "kind must be sellers or buyers" });
  } catch (err) {
    console.error("admin account delete error:", err);
    res.status(500).json({ error: err.message });
  }
});

async function pgTableCount(pool, tableName) {
  const { rows } = await pool.query(`SELECT COUNT(*)::int AS count FROM ${tableName}`);
  return rows?.[0]?.count ?? 0;
}

function expectedSupportMessageCount() {
  const orders = loadOrdersFile();
  const fromOrders = orders.reduce((sum, order) => {
    const supportRequests = Array.isArray(order?.supportRequests) ? order.supportRequests.length : 0;
    const orderMessages = Array.isArray(order?.orderMessages) ? order.orderMessages.length : 0;
    return sum + supportRequests + orderMessages;
  }, 0);

  const customOrderRequests = loadCustomOrderRequestsFile();
  const sellerInquiries = loadSellerInquiriesFile();
  const fromCustomRequests = customOrderRequests.length;
  const fromInquiries = sellerInquiries.reduce((sum, thread) => {
    const messages = Array.isArray(thread?.messages) ? thread.messages.length : 0;
    return sum + (messages || 1);
  }, 0);

  return fromOrders + fromCustomRequests + fromInquiries;
}

function expectedSellerMediaMinimumCount(catalogProducts = [], sellers = {}) {
  const fromProducts = catalogProducts.reduce((sum, product) => {
    const images = Array.isArray(product?.imageURLs) ? product.imageURLs.filter(Boolean).length : 0;
    const demo = product?.demoVideoURL ? 1 : 0;
    const preview = product?.productionPreviewURL ? 1 : 0;
    return sum + images + demo + preview;
  }, 0);

  const fromSellerProfiles = Object.values(sellers).reduce((sum, seller) => {
    const avatar = seller?.profile?.avatarURL ? 1 : 0;
    const banner = seller?.profile?.bannerURL ? 1 : 0;
    return sum + avatar + banner;
  }, 0);

  return fromProducts + fromSellerProfiles;
}

app.get("/admin/pg-relational-health", adminMutationLimiter, requireAdmin, async (req, res) => {
  if (!isPgEnabled()) {
    return res.status(503).json({
      ok: false,
      error: "DATABASE_URL is not configured",
    });
  }

  try {
    await ensureSchema();
    await ensureRelationalSchema();
    const pool = getPool();
    if (!pool) {
      return res.status(503).json({ ok: false, error: "Postgres pool unavailable" });
    }

    const sellers = loadSellersFile();
    const buyers = loadBuyersFile();
    const orders = loadOrdersFile();
    const drops = loadDropsFile();
    const exchanges = loadExchangeRequestsFile();
    const reviews = loadProductReviewsFile();
    const catalog = await fetchCatalog();
    const products = Array.isArray(catalog?.products) ? catalog.products : [];

    const expected = {
      sellers: Object.keys(sellers).length,
      creator_programs: Object.keys(sellers).length,
      buyers: Object.keys(buyers).length,
      products: products.length,
      orders: orders.length,
      weekly_drops: Object.keys(drops).length,
      exchanges: exchanges.length,
      reviews: reviews.length,
      support_messages: expectedSupportMessageCount(),
      seller_media_minimum: expectedSellerMediaMinimumCount(products, sellers),
    };

    const actual = {
      tb_documents: await pgTableCount(pool, "tb_documents"),
      sellers: await pgTableCount(pool, "sellers"),
      creator_programs: await pgTableCount(pool, "creator_programs"),
      buyers: await pgTableCount(pool, "buyers"),
      products: await pgTableCount(pool, "products"),
      orders: await pgTableCount(pool, "orders"),
      weekly_drops: await pgTableCount(pool, "weekly_drops"),
      exchanges: await pgTableCount(pool, "exchanges"),
      reviews: await pgTableCount(pool, "reviews"),
      support_messages: await pgTableCount(pool, "support_messages"),
      seller_media: await pgTableCount(pool, "seller_media"),
    };

    const checks = {
      sellers: actual.sellers === expected.sellers,
      creator_programs: actual.creator_programs === expected.creator_programs,
      buyers: actual.buyers === expected.buyers,
      products: actual.products === expected.products,
      orders: actual.orders === expected.orders,
      weekly_drops: actual.weekly_drops === expected.weekly_drops,
      exchanges: actual.exchanges === expected.exchanges,
      reviews: actual.reviews === expected.reviews,
      support_messages: actual.support_messages === expected.support_messages,
      seller_media_minimum: actual.seller_media >= expected.seller_media_minimum,
    };

    const ok = Object.values(checks).every(Boolean);
    return res.status(ok ? 200 : 503).json({
      ok,
      checks,
      expected,
      actual,
      note: "seller_media is validated as a minimum because runtime uploads can exceed base catalog/profile references.",
    });
  } catch (err) {
    console.error("admin pg relational health error:", err);
    return res.status(500).json({ ok: false, error: err.message });
  }
});

app.get("/admin/custom-order-requests", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const requestedStatus = String(req.query.status || "").trim().toLowerCase();
    const q = String(req.query.q || "").trim().toLowerCase();
    const sellers = await fetchSellers();
    let requests = loadCustomOrderRequestsFile()
      .filter((request) => !requestedStatus || request.status === requestedStatus)
      .map((request) => {
        const sellerRecord = sellers[request.sellerId] || {};
        const profile = normalizeSellerPublicProfile(
          sellerRecord.profile,
          request.sellerId,
          sellerRecord.businessName
        );
        return {
          ...request,
          sellerDisplayName: profile.displayName || sellerRecord.businessName || request.sellerId,
          sellerEmail: sellerRecord.email || "",
          sellerHandle: profile.handle || "",
        };
      });

    if (q) {
      requests = requests.filter((request) =>
        [
          request.id,
          request.sellerId,
          request.sellerDisplayName,
          request.sellerEmail,
          request.sellerHandle,
          request.buyerName,
          request.buyerEmail,
          request.description,
          request.status,
        ].some((value) => String(value || "").toLowerCase().includes(q))
      );
    }

    requests.sort((lhs, rhs) => {
      const lhsTime = new Date(lhs.createdAt || 0).getTime();
      const rhsTime = new Date(rhs.createdAt || 0).getTime();
      return rhsTime - lhsTime;
    });

    auditLog(
      auditContext(req, {
        action: "admin_custom_order_queue_view",
        status: requestedStatus || "all",
        resultCount: requests.length,
      })
    );

    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.json({ requests });
  } catch (err) {
    console.error("admin custom order requests error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/exchange-requests", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const requestedStatus = String(req.query.status || "").trim().toLowerCase();
    const orders = loadOrdersFile();
    const exchangeRequests = loadExchangeRequestsFile()
      .filter((request) => !requestedStatus || request.status === requestedStatus)
      .map((request) => buildAdminExchangeQueueRecord(request, orders))
      .sort((lhs, rhs) => {
        const lhsTime = new Date(lhs.updatedAt || lhs.createdAt || 0).getTime();
        const rhsTime = new Date(rhs.updatedAt || rhs.createdAt || 0).getTime();
        return rhsTime - lhsTime;
      });

    auditLog(
      auditContext(req, {
        action: "admin_exchange_queue_view",
        status: requestedStatus || "all",
      })
    );

    res.json({ exchangeRequests });
  } catch (err) {
    console.error("admin exchange queue error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/admin/exchange-requests/:id", adminMutationLimiter, requireAdmin, (req, res) => {
  try {
    const exchangeRequestId = String(req.params.id || "").trim();
    const orders = loadOrdersFile();
    const exchangeRequest = loadExchangeRequestsFile().find((request) => request.id === exchangeRequestId);
    if (!exchangeRequest) {
      return res.status(404).json({ error: "Exchange request not found" });
    }

    const order = orders.find((candidate) => candidate.id === exchangeRequest.orderId) || null;
    const resolved = order ? resolveOrderItem(order, exchangeRequest.orderItemId) : null;

    auditLog(
      auditContext(req, {
        action: "admin_exchange_detail_view",
        exchangeRequestId,
        orderId: exchangeRequest.orderId,
      })
    );

    res.json({
      exchangeRequest,
      order,
      orderItem: resolved?.item || null,
      shipment: resolved?.shipment || null,
    });
  } catch (err) {
    console.error("admin exchange detail error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/admin/products/:productId/review", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const productId = String(req.params.productId || "").trim();
    const decision = String(req.body?.decision || "").trim().toLowerCase();
    const notes = String(req.body?.notes || "").trim();

    if (!productId) {
      return res.status(400).json({ error: "productId is required" });
    }

    if (!["approve", "reject"].includes(decision)) {
      return res.status(400).json({ error: "decision must be approve or reject" });
    }

    const catalog = await fetchCatalog();
    const existingProducts = Array.isArray(catalog.products) ? catalog.products : [];
    const productIndex = existingProducts.findIndex((product) => product.id === productId);
    if (productIndex < 0) {
      return res.status(404).json({ error: "Product not found" });
    }

    const existingProduct = existingProducts[productIndex];
    const reviewedAt = new Date().toISOString();
    const reviewedProduct = normalizeCatalogProduct({
      ...existingProduct,
      isActive: decision === "approve",
      isApproved: decision === "approve",
      approvalStatus: decision === "approve" ? "approved" : "rejected",
      archivedAt: null,
      reviewedAt,
      reviewNotes: notes,
      submittedAt: existingProduct.submittedAt || reviewedAt,
    });

    const updatedProducts = [...existingProducts];
    updatedProducts[productIndex] = reviewedProduct;

    saveCatalog({
      version: catalog.version,
      products: updatedProducts,
    });

    auditLog(
      auditContext(req, {
        action: "admin_product_review",
        productId,
        decision,
      })
    );

    try {
      await notifyOrderStatusChanged({
        sellerId: reviewedProduct.sellerId,
        title: decision === "approve" ? "Product approved" : "Product needs updates",
        body: decision === "approve"
          ? `${reviewedProduct.name || "Your listing"} is now live on TenBelow.`
          : `${reviewedProduct.name || "Your listing"} was not approved. Check the admin notes and update it when ready.`,
      });
    } catch (pushErr) {
      console.warn("Product review push notification error:", pushErr?.message || pushErr);
    }

    res.json({ product: reviewedProduct });
  } catch (err) {
    console.error("product review error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/admin/products/:productId/archive", adminMutationLimiter, requireAdmin, async (req, res) => {
  try {
    const productId = String(req.params.productId || "").trim();
    const notes = String(req.body?.notes || "").trim();
    const now = new Date().toISOString();

    if (!productId) {
      return res.status(400).json({ error: "productId is required" });
    }

    const catalog = await fetchCatalog();
    const existingProducts = Array.isArray(catalog.products) ? catalog.products : [];
    const productIndex = existingProducts.findIndex((product) => product.id === productId);
    if (productIndex < 0) {
      return res.status(404).json({ error: "Product not found" });
    }

    const existingProduct = existingProducts[productIndex];
    const archivedProduct = normalizeCatalogProduct({
      ...existingProduct,
      isActive: false,
      isApproved: false,
      approvalStatus: "archived",
      archivedAt: now,
      reviewedAt: now,
      reviewNotes: notes || existingProduct.reviewNotes || "",
      submittedAt: existingProduct.submittedAt || now,
    });

    const updatedProducts = [...existingProducts];
    updatedProducts[productIndex] = archivedProduct;

    saveCatalog({
      version: catalog.version,
      products: updatedProducts,
    });

    auditLog(
      auditContext(req, {
        action: "admin_product_archive",
        productId,
      })
    );

    res.json({ product: archivedProduct });
  } catch (err) {
    console.error("product archive error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put(
  "/seller-media/:sellerId/:productId/:mediaKind/:slot",
  requireAppClient,
  requireAuthenticatedSeller,
  mediaUploadLimiter,
  sellerWriteLimiter,
  express.raw({ type: "*/*", limit: sellerMediaRawLimit }),
  async (req, res) => {
    try {
      const sellerId = sanitizePathSegment(req.params.sellerId, "seller");
      if (req.auth.sellerId !== sellerId) {
        auditOwnershipMismatch(req, {
          scope: "seller_media_upload",
          expectedSellerId: sellerId,
          actualSellerId: req.auth.sellerId || null,
        });
        return res.status(403).json({ error: "Seller media upload denied" });
      }
      const productId = sanitizePathSegment(req.params.productId, "product");
      const mediaKind = sanitizePathSegment(req.params.mediaKind, "media");
      const slot = sanitizePathSegment(req.params.slot, "0");
      const catalog = await fetchCatalog();
      const catalogProducts = Array.isArray(catalog.products) ? catalog.products : [];
      const existingProduct = catalogProducts.find((product) => String(product.id || "") === productId);
      if (existingProduct && String(existingProduct.sellerId || "").trim() !== sellerId) {
        auditOwnershipMismatch(req, {
          scope: "seller_media_upload_product_owner",
          expectedSellerId: existingProduct.sellerId || null,
          actualSellerId: sellerId,
          productId,
          mediaKind,
        });
        return res.status(403).json({ error: "Seller media upload denied" });
      }

      const body = req.body;
      const extension = sanitizeFileExtension(req.headers["x-file-extension"], "jpg");
      const contentType = String(req.headers["content-type"] || "").trim().toLowerCase();
      const mediaValidation = validateSellerMediaUpload({
        buffer: body,
        contentType,
        fileExtension: extension,
        mediaKind,
      });
      if (!mediaValidation.ok) {
        recordSecurityAudit(req, {
          action: "media_upload_rejected",
          scope: "seller_media_upload",
          reason: mediaValidation.error,
          sellerId,
          productId,
          mediaKind,
        });
        return res.status(400).json({ error: mediaValidation.error });
      }

      const filename = `${mediaKind}-${slot}.${mediaValidation.extension}`;
      const relativeKey = `${sellerId}/${productId}/${filename}`;
      const { url } = await storeMediaBytes({
        relativeKey,
        buffer: body,
        contentType: mediaValidation.contentType,
      });
      const version = Date.now();
      const withQuery = url.includes("?") ? `${url}&v=${version}` : `${url}?v=${version}`;
      const storageProvider = String(process.env.S3_MEDIA_BUCKET || "").trim() ? "object_storage" : "local_disk";
      if (isPgEnabled()) {
        void recordSellerMediaUpload({
          id: `${productId}:${mediaKind}:${slot}`,
          sellerId,
          productId,
          mediaKind,
          url: withQuery,
          storageProvider,
          source: "seller_media_upload",
          payload: {
            sellerId,
            productId,
            mediaKind,
            slot,
            relativeKey,
            url: withQuery,
          },
        }).catch((err) => {
          console.error("seller_media relational upsert failed:", err.message || err);
        });
      }

      res.json({
        url: withQuery,
      });
    } catch (err) {
      console.error("seller-media upload error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.put(
  "/admin/media/marketing/:assetId/:mediaKind",
  adminMutationLimiter,
  requireAdmin,
  mediaUploadLimiter,
  express.raw({ type: "*/*", limit: sellerMediaRawLimit }),
  async (req, res) => {
    try {
      const assetId = sanitizePathSegment(req.params.assetId, "asset");
      const requestedKind = String(req.params.mediaKind || "").trim().toLowerCase();
      const mediaKind = requestedKind === "video" ? "demo-video" : "image";
      const extension = sanitizeFileExtension(req.headers["x-file-extension"], mediaKind === "image" ? "jpg" : "mp4");
      const contentType = String(req.headers["content-type"] || "").trim().toLowerCase();
      const mediaValidation = validateSellerMediaUpload({
        buffer: req.body,
        contentType,
        fileExtension: extension,
        mediaKind,
      });
      if (!mediaValidation.ok) {
        return res.status(400).json({ error: mediaValidation.error });
      }

      const filename = `marketing-${mediaKind}.${mediaValidation.extension}`;
      const relativeKey = `marketing-assets/${assetId}/${filename}`;
      const { url } = await storeMediaBytes({
        relativeKey,
        buffer: req.body,
        contentType: mediaValidation.contentType,
      });
      const version = Date.now();
      const withQuery = url.includes("?") ? `${url}&v=${version}` : `${url}?v=${version}`;
      const storageProvider = String(process.env.S3_MEDIA_BUCKET || "").trim() ? "object_storage" : "local_disk";
      if (isPgEnabled()) {
        void recordSellerMediaUpload({
          id: `marketing:${assetId}:${requestedKind || "image"}`,
          sellerId: null,
          productId: null,
          mediaKind: requestedKind === "video" ? "marketing-video" : "marketing-image",
          url: withQuery,
          storageProvider,
          source: "marketing_asset_upload",
          payload: {
            assetId,
            relativeKey,
            mediaKind: requestedKind,
            url: withQuery,
          },
        }).catch((err) => {
          console.error("seller_media relational upsert failed (marketing):", err.message || err);
        });
      }

      res.json({ url: withQuery });
    } catch (err) {
      console.error("marketing asset upload error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.get("/seller-membership-status/:sellerId", requireAppClient, requireAuthenticatedSeller, (req, res) => {
  const requestedSellerId = String(req.params.sellerId || "").trim();
  if (req.auth.sellerId !== requestedSellerId) {
    auditOwnershipMismatch(req, {
      scope: "seller_membership_status",
      expectedSellerId: requestedSellerId,
      actualSellerId: req.auth.sellerId || null,
    });
    return res.status(403).json({ error: "Seller membership access denied" });
  }
  const sellers = loadSellersFile();
  const seller = sellers[requestedSellerId];
  if (!seller) return res.status(404).json({ error: "Seller not found" });
  res.json(sellerMembershipResponse(requestedSellerId, seller));
});

app.post("/create-seller-membership-checkout", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const sellerId = String(req.body.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });
    if (req.auth.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "seller_membership_checkout",
        expectedSellerId: sellerId,
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller membership checkout denied" });
    }
    const sellers = loadSellersFile();
    if (!sellers[sellerId]) return res.status(404).json({ error: "Seller not found" });

    const priceId = String(process.env.STRIPE_SELLER_MEMBERSHIP_PRICE_ID || "").trim();
    if (!priceId) {
      return res.status(503).json({
        error:
          "Stripe seller membership is not configured. Set STRIPE_SELLER_MEMBERSHIP_PRICE_ID to a recurring Price id.",
      });
    }

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${BACKEND_URL}/seller-membership-checkout-success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${BACKEND_URL}/seller-membership-checkout-cancel`,
      client_reference_id: sellerId,
      metadata: { sellerId },
      subscription_data: {
        metadata: { sellerId },
      },
    });

    if (!session.url) {
      return res.status(500).json({ error: "Stripe did not return a checkout URL." });
    }
    res.json({ url: session.url });
  } catch (err) {
    console.error("create-seller-membership-checkout error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-membership-checkout-success", (req, res) => {
  res
    .type("html")
    .send(
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/></head><body style=\"font-family:system-ui;padding:24px;\"><p>Payment complete. Return to the TenBelow app — your membership updates in a few seconds.</p></body></html>"
    );
});

app.get("/seller-membership-checkout-cancel", (req, res) => {
  res
    .type("html")
    .send(
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/></head><body style=\"font-family:system-ui;padding:24px;\"><p>Checkout canceled. You can close this page and return to TenBelow.</p></body></html>"
    );
});

app.post("/seller-membership-sync", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const { sellerId, productId, isActive, expiresAt, transactionId, originalTransactionId } = req.body;
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });
    if (req.auth.sellerId !== String(sellerId).trim()) {
      auditOwnershipMismatch(req, {
        scope: "seller_membership_sync",
        expectedSellerId: String(sellerId).trim(),
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller membership sync denied" });
    }

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });

    const existingMembership = normalizeMembership(seller.membership);
    if (
      existingMembership.source === "stripe" &&
      existingMembership.hasActiveSubscription === true &&
      isActive === false
    ) {
      return res.json(sellerMembershipResponse(sellerId, seller));
    }

    const effectiveProductId = productId || seller.membership?.productId || SELLER_SUBSCRIPTION_PRODUCT_ID;
    const storedOriginal = seller.membership?.originalTransactionId || null;
    const bodyOriginal =
      originalTransactionId != null && String(originalTransactionId).trim()
        ? String(originalTransactionId).trim()
        : null;
    const originalTx = bodyOriginal || storedOriginal;

    if (isAppStoreVerificationConfigured()) {
      if (originalTx) {
        try {
          const apple = await verifySubscriptionWithAppStore(originalTx, effectiveProductId);
          seller.membership = normalizeMembership({
            ...seller.membership,
            productId: apple.productId || effectiveProductId,
            hasActiveSubscription: apple.hasActiveSubscription,
            expiresAt: apple.expiresAt,
            lastSyncedAt: new Date().toISOString(),
            source: "app_store_verified",
            transactionId: apple.transactionId || transactionId || seller.membership?.transactionId || null,
            originalTransactionId: apple.originalTransactionId || originalTx,
          });
        } catch (err) {
          console.error("seller-membership-sync App Store verification failed:", err);
          const code = err.httpStatusCode;
          const msg = err.message || "App Store verification failed";
          if (code === 404) {
            return res.status(404).json({ error: "No subscription found for this original transaction id." });
          }
          return res.status(502).json({ error: msg });
        }
      } else {
        if (isActive === true) {
          return res.status(400).json({
            error: "originalTransactionId is required so the server can verify the subscription with Apple.",
          });
        }
        seller.membership = normalizeMembership({
          ...seller.membership,
          productId: effectiveProductId,
          hasActiveSubscription: false,
          expiresAt: null,
          lastSyncedAt: new Date().toISOString(),
          source: "app_store",
          transactionId: null,
          originalTransactionId: null,
        });
      }
    } else {
      console.warn(
        "seller-membership-sync: App Store Server API env not set; refusing active membership sync until APP_STORE_* verification is configured."
      );
      if (isActive === true) {
        return res.status(503).json({
          error:
            "Seller membership verification is temporarily unavailable. Configure App Store Server API credentials before syncing active memberships.",
        });
      }
      seller.membership = normalizeMembership({
        ...seller.membership,
        productId: effectiveProductId,
        hasActiveSubscription: false,
        expiresAt: null,
        lastSyncedAt: new Date().toISOString(),
        source: "app_store",
        transactionId: null,
        originalTransactionId: bodyOriginal || storedOriginal,
      });
    }

    sellers[sellerId] = seller;
    saveSellersFile(sellers);
    res.json(sellerMembershipResponse(sellerId, seller));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Weekly Drop System
// ---------------------------------------------------------------------------

const DROP_MIN_PRICE_CENTS = 1001;
const DROP_MAX_SLOTS_PER_SELLER = 4;

function loadDropsFile() {
  const cached = getCachedDocument("drops");
  if (cached !== undefined) {
    return cached && typeof cached === "object" ? cached : {};
  }
  try {
    const parsed = JSON.parse(readFileSync(DROPS_PATH, "utf-8"));
    const obj = parsed && typeof parsed === "object" ? parsed : {};
    setCachedDocument("drops", obj);
    return obj;
  } catch {
    setCachedDocument("drops", {});
    return {};
  }
}

function saveDropsFile(drops) {
  const normalized = Object.fromEntries(
    Object.entries(drops || {}).map(([weekId, weekData]) => [
      weekId,
      {
        startsAt: weekData?.startsAt || null,
        endsAt: weekData?.endsAt || null,
        entries: dropEntriesForWeek(weekData),
      },
    ])
  );
  writeManagedJSON("drops", normalized);
}

function normalizeDropEntry(entry = {}) {
  return {
    productId: String(entry.productId || entry.id || "").trim(),
    sellerId: String(entry.sellerId || "").trim(),
    submittedAt: entry.submittedAt || new Date().toISOString(),
  };
}

function dropEntriesForWeek(weekData = {}) {
  const rawEntries = Array.isArray(weekData.entries)
    ? weekData.entries
    : Array.isArray(weekData.products)
      ? weekData.products
      : [];

  return rawEntries
    .map((entry) => normalizeDropEntry(entry))
    .filter((entry) => entry.productId && entry.sellerId);
}

function buildDropProduct(product = {}, entry = {}, index = 0) {
  const normalizedProduct = normalizeCatalogProduct(product);
  return {
    id: normalizedProduct.id,
    sellerId: normalizedProduct.sellerId,
    name: normalizedProduct.name,
    priceCents: normalizedProduct.priceCents,
    previousPriceCents: normalizedProduct.previousPriceCents,
    category: normalizedProduct.category,
    imageURLs: normalizedProduct.imageURLs,
    demoVideoURL: normalizedProduct.demoVideoURL,
    productionPreviewURL: normalizedProduct.productionPreviewURL,
    headline: normalizedProduct.dropHeadline || "",
    story: normalizedProduct.dropStory || "",
    bestUseCase: normalizedProduct.dropBestUseCase || "",
    material: normalizedProduct.material,
    durabilityNote: normalizedProduct.durabilityNote,
    careWarnings: normalizedProduct.careWarnings,
    shipsInMinDays: normalizedProduct.shipsInMinDays,
    shipsInMaxDays: normalizedProduct.shipsInMaxDays,
    approvalStatus: normalizedProduct.approvalStatus || "submitted",
    reviewNotes: normalizedProduct.reviewNotes || "",
    reviewedAt: normalizedProduct.reviewedAt || null,
    submittedAt: entry.submittedAt || new Date().toISOString(),
    slotNumber: index + 1,
    rightsOwnershipType: normalizedProduct.rightsOwnershipType || null,
    rightsReferenceFlags: normalizedProduct.rightsReferenceFlags || [],
    rightsCertificationAccepted: normalizedProduct.rightsCertificationAccepted === true,
    rightsCertificationAcceptedAt: normalizedProduct.rightsCertificationAcceptedAt || null,
    requiresManualReview: normalizedProduct.requiresManualReview === true,
    reviewReason: normalizedProduct.reviewReason || null,
  };
}

function resolveDropProducts(weekData = {}, catalog = {}) {
  const catalogProducts = Array.isArray(catalog.products) ? catalog.products : [];
  const productsById = new Map(
    catalogProducts.map((product) => {
      const normalizedProduct = normalizeCatalogProduct(product);
      return [normalizedProduct.id, normalizedProduct];
    })
  );

  return dropEntriesForWeek(weekData)
    .map((entry, index) => {
      const product = productsById.get(entry.productId);
      if (
        !product ||
        product.sellerId !== entry.sellerId ||
        product.isDrop !== true ||
        product.isApproved !== true ||
        String(product.approvalStatus || "").trim().toLowerCase() !== "approved"
      ) {
        return null;
      }
      return buildDropProduct(product, entry, index);
    })
    .filter(Boolean);
}

const DROP_TIME_ZONE = "America/New_York";
const DROP_WEEKDAY_INDEX = {
  Sun: 0,
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
};

function dropTimeParts(date, timeZone = DROP_TIME_ZONE) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
    hour12: false,
  });
  const parts = Object.fromEntries(
    formatter
      .formatToParts(date)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value])
  );
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
    weekday: DROP_WEEKDAY_INDEX[parts.weekday] ?? 0,
  };
}

function dropTimeOffsetMs(date, timeZone = DROP_TIME_ZONE) {
  const parts = dropTimeParts(date, timeZone);
  const asUTC = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
  );
  return asUTC - date.getTime();
}

function dropTimeToUTC(
  { year, month, day, hour = 0, minute = 0, second = 0, millisecond = 0 },
  timeZone = DROP_TIME_ZONE
) {
  const utcGuess = new Date(Date.UTC(year, month - 1, day, hour, minute, second, millisecond));
  const initialOffset = dropTimeOffsetMs(utcGuess, timeZone);
  const candidate = new Date(utcGuess.getTime() - initialOffset);
  const correctedOffset = dropTimeOffsetMs(candidate, timeZone);
  return new Date(utcGuess.getTime() - correctedOffset);
}

function addDropZoneDays(anchorDate, dayOffset, timeZone = DROP_TIME_ZONE) {
  const parts = dropTimeParts(anchorDate, timeZone);
  return dropTimeToUTC(
    {
      year: parts.year,
      month: parts.month,
      day: parts.day + dayOffset,
    },
    timeZone
  );
}

function dropCycleWindowForFridayStart(fridayStart) {
  const fridayParts = dropTimeParts(fridayStart, DROP_TIME_ZONE);
  const submissionStartsAt = dropTimeToUTC({
    year: fridayParts.year,
    month: fridayParts.month,
    day: fridayParts.day - 1,
    hour: 17,
  });
  const submissionEndsAt = dropTimeToUTC({
    year: fridayParts.year,
    month: fridayParts.month,
    day: fridayParts.day - 1,
    hour: 23,
    minute: 59,
    second: 59,
    millisecond: 999,
  });
  const endsAt = dropTimeToUTC({
    year: fridayParts.year,
    month: fridayParts.month,
    day: fridayParts.day + 2,
    hour: 23,
    minute: 59,
    second: 59,
    millisecond: 999,
  });

  const isoYear = fridayStart.getUTCFullYear();
  const dayOfYear = Math.floor((fridayStart - new Date(Date.UTC(isoYear, 0, 1))) / 86400000);
  const weekNum = Math.ceil((dayOfYear + 1) / 7);

  return {
    weekId: `${isoYear}-W${String(weekNum).padStart(2, "0")}`,
    submissionStartsAt,
    submissionEndsAt,
    startsAt: fridayStart,
    endsAt,
  };
}

function getRelevantDropFridayStart(referenceDate = new Date()) {
  const nowParts = dropTimeParts(referenceDate, DROP_TIME_ZONE);
  const todayStart = dropTimeToUTC({
    year: nowParts.year,
    month: nowParts.month,
    day: nowParts.day,
  });
  const daysSinceFriday = (nowParts.weekday - 5 + 7) % 7;
  const mostRecentFridayStart = addDropZoneDays(todayStart, -daysSinceFriday, DROP_TIME_ZONE);
  const currentCycle = dropCycleWindowForFridayStart(mostRecentFridayStart);

  if (referenceDate >= currentCycle.submissionStartsAt && referenceDate <= currentCycle.endsAt) {
    return mostRecentFridayStart;
  }

  return addDropZoneDays(mostRecentFridayStart, 7, DROP_TIME_ZONE);
}

function getCurrentDropWindow() {
  const now = new Date();
  const fridayStart = getRelevantDropFridayStart(now);
  const cycle = dropCycleWindowForFridayStart(fridayStart);
  const isActive = now >= cycle.startsAt && now <= cycle.endsAt;

  let nextDropAt = null;
  if (!isActive) {
    nextDropAt = now < cycle.startsAt
      ? cycle.startsAt.toISOString()
      : dropCycleWindowForFridayStart(addDropZoneDays(fridayStart, 7, DROP_TIME_ZONE)).startsAt.toISOString();
  }

  return {
    weekId: cycle.weekId,
    startsAt: cycle.startsAt.toISOString(),
    endsAt: cycle.endsAt.toISOString(),
    isActive,
    nextDropAt,
  };
}

function getCurrentDropSubmissionWindow() {
  const now = new Date();
  const fridayStart = getRelevantDropFridayStart(now);
  const cycle = dropCycleWindowForFridayStart(fridayStart);
  const isActive = now >= cycle.submissionStartsAt && now <= cycle.submissionEndsAt;

  let nextDropAt = null;
  if (!isActive) {
    if (now < cycle.submissionStartsAt) {
      nextDropAt = cycle.submissionStartsAt.toISOString();
    } else {
      nextDropAt = dropCycleWindowForFridayStart(
        addDropZoneDays(fridayStart, 7, DROP_TIME_ZONE)
      ).submissionStartsAt.toISOString();
    }
  }

  return {
    weekId: cycle.weekId,
    startsAt: cycle.submissionStartsAt.toISOString(),
    endsAt: cycle.submissionEndsAt.toISOString(),
    liveStartsAt: cycle.startsAt.toISOString(),
    liveEndsAt: cycle.endsAt.toISOString(),
    isActive,
    nextDropAt,
  };
}

/**
 * Which Friday's `drops[weekId]` bucket should seller "my submissions" read from.
 *
 * `getRelevantDropFridayStart` advances to the *next* Friday once the current cycle's
 * weekend ends (Sunday night). The new `weekId` often has no rows yet Mon–Wed, so the
 * hub looks empty. While we're after the prior weekend and before the next Thursday
 * 5pm submission window, map sellers back to the **previous** Friday's bucket.
 *
 * Thursday is handled in `GET /drop/my-submissions`: if the mapped week is empty,
 * fall back to the prior week when that gap condition still applies (covers Thu AM).
 */
function getFridayStartForStagedDropLineup(referenceDate = new Date()) {
  const standard = getRelevantDropFridayStart(referenceDate);
  const standardCycle = dropCycleWindowForFridayStart(standard);
  const priorFriday = addDropZoneDays(standard, -7, DROP_TIME_ZONE);
  const priorCycle = dropCycleWindowForFridayStart(priorFriday);

  if (referenceDate <= priorCycle.endsAt || referenceDate >= standardCycle.submissionStartsAt) {
    return standard;
  }

  const parts = dropTimeParts(referenceDate, DROP_TIME_ZONE);
  if (parts.weekday >= 1 && parts.weekday <= 3) {
    return priorFriday;
  }

  return standard;
}

app.post("/drop/submit", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const {
      productId,
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      productionPreviewURL,
      headline,
      story,
      bestUseCase,
      material,
      durabilityNote,
      careWarnings,
      shipsInMinDays,
      shipsInMaxDays,
      rightsOwnershipType,
      rightsReferenceFlags,
      rightsCertificationAccepted,
      rightsCertificationAcceptedAt,
      requiresManualReview,
      reviewReason,
    } = req.body;

    if (!sellerId || !name || !priceCents) {
      return res.status(400).json({ error: "sellerId, name, and priceCents are required" });
    }
    if (req.auth.sellerId !== String(sellerId).trim()) {
      auditOwnershipMismatch(req, {
        scope: "drop_submit",
        expectedSellerId: String(sellerId).trim(),
        actualSellerId: req.auth.sellerId || null,
      });
      return res.status(403).json({ error: "Seller drop submission denied" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) {
      return res.status(404).json({ error: "Seller not found. Create an account first." });
    }

    const catalog = await fetchCatalog();

    if (!effectiveSellerMembershipStatus(sellers[sellerId]).hasActiveSubscription) {
      return res.status(403).json({
        error: "An active seller membership is required before submitting Weekly Drop products.",
      });
    }

    if (priceCents < DROP_MIN_PRICE_CENTS) {
      return res.status(400).json({ error: `Drop products must be over $10 (got $${(priceCents / 100).toFixed(2)})` });
    }

    const window = getCurrentDropSubmissionWindow();
    if (!window.isActive) {
      return res.status(400).json({
        error: "Drop submissions are only open Thursday from 5:00 PM through 11:59 PM ET.",
        nextDropAt: window.nextDropAt,
      });
    }

    const drops = loadDropsFile();
    if (!drops[window.weekId]) {
      drops[window.weekId] = { startsAt: window.startsAt, endsAt: window.endsAt, entries: [] };
    }

    const weekData = drops[window.weekId];
    const weekEntries = dropEntriesForWeek(weekData);
    const sellerEntries = weekEntries.filter((entry) => entry.sellerId === sellerId);
    if (sellerEntries.length >= DROP_MAX_SLOTS_PER_SELLER) {
      return res.status(400).json({ error: `You've reached the maximum of ${DROP_MAX_SLOTS_PER_SELLER} drop products this week` });
    }

    const catalogProducts = Array.isArray(catalog.products) ? catalog.products.map((product) => normalizeCatalogProduct(product)) : [];
    const resolvedProductId = sanitizePathSegment(productId || `drop-${crypto.randomUUID()}`, `drop-${crypto.randomUUID()}`);
    const existingProductIndex = catalogProducts.findIndex((product) => product.id === resolvedProductId);
    const existingProduct = existingProductIndex >= 0 ? catalogProducts[existingProductIndex] : null;
    if (existingProduct && existingProduct.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "drop_submit_existing_product",
        expectedSellerId: sellerId,
        actualSellerId: existingProduct.sellerId || null,
        productId: resolvedProductId,
      });
      return res.status(403).json({ error: "That product belongs to another seller." });
    }

    if (weekEntries.some((entry) => entry.productId === resolvedProductId)) {
      return res.status(409).json({ error: "This product is already in the current Weekly Drop." });
    }

    const product = normalizeCatalogProduct({
      ...existingProduct,
      id: resolvedProductId,
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      productionPreviewURL,
      dropHeadline: headline || "",
      dropStory: story || "",
      dropBestUseCase: bestUseCase || "",
      previousPriceCents:
        existingProduct?.priceCents != null && existingProduct.priceCents !== priceCents
          ? existingProduct.priceCents
          : existingProduct?.previousPriceCents || null,
      material: material || "PLA+",
      durabilityNote: durabilityNote || "",
      careWarnings: careWarnings || [],
      shipsInMinDays: shipsInMinDays || 3,
      shipsInMaxDays: shipsInMaxDays || 7,
      isDrop: true,
      isActive: false,
      isApproved: false,
      approvalStatus: "submitted",
      submittedAt: existingProduct?.submittedAt || new Date().toISOString(),
      reviewedAt: null,
      reviewNotes: "",
      rightsOwnershipType,
      rightsReferenceFlags,
      rightsCertificationAccepted,
      rightsCertificationAcceptedAt,
      requiresManualReview,
      reviewReason,
    });

    const productIndex = catalogProducts.findIndex((catalogProduct) => catalogProduct.id === product.id);
    if (productIndex >= 0) {
      catalogProducts[productIndex] = product;
    } else {
      catalogProducts.unshift(product);
    }
    saveCatalog({ ...catalog, products: catalogProducts });

    const entry = normalizeDropEntry({
      productId: product.id,
      sellerId,
      submittedAt: product.submittedAt || new Date().toISOString(),
    });
    const nextEntries = [...weekEntries, entry];
    weekData.entries = nextEntries;
    saveDropsFile(drops);

    res.json(buildDropProduct(product, entry, nextEntries.findIndex((currentEntry) => currentEntry.productId === product.id)));
  } catch (err) {
    console.error("drop/submit error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put("/drop/submission/:productId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  try {
    const { productId } = req.params;
    const {
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      productionPreviewURL,
      headline,
      story,
      bestUseCase,
      material,
      durabilityNote,
      careWarnings,
      shipsInMinDays,
      shipsInMaxDays,
      rightsOwnershipType,
      rightsReferenceFlags,
      rightsCertificationAccepted,
      rightsCertificationAcceptedAt,
      requiresManualReview,
      reviewReason,
    } = req.body;

    if (!sellerId || !name || !priceCents) {
      return res.status(400).json({ error: "sellerId, name, and priceCents are required" });
    }
    if (req.auth.sellerId !== String(sellerId).trim()) {
      auditOwnershipMismatch(req, {
        scope: "drop_update",
        expectedSellerId: String(sellerId).trim(),
        actualSellerId: req.auth.sellerId || null,
        productId,
      });
      return res.status(403).json({ error: "Seller drop update denied" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) {
      return res.status(404).json({ error: "Seller not found. Create an account first." });
    }

    const catalog = await fetchCatalog();

    if (!effectiveSellerMembershipStatus(sellers[sellerId]).hasActiveSubscription) {
      return res.status(403).json({
        error: "An active seller membership is required before submitting Weekly Drop products.",
      });
    }

    if (priceCents < DROP_MIN_PRICE_CENTS) {
      return res.status(400).json({ error: `Drop products must be over $10 (got $${(priceCents / 100).toFixed(2)})` });
    }

    const window = getCurrentDropSubmissionWindow();
    if (!window.isActive) {
      return res.status(400).json({
        error: "Drop submissions are only open Thursday from 5:00 PM through 11:59 PM ET.",
        nextDropAt: window.nextDropAt,
      });
    }

    const drops = loadDropsFile();
    const weekData = drops[window.weekId];
    if (!weekData) {
      return res.status(404).json({ error: "No drop data for this week" });
    }

    const weekEntries = dropEntriesForWeek(weekData);
    const entry = weekEntries.find((currentEntry) => currentEntry.productId === productId);
    if (!entry) {
      return res.status(404).json({ error: "Product not found in this week's drop" });
    }

    if (entry.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "drop_update_entry_owner",
        expectedSellerId: sellerId,
        actualSellerId: entry.sellerId || null,
        productId,
      });
      return res.status(403).json({ error: "You can only edit your own drop products." });
    }

    const catalogProducts = Array.isArray(catalog.products) ? catalog.products.map((product) => normalizeCatalogProduct(product)) : [];
    const existingProductIndex = catalogProducts.findIndex((product) => product.id === productId);
    if (existingProductIndex === -1) {
      return res.status(404).json({ error: "Drop product not found in catalog." });
    }
    const existingProduct = catalogProducts[existingProductIndex];
    if (existingProduct.sellerId !== sellerId) {
      auditOwnershipMismatch(req, {
        scope: "drop_update_catalog_owner",
        expectedSellerId: existingProduct.sellerId || null,
        actualSellerId: sellerId,
        productId,
      });
      return res.status(403).json({ error: "Seller drop update denied" });
    }

    const updatedProduct = normalizeCatalogProduct({
      ...existingProduct,
      id: productId,
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      productionPreviewURL,
      dropHeadline: headline || "",
      dropStory: story || "",
      dropBestUseCase: bestUseCase || "",
      previousPriceCents:
        existingProduct.priceCents != null && existingProduct.priceCents !== priceCents
          ? existingProduct.priceCents
          : existingProduct.previousPriceCents || null,
      material: material || "PLA+",
      durabilityNote: durabilityNote || "",
      careWarnings: careWarnings || [],
      shipsInMinDays: shipsInMinDays || 3,
      shipsInMaxDays: shipsInMaxDays || 7,
      isDrop: true,
      isActive: false,
      isApproved: false,
      approvalStatus: "submitted",
      submittedAt: existingProduct?.submittedAt || new Date().toISOString(),
      reviewedAt: null,
      reviewNotes: "",
      rightsOwnershipType,
      rightsReferenceFlags,
      rightsCertificationAccepted,
      rightsCertificationAcceptedAt,
      requiresManualReview,
      reviewReason,
    });

    catalogProducts[existingProductIndex] = updatedProduct;
    saveCatalog({ ...catalog, products: catalogProducts });

    weekData.entries = weekEntries;
    saveDropsFile(drops);

    res.json(buildDropProduct(updatedProduct, entry, weekEntries.findIndex((currentEntry) => currentEntry.productId === productId)));
  } catch (err) {
    console.error("drop/submission update error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/drop/current", publicReadLimiter, async (req, res) => {
  try {
    const window = getCurrentDropWindow();
    const drops = loadDropsFile();
    const weekData = drops[window.weekId];
    const catalog = await fetchCatalog();
    const products = resolveDropProducts(weekData, catalog);
    const etag = `"drop-${etagFromFileURL(DROPS_PATH).slice(1, -1)}-${etagFromFileURL(PRODUCTS_PATH).slice(1, -1)}"`;

    if (!window.isActive || !weekData || !products.length) {
      const payload = {
        active: false,
        weekId: window.weekId,
        nextDropAt: window.nextDropAt,
        startsAt: window.startsAt,
        endsAt: window.endsAt,
        products: [],
      };
      return sendPublicJsonWithCache(req, res, payload, { maxAgeSeconds: 20, etag });
    }

    const payload = {
      active: true,
      weekId: window.weekId,
      startsAt: weekData.startsAt || window.startsAt,
      endsAt: weekData.endsAt || window.endsAt,
      products,
      nextDropAt: null,
    };
    return sendPublicJsonWithCache(req, res, payload, { maxAgeSeconds: 20, etag });
  } catch (err) {
    console.error("drop/current error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/drop/my-submissions/:sellerId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  const { sellerId } = req.params;
  if (req.auth.sellerId !== String(sellerId || "").trim()) {
    auditOwnershipMismatch(req, {
      scope: "drop_my_submissions",
      expectedSellerId: String(sellerId || "").trim(),
      actualSellerId: req.auth.sellerId || null,
    });
    return res.status(403).json({ error: "Seller submissions access denied" });
  }
  const window = getCurrentDropSubmissionWindow();
  const drops = loadDropsFile();
  const catalog = await fetchCatalog();

  const lineupFriday = getFridayStartForStagedDropLineup(new Date());
  let lineupCycle = dropCycleWindowForFridayStart(lineupFriday);
  let weekData = drops[lineupCycle.weekId];
  let myProducts = resolveDropProducts(weekData, catalog).filter((product) => product.sellerId === sellerId);

  if (myProducts.length === 0) {
    const standard = getRelevantDropFridayStart(new Date());
    const standardCycle = dropCycleWindowForFridayStart(standard);
    const priorFriday = addDropZoneDays(standard, -7, DROP_TIME_ZONE);
    const priorCycle = dropCycleWindowForFridayStart(priorFriday);
    const now = new Date();
    const parts = dropTimeParts(now, DROP_TIME_ZONE);
    if (
      parts.weekday === 4 &&
      parts.hour < 17 &&
      now > priorCycle.endsAt &&
      now < standardCycle.submissionStartsAt
    ) {
      const altWeekData = drops[priorCycle.weekId];
      const altProducts = resolveDropProducts(altWeekData, catalog).filter((product) => product.sellerId === sellerId);
      if (altProducts.length > 0) {
        myProducts = altProducts;
        lineupCycle = priorCycle;
      }
    }
  }

  res.json({
    sellerId,
    weekId: lineupCycle.weekId,
    isActive: window.isActive,
    nextDropAt: window.nextDropAt,
    slotsUsed: myProducts.length,
    slotsMax: DROP_MAX_SLOTS_PER_SELLER,
    products: myProducts,
  });
});

app.get("/drop/history/:sellerId", requireAppClient, requireAuthenticatedSeller, async (req, res) => {
  const { sellerId } = req.params;
  const normalizedSellerId = String(sellerId || "").trim();
  if (req.auth.sellerId !== normalizedSellerId) {
    auditOwnershipMismatch(req, {
      scope: "drop_history",
      expectedSellerId: normalizedSellerId,
      actualSellerId: req.auth.sellerId || null,
    });
    return res.status(403).json({ error: "Seller drop history access denied" });
  }

  try {
    const limit = Math.max(1, Math.min(12, Number(req.query.limit) || 8));
    const now = new Date();
    const drops = loadDropsFile();
    const catalog = await fetchCatalog();
    const catalogProducts = Array.isArray(catalog.products)
      ? catalog.products.map((product) => normalizeCatalogProduct(product))
      : [];
    const productsById = new Map(catalogProducts.map((product) => [String(product.id || ""), product]));
    const orders = loadOrdersFile();

    const weeks = Object.entries(drops || {})
      .map(([weekId, weekData]) => {
        const startsAt = weekData?.startsAt || null;
        const endsAt = weekData?.endsAt || null;
        const endedAt = endsAt ? new Date(endsAt) : null;
        if (!startsAt || !endsAt || !endedAt || Number.isNaN(endedAt.getTime()) || endedAt > now) {
          return null;
        }

        const sellerEntries = dropEntriesForWeek(weekData).filter((entry) => entry.sellerId === normalizedSellerId);
        const products = sellerEntries
          .map((entry, index) => {
            const product = productsById.get(entry.productId);
            if (!product || product.sellerId !== normalizedSellerId) return null;
            return buildDropProduct(product, entry, index);
          })
          .filter(Boolean);

        if (!products.length) return null;

        const productIds = new Set(products.map((product) => product.id));
        const soldCount = orders.reduce((count, order) => {
          const createdAt = order?.createdAt ? new Date(order.createdAt) : null;
          const isDuringWeek =
            createdAt &&
            !Number.isNaN(createdAt.getTime()) &&
            createdAt >= new Date(startsAt) &&
            createdAt <= endedAt;
          if (!isDuringWeek) return count;

          return count + (Array.isArray(order.shipments) ? order.shipments : []).reduce((shipmentCount, shipment) => {
            if (String(shipment.sellerId || "").trim() !== normalizedSellerId) return shipmentCount;
            return shipmentCount + (Array.isArray(shipment.items) ? shipment.items : []).reduce((itemCount, item) => {
              if (!productIds.has(String(item.productId || "").trim())) return itemCount;
              return itemCount + Math.max(1, asFiniteNumber(item.quantity, 1));
            }, 0);
          }, 0);
        }, 0);

        return {
          weekId,
          startsAt,
          endsAt,
          postedCount: products.length,
          soldCount,
          products,
        };
      })
      .filter(Boolean)
      .sort((lhs, rhs) => new Date(rhs.startsAt).getTime() - new Date(lhs.startsAt).getTime())
      .slice(0, limit);

    res.json({ sellerId: normalizedSellerId, weeks });
  } catch (err) {
    console.error("drop/history error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.delete("/drop/submission/:productId", requireAppClient, requireAuthenticatedSeller, (req, res) => {
  const { productId } = req.params;
  const window = getCurrentDropSubmissionWindow();

  if (!window.isActive) {
    return res.status(400).json({ error: "Cannot delete submissions outside the Thursday evening drop window" });
  }

  const drops = loadDropsFile();
  const weekData = drops[window.weekId];
  if (!weekData) return res.status(404).json({ error: "No drop data for this week" });

  const weekEntries = dropEntriesForWeek(weekData);
  const idx = weekEntries.findIndex((entry) => entry.productId === productId);
  if (idx === -1) return res.status(404).json({ error: "Product not found in this week's drop" });
  if (req.auth.sellerId !== weekEntries[idx].sellerId) {
    auditOwnershipMismatch(req, {
      scope: "drop_delete",
      expectedSellerId: weekEntries[idx].sellerId || null,
      actualSellerId: req.auth.sellerId || null,
      productId,
    });
    return res.status(403).json({ error: "Seller drop deletion denied" });
  }

  const removedEntry = weekEntries.splice(idx, 1)[0];
  weekData.entries = weekEntries;

  fetchCatalog()
    .then((catalog) => {
      const catalogProducts = Array.isArray(catalog.products) ? catalog.products.map((product) => normalizeCatalogProduct(product)) : [];
      const productIndex = catalogProducts.findIndex((product) => product.id === productId);
      let removedProduct = null;

      if (productIndex >= 0) {
        removedProduct = {
          ...catalogProducts[productIndex],
          isDrop: false,
        };
        catalogProducts[productIndex] = normalizeCatalogProduct(removedProduct);
        saveCatalog({ ...catalog, products: catalogProducts });
      }

      saveDropsFile(drops);
      res.json({
        deleted: true,
        product: buildDropProduct(removedProduct || { id: productId, sellerId: removedEntry.sellerId }, removedEntry),
      });
    })
    .catch((err) => {
      console.error("drop/submission delete error:", err);
      res.status(500).json({ error: err.message });
    });
});

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

async function checkReadiness() {
  const resendStatus = resend ? await getResendProviderStatus() : { valid: null, detail: "not_configured" };
  const checks = {
    dataDirectoryExists: existsSync(DATA_DIRECTORY_PATH),
    dataDirectoryWritable: false,
    stripeSecretKey: Boolean(String(process.env.STRIPE_SECRET_KEY || "").trim()),
    stripeWebhookSecret: Boolean(String(process.env.STRIPE_WEBHOOK_SECRET || "").trim()),
    appApiKey: Boolean(String(process.env.APP_API_KEY || "").trim()),
    authSecret: Boolean(String(process.env.AUTH_JWT_SECRET || "").trim() || String(process.env.APP_API_KEY || "").trim()),
    email: transactionalEmailConfigured(),
    adminLoginEmail: Boolean(ADMIN_LOGIN_EMAIL),
    emailFromResendSandbox: emailFromUsesResendSandbox(),
    resendApiKeyValid: resendStatus.valid,
    ...(resendStatus.valid === false ? { resendApiKeyError: resendStatus.detail } : {}),
  };
  try {
    const probe = path.join(DATA_DIRECTORY_PATH, `.write_probe_${Date.now()}`);
    writeFileSync(probe, "ok");
    unlinkSync(probe);
    checks.dataDirectoryWritable = true;
  } catch {
    checks.dataDirectoryWritable = false;
  }

  applyDatabaseUrlToEnv();
  checks.databaseUrlConfigured = isPrismaConfigured();
  if (checks.databaseUrlConfigured) {
    try {
      const prisma = getPrisma();
      if (prisma) {
        await prisma.$queryRaw`SELECT 1`;
        checks.postgresReachable = true;
      } else {
        checks.postgresReachable = false;
      }
    } catch {
      checks.postgresReachable = false;
    }
  } else {
    checks.postgresReachable = null;
  }

  let ok =
    checks.dataDirectoryExists &&
    checks.dataDirectoryWritable &&
    checks.stripeSecretKey &&
    checks.authSecret;

  if (IS_PRODUCTION) {
    ok = ok && checks.stripeWebhookSecret && checks.appApiKey && checks.email;
  }

  if (checks.databaseUrlConfigured && checks.postgresReachable === false) {
    console.warn("Readiness: DATABASE_URL is set but Postgres is not reachable");
  }

  return { ok, checks };
}

app.get("/", (_, res) =>
  res.json({ ok: true, service: "TenBelow", hint: "API routes include /config, /health, /ready, /catalog" })
);

app.get("/health", (_, res) => res.json({ ok: true }));

app.get("/ready", async (_, res) => {
  const { ok, checks } = await checkReadiness();
  res.status(ok ? 200 : 503).json({
    ok,
    checks,
    dataDirectory: DATA_DIRECTORY_PATH,
    environment: IS_PRODUCTION ? "production" : "development",
  });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const PORT = process.env.PORT || 3000;

async function startServer() {
  applyDatabaseUrlToEnv();
  if (isPgEnabled()) {
    try {
      await ensureSchema();
      await ensureRelationalSchema();
      if (process.env.PG_READS === "1") {
        DOCUMENT_MEMORY_CACHE.clear();
        await loadAllDocumentsInto(DOCUMENT_MEMORY_CACHE);
        console.log(`Postgres read cache primed (${DOCUMENT_MEMORY_CACHE.size} documents)`);
      }
    } catch (err) {
      console.error("Postgres initialization failed:", err.message || err);
      if (process.env.PG_READS === "1") {
        process.exit(1);
      }
    }
  }

  if (isPrismaConfigured() && String(process.env.PRISMA_BOOTSTRAP_SYNC || "").trim() === "1") {
    try {
      const result = await syncPhase1ToPrisma();
      console.log("Phase 1 Prisma bootstrap sync complete:", JSON.stringify(result));
    } catch (err) {
      console.error("Phase 1 Prisma bootstrap sync failed:", err.message || err);
    }
  }

  app.listen(PORT, () => {
    console.log(`TenBelow backend → http://localhost:${PORT}`);
    console.log(`TenBelow public URL → ${BACKEND_URL}`);
    console.log(`TenBelow data directory → ${DATA_DIRECTORY_PATH}`);
    if (!transactionalEmailConfigured()) {
      console.warn("No transactional email provider configured. Set RESEND_API_KEY or SMTP settings.");
    } else if (!resend && smtpConfigured) {
      console.log(`Transactional email provider → SMTP (${SMTP_HOST}:${SMTP_PORT})`);
    }
  });
}

startServer().catch((err) => {
  console.error("Server failed to start:", err);
  process.exit(1);
});
