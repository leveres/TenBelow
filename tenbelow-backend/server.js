import "dotenv/config";
import express from "express";
import cors from "cors";
import Stripe from "stripe";
import { Resend } from "resend";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import crypto from "crypto";
import { fileURLToPath } from "url";
import {
  isAppStoreVerificationConfigured,
  verifySubscriptionWithAppStore,
} from "./appStoreMembershipVerification.js";
import { registerPushDevice } from "./pushDevicesStore.js";
import { notifyPaymentSucceeded } from "./pushOrderNotifications.js";
import {
  DATA_DIRECTORY_PATH,
  DATA_DIRECTORY_URL,
  MEDIA_DIRECTORY_PATH,
  MEDIA_DIRECTORY_URL,
  dataFileURL,
  ensureDirectory,
} from "./storagePaths.js";

const app = express();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const resend = process.env.RESEND_API_KEY
  ? new Resend(process.env.RESEND_API_KEY)
  : null;

const EMAIL_FROM = process.env.EMAIL_FROM || "TenBelow <noreply@tenbelow.com>";
const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:3000";
const SELLER_SUBSCRIPTION_PRODUCT_ID =
  process.env.SELLER_SUBSCRIPTION_PRODUCT_ID || "com.innovativecodeworks.com.TenBelow.seller.monthly";
const LEGACY_PRODUCTS_PATH = new URL("../TenBelow/Data/Remote/products.json", import.meta.url);
const LEGACY_CONFIG_PATH = new URL("../TenBelow/Data/Remote/config.json", import.meta.url);
const LEGACY_SELLERS_PATH = new URL("./sellers.json", import.meta.url);
const LEGACY_ORDERS_PATH = new URL("./orders.json", import.meta.url);
const LEGACY_DROPS_PATH = new URL("./drops.json", import.meta.url);
const PRODUCTS_PATH = dataFileURL("products.json");
const CONFIG_PATH = dataFileURL("config.json");
const SELLERS_PATH = dataFileURL("sellers.json");
const ORDERS_PATH = dataFileURL("orders.json");
const DROPS_PATH = dataFileURL("drops.json");
const PRODUCT_REVIEWS_PATH = dataFileURL("product-reviews.json");

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
}

initializeBackendStorage();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch ${url} → ${res.status}`);
  return res.json();
}

async function fetchCatalog() {
  const hydrateCatalog = (catalog) => {
    const reviews = loadProductReviewsFile();
    return hydrateCatalogWithProductReviews(catalog, reviews);
  };

  if (process.env.CATALOG_URL) {
    try { return await fetchJSON(process.env.CATALOG_URL); } catch (e) {
      console.warn("CATALOG_URL fetch failed:", e.message);
    }
  }
  try {
    return hydrateCatalog(JSON.parse(readFileSync(PRODUCTS_PATH, "utf-8")));
  } catch { return hydrateCatalog({ version: 1, updatedAt: new Date().toISOString(), products: [] }); }
}

async function fetchConfig() {
  if (process.env.CONFIG_URL) {
    try { return await fetchJSON(process.env.CONFIG_URL); } catch (e) {
      console.warn("CONFIG_URL fetch failed:", e.message);
    }
  }
  try {
    return JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
  } catch { return { version: 2, minimumOrderCents: 1500 }; }
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
    expiresAt: membership.expiresAt || null,
    lastSyncedAt: membership.lastSyncedAt || null,
    source: membership.source || "app_store",
    originalTransactionId: membership.originalTransactionId || null,
    transactionId: membership.transactionId || null,
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

function isValidSellerId(value) {
  return /^[a-z0-9][a-z0-9_-]{2,23}$/.test(String(value || "").trim());
}

function normalizeCatalogProduct(product = {}) {
  return {
    id: String(product.id || crypto.randomUUID()),
    sellerId: String(product.sellerId || "").trim(),
    name: String(product.name || "").trim(),
    priceCents: Math.max(0, asFiniteNumber(product.priceCents, 0)),
    category: String(product.category || "desk").trim().toLowerCase(),
    imageURLs: Array.isArray(product.imageURLs) ? product.imageURLs.filter(Boolean) : [],
    demoVideoURL: product.demoVideoURL || null,
    material: String(product.material || "PLA+").trim(),
    durabilityNote: String(product.durabilityNote || "Built for everyday use.").trim(),
    careWarnings: Array.isArray(product.careWarnings) ? product.careWarnings.filter(Boolean) : [],
    shipsInMinDays: Math.max(1, asFiniteNumber(product.shipsInMinDays, 2)),
    shipsInMaxDays: Math.max(1, asFiniteNumber(product.shipsInMaxDays, 4)),
    isDrop: product.isDrop === true,
    isActive: product.isActive !== false,
    isApproved: product.isApproved !== false,
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
  writeFileSync(PRODUCTS_PATH, JSON.stringify(payload, null, 2));
}

function loadProductReviewsFile() {
  try {
    const parsed = JSON.parse(readFileSync(PRODUCT_REVIEWS_PATH, "utf-8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveProductReviewsFile(reviews) {
  writeFileSync(PRODUCT_REVIEWS_PATH, JSON.stringify(Array.isArray(reviews) ? reviews : [], null, 2));
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

  return {
    displayName: String(profile.displayName || businessName || trimmedSellerId || "TenBelow Seller").trim(),
    handle: `@${normalizedHandleBase || "tenbelowseller"}`,
    bio: String(profile.bio || "Independent TenBelow seller creating 3D-printed products.").trim(),
    avatarURL: profile.avatarURL || null,
    bannerURL: profile.bannerURL || null,
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
  };
}

function normalizeSellerRecord(record = {}, sellerId = "") {
  return {
    stripeAccountId: record.stripeAccountId || "",
    email: record.email || "",
    businessName: record.businessName || "",
    membership: normalizeMembership(record.membership),
    profile: normalizeSellerPublicProfile(record.profile, sellerId, record.businessName),
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
  };
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

function sellerMembershipResponse(sellerId, seller) {
  const membership = normalizeMembership(seller?.membership);
  return {
    sellerId,
    requiresSubscription: true,
    hasActiveSubscription: membership.hasActiveSubscription,
    productId: membership.productId,
    source: membership.source,
    expiresAt: membership.expiresAt,
    lastSyncedAt: membership.lastSyncedAt,
  };
}

function loadOrdersFile() {
  try {
    return JSON.parse(readFileSync(ORDERS_PATH, "utf-8"));
  } catch {
    return [];
  }
}

function saveOrdersFile(orders) {
  writeFileSync(ORDERS_PATH, JSON.stringify(orders, null, 2));
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

  const deliveredCount = shipments.filter((shipment) => shipment.status === "delivered").length;
  const shippedCount = shipments.filter((shipment) => shipment.status === "shipped").length;
  const preparingCount = shipments.filter((shipment) => shipment.status === "preparing").length;

  if (deliveredCount === shipments.length) return "delivered";
  if (shippedCount + deliveredCount === shipments.length && shippedCount > 0) return "shipped";
  if (shippedCount > 0 && preparingCount > 0) return "partiallyShipped";
  if (preparingCount > 0) return "processing";
  return current;
}

function upsertPaidOrder({ orderId, buyerEmail, shipping, totalCents, currency = "USD", orderItems, sellers }) {
  const orders = loadOrdersFile();
  const existingIndex = orders.findIndex((order) => order.id === orderId);
  const existingOrder = existingIndex >= 0 ? orders[existingIndex] : null;
  const shipments = existingOrder?.shipments?.length
    ? existingOrder.shipments
    : groupOrderItemsIntoShipments(orderItems, sellers);

  const nextOrder = {
    id: orderId,
    createdAt: existingOrder?.createdAt || new Date().toISOString(),
    status: deriveOrderStatus(shipments, "placed"),
    buyerEmail: buyerEmail || existingOrder?.buyerEmail || null,
    shipToCity: shipping?.city || existingOrder?.shipToCity || null,
    shipToState: shipping?.state || existingOrder?.shipToState || null,
    currency,
    totalCents,
    shipments,
  };

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
    const pi = event.data.object;
    const meta = pi.metadata;
    const orderId = meta.orderId || crypto.randomUUID();

    try {
      const orderItems = JSON.parse(meta.orderItems || "[]");
      const sellerTotals = JSON.parse(meta.sellerTotals || "{}");
      const shipping = JSON.parse(meta.shipping || "{}");
      const sellers = await fetchSellers();
      upsertPaidOrder({
        orderId,
        buyerEmail: meta.buyerEmail,
        shipping,
        totalCents: pi.amount_received || pi.amount,
        currency: (pi.currency || "usd").toUpperCase(),
        orderItems,
        sellers,
      });

      for (const [sellerId, amountCents] of Object.entries(sellerTotals)) {
        const seller = sellers[sellerId];
        if (!seller?.stripeAccountId) continue;
        const platformFee = Math.round(amountCents * 0.10);
        const transferAmount = amountCents - platformFee;
        if (transferAmount <= 0) continue;
        await stripe.transfers.create({
          amount: transferAmount,
          currency: "usd",
          destination: seller.stripeAccountId,
          transfer_group: orderId,
        });
      }

      if (meta.buyerEmail && resend) {
        await resend.emails.send({
          from: EMAIL_FROM,
          to: meta.buyerEmail,
          subject: `TenBelow Order Confirmed — ${orderId}`,
          html: `<h2>Thanks for your order!</h2><p>Order <strong>${orderId}</strong></p><p>We'll email tracking when items ship.</p>`,
        });
      } else if (meta.buyerEmail && !resend) {
        console.warn("RESEND_API_KEY not configured; skipping order confirmation email.");
      }

      try {
        await notifyPaymentSucceeded({
          orderId,
          buyerEmail: meta.buyerEmail,
          sellerTotals,
        });
      } catch (pushErr) {
        console.warn("Order push notification error:", pushErr?.message || pushErr);
      }
    } catch (err) {
      console.error("Webhook processing error:", err);
    }
  }

  res.json({ received: true });
});

// ---------------------------------------------------------------------------
// JSON body parser (after webhook)
// ---------------------------------------------------------------------------

app.use(express.json());
app.use(cors());
app.use("/media", express.static(MEDIA_DIRECTORY_PATH));

app.get("/catalog", async (_, res) => {
  try {
    const catalog = await fetchCatalog();
    res.json(catalog);
  } catch (err) {
    console.error("catalog error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/config", async (_, res) => {
  try {
    const config = await fetchConfig();
    res.json(config);
  } catch (err) {
    console.error("config error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/register-push-device", (req, res) => {
  try {
    const { deviceToken, userKey } = req.body || {};
    if (!deviceToken) return res.status(400).json({ error: "deviceToken required" });
    registerPushDevice(userKey, deviceToken);
    res.json({ ok: true });
  } catch (e) {
    console.warn("register-push-device:", e.message);
    res.status(400).json({ error: e.message });
  }
});

// ---------------------------------------------------------------------------
// Create Payment Intent
// ---------------------------------------------------------------------------

app.post("/create-payment-intent", async (req, res) => {
  try {
    const { email, shipping, items } = req.body;
    if (!email || !items?.length) return res.status(400).json({ error: "Missing email or items" });

    const catalog = await fetchCatalog();
    const config = await fetchConfig();
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
        productionPreviewURL: null,
        shipsInMaxDays: product.shipsInMaxDays || 4,
      });
    }

    if (!orderItems.length) {
      return res.status(400).json({
        code: "empty_valid_cart",
        error: "Your cart is empty. Add an item before checking out.",
      });
    }

    const minimumOrderCents = config.minimumOrderCents || 1500;
    if (subtotalCents < minimumOrderCents) {
      return res.status(400).json({
        code: "minimum_order_not_met",
        error: `Minimum order is $${(minimumOrderCents / 100).toFixed(2)}`,
        minimumOrderCents,
      });
    }

    const totalCents = subtotalCents;
    const orderId = crypto.randomUUID();

    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalCents,
      currency: "usd",
      payment_method_types: ["card"],
      metadata: {
        orderId,
        buyerEmail: email,
        orderItems: JSON.stringify(orderItems),
        sellerTotals: JSON.stringify(sellerTotals),
        shipping: JSON.stringify({
          city: shipping?.city || null,
          state: shipping?.state || null,
        }),
      },
    });

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
  try { return normalizeSellerMap(JSON.parse(readFileSync(SELLERS_PATH, "utf-8"))); } catch { return {}; }
}

function saveSellersFile(sellers) {
  writeFileSync(SELLERS_PATH, JSON.stringify(normalizeSellerMap(sellers), null, 2));
}

app.get("/orders", (req, res) => {
  try {
    const buyerEmail = (req.query.buyerEmail || "").toString().trim().toLowerCase();
    const sellerId = (req.query.sellerId || "").toString().trim();
    const orderId = (req.query.orderId || "").toString().trim();

    let orders = loadOrdersFile();
    if (orderId) {
      orders = orders.filter((order) => order.id === orderId);
    }
    if (buyerEmail) {
      orders = orders.filter((order) => (order.buyerEmail || "").trim().toLowerCase() === buyerEmail);
    }
    if (sellerId) {
      orders = orders.filter((order) => order.shipments.some((shipment) => shipment.sellerId === sellerId));
    }

    orders.sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime());
    res.json({ orders });
  } catch (err) {
    console.error("orders fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/orders/shipment-action", (req, res) => {
  try {
    const { orderId, shipmentId, sellerId, action, carrier, trackingNumber } = req.body || {};
    if (!orderId || !shipmentId || !sellerId || !action) {
      return res.status(400).json({ error: "orderId, shipmentId, sellerId, and action are required" });
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
      default:
        return res.status(400).json({ error: "Unknown shipment action" });
    }

    orders[orderIndex].status = deriveOrderStatus(orders[orderIndex].shipments, orders[orderIndex].status);
    saveOrdersFile(orders);
    res.json({ order: orders[orderIndex] });
  } catch (err) {
    console.error("shipment action error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/product-reviews", (req, res) => {
  try {
    const { orderId, productId, buyerEmail, rating, reviewText } = req.body || {};
    const normalizedOrderId = String(orderId || "").trim();
    const normalizedProductId = String(productId || "").trim();
    const normalizedBuyerEmail = String(buyerEmail || "").trim().toLowerCase();
    const normalizedRating = Math.round(asFiniteNumber(rating, 0));

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

app.get("/product-reviews", (req, res) => {
  try {
    const productId = String(req.query.productId || "").trim();
    if (!productId) {
      return res.status(400).json({ error: "productId is required" });
    }

    const reviews = loadProductReviewsFile()
      .filter((entry) => String(entry.productId || "").trim() === productId)
      .sort((lhs, rhs) => new Date(rhs.updatedAt || rhs.createdAt || 0).getTime() - new Date(lhs.updatedAt || lhs.createdAt || 0).getTime());

    const summary = buildProductReviewSummaryMap(reviews).get(productId) || { total: 0, count: 0 };

    res.json({
      productId,
      averageRating: summary.count > 0 ? Number((summary.total / summary.count).toFixed(1)) : 0,
      reviewCount: summary.count,
      reviews,
    });
  } catch (err) {
    console.error("product reviews fetch error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/create-seller-account", async (req, res) => {
  try {
    const rawSellerId = String(req.body.sellerId || "").trim().toLowerCase();
    const sellerId = rawSellerId.replace(/\s+/g, "-");
    const email = String(req.body.email || "").trim().toLowerCase();
    const businessName = req.body.businessName;

    if (!sellerId || !email) return res.status(400).json({ error: "sellerId and email required" });
    if (!isValidSellerId(sellerId)) {
      return res.status(400).json({ error: "Seller ID must be 3 to 24 characters using letters, numbers, hyphens, or underscores." });
    }

    const sellers = loadSellersFile();
    if (sellers[sellerId]) return res.status(409).json({ error: "Seller already exists" });

    const account = await stripe.accounts.create({
      type: "express",
      email,
      business_profile: { name: businessName || sellerId },
      capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
    });

    sellers[sellerId] = {
      stripeAccountId: account.id,
      email,
      businessName: businessName || "",
      membership: normalizeMembership(),
      profile: normalizeSellerPublicProfile({}, sellerId, businessName || sellerId),
    };
    saveSellersFile(sellers);

    const link = await stripe.accountLinks.create({
      account: account.id,
      refresh_url: `${BACKEND_URL}/seller-onboarding-refresh?sellerId=${sellerId}`,
      return_url: `${BACKEND_URL}/seller-onboarding-complete?sellerId=${sellerId}`,
      type: "account_onboarding",
    });

    res.json({ sellerId, stripeAccountId: account.id, onboardingUrl: link.url });
  } catch (err) {
    console.error("create-seller-account error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-link/:sellerId", async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const seller = sellers[req.params.sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const link = await stripe.accountLinks.create({
      account: seller.stripeAccountId,
      refresh_url: `${BACKEND_URL}/seller-onboarding-refresh?sellerId=${req.params.sellerId}`,
      return_url: `${BACKEND_URL}/seller-onboarding-complete?sellerId=${req.params.sellerId}`,
      type: "account_onboarding",
    });
    res.json({ sellerId: req.params.sellerId, onboardingUrl: link.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-status/:sellerId", async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const seller = sellers[req.params.sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const account = await stripe.accounts.retrieve(seller.stripeAccountId);
    res.json({
      sellerId: req.params.sellerId,
      stripeAccountId: seller.stripeAccountId,
      chargesEnabled: account.charges_enabled,
      payoutsEnabled: account.payouts_enabled,
      detailsSubmitted: account.details_submitted,
      onboardingComplete: account.charges_enabled && account.payouts_enabled && account.details_submitted,
      hasActiveSubscription: seller.membership.hasActiveSubscription,
      subscriptionExpiresAt: seller.membership.expiresAt,
      subscriptionProductId: seller.membership.productId,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-dashboard-link/:sellerId", async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const seller = sellers[req.params.sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const link = await stripe.accounts.createLoginLink(seller.stripeAccountId);
    res.json({ sellerId: req.params.sellerId, dashboardUrl: link.url });
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

app.get("/sellers", (_, res) => res.json(loadSellersFile()));

app.get("/seller-profiles", async (_, res) => {
  try {
    const sellers = loadSellersFile();
    const catalog = await fetchCatalog();
    const orders = loadOrdersFile();
    res.json({
      sellers: buildSellerProfiles(sellers, catalog.products || [], orders),
    });
  } catch (err) {
    console.error("seller-profiles error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-profiles/:sellerId", async (req, res) => {
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

    res.json({
      seller: buildSellerProfile(sellerId, sellers[sellerId], catalog.products || [], orders),
    });
  } catch (err) {
    console.error("seller-profile error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put("/seller-profiles/:sellerId", async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    if (!sellerId) return res.status(400).json({ error: "Seller id is required" });

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });

    const body = req.body || {};
    const mergedProfile = normalizeSellerPublicProfile(
      {
        ...(seller.profile || {}),
        displayName: body.displayName,
        handle: body.handle,
        bio: body.bio,
        avatarURL: body.avatarURL,
        bannerURL: body.bannerURL,
        websiteURL: body.websiteURL,
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

app.put("/seller-products/:sellerId/:productId", async (req, res) => {
  try {
    const sellerId = String(req.params.sellerId || "").trim();
    const productId = String(req.params.productId || "").trim();
    if (!sellerId || !productId) {
      return res.status(400).json({ error: "sellerId and productId are required" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) return res.status(404).json({ error: "Seller not found" });

    const body = req.body || {};
    const catalog = await fetchCatalog();
    const nextProduct = normalizeCatalogProduct({
      id: productId,
      sellerId,
      name: body.name,
      priceCents: body.priceCents,
      category: body.category,
      imageURLs: body.imageURLs,
      demoVideoURL: body.demoVideoURL,
      material: body.material,
      durabilityNote: body.durabilityNote,
      careWarnings: body.careWarnings,
      shipsInMinDays: body.shipsInMinDays,
      shipsInMaxDays: body.shipsInMaxDays,
      isDrop: body.isDrop,
      isActive: body.isActive,
      isApproved: body.isApproved,
    });

    if (!nextProduct.name) {
      return res.status(400).json({ error: "Product name is required" });
    }

    const existingProducts = Array.isArray(catalog.products) ? catalog.products : [];
    const existingIndex = existingProducts.findIndex((product) => product.id === productId);
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

    res.json({ product: mergedProduct });
  } catch (err) {
    console.error("update seller-product error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put(
  "/seller-media/:sellerId/:productId/:mediaKind/:slot",
  express.raw({ type: "*/*", limit: "80mb" }),
  (req, res) => {
    try {
      const sellerId = sanitizePathSegment(req.params.sellerId, "seller");
      const productId = sanitizePathSegment(req.params.productId, "product");
      const mediaKind = sanitizePathSegment(req.params.mediaKind, "media");
      const slot = sanitizePathSegment(req.params.slot, "0");
      const body = req.body;
      if (!body || !Buffer.isBuffer(body) || body.length === 0) {
        return res.status(400).json({ error: "Media file is required" });
      }

      const extension = sanitizeFileExtension(req.headers["x-file-extension"], "bin");
      const directoryURL = new URL(`./${sellerId}/${productId}/`, MEDIA_DIRECTORY_URL);
      mkdirSync(directoryURL, { recursive: true });

      const filename = `${mediaKind}-${slot}.${extension}`;
      const fileURL = new URL(filename, directoryURL);
      writeFileSync(fileURL, body);

      res.json({
        url: `${BACKEND_URL}/media/${sellerId}/${productId}/${filename}`,
      });
    } catch (err) {
      console.error("seller-media upload error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.get("/seller-membership-status/:sellerId", (req, res) => {
  const sellers = loadSellersFile();
  const seller = sellers[req.params.sellerId];
  if (!seller) return res.status(404).json({ error: "Seller not found" });
  res.json(sellerMembershipResponse(req.params.sellerId, seller));
});

app.post("/seller-membership-sync", async (req, res) => {
  try {
    const { sellerId, productId, isActive, expiresAt, transactionId, originalTransactionId } = req.body;
    if (!sellerId) return res.status(400).json({ error: "sellerId is required" });

    const sellers = loadSellersFile();
    const seller = sellers[sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });

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
        "seller-membership-sync: App Store Server API env not set; using client-reported membership (configure APP_STORE_* for server-side verification)."
      );
      seller.membership = normalizeMembership({
        ...seller.membership,
        productId: effectiveProductId,
        hasActiveSubscription: isActive === true,
        expiresAt: expiresAt || null,
        lastSyncedAt: new Date().toISOString(),
        source: "app_store",
        transactionId: transactionId || seller.membership?.transactionId || null,
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
  try { return JSON.parse(readFileSync(DROPS_PATH, "utf-8")); } catch { return {}; }
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
  writeFileSync(DROPS_PATH, JSON.stringify(normalized, null, 2));
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

function buildDropProduct(product = {}, entry = {}) {
  const normalizedProduct = normalizeCatalogProduct(product);
  return {
    id: normalizedProduct.id,
    sellerId: normalizedProduct.sellerId,
    name: normalizedProduct.name,
    priceCents: normalizedProduct.priceCents,
    category: normalizedProduct.category,
    imageURLs: normalizedProduct.imageURLs,
    demoVideoURL: normalizedProduct.demoVideoURL,
    material: normalizedProduct.material,
    durabilityNote: normalizedProduct.durabilityNote,
    careWarnings: normalizedProduct.careWarnings,
    shipsInMinDays: normalizedProduct.shipsInMinDays,
    shipsInMaxDays: normalizedProduct.shipsInMaxDays,
    submittedAt: entry.submittedAt || new Date().toISOString(),
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
    .map((entry) => {
      const product = productsById.get(entry.productId);
      if (!product || product.sellerId !== entry.sellerId || product.isDrop !== true) {
        return null;
      }
      return buildDropProduct(product, entry);
    })
    .filter(Boolean);
}

function getCurrentDropWindow() {
  const now = new Date();
  const utcDay = now.getUTCDay();

  let fridayOffset;
  if (utcDay === 5) fridayOffset = 0;
  else if (utcDay === 6) fridayOffset = -1;
  else if (utcDay === 0) fridayOffset = -2;
  else fridayOffset = -(utcDay + 2);

  const friday = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + fridayOffset,
    0, 0, 0, 0
  ));

  const sunday = new Date(Date.UTC(
    friday.getUTCFullYear(), friday.getUTCMonth(), friday.getUTCDate() + 2,
    23, 59, 59, 999
  ));

  const isActive = utcDay === 5 || utcDay === 6 || utcDay === 0;

  const isoYear = friday.getUTCFullYear();
  const dayOfYear = Math.floor((friday - new Date(Date.UTC(isoYear, 0, 1))) / 86400000);
  const weekNum = Math.ceil((dayOfYear + 1) / 7);
  const weekId = `${isoYear}-W${String(weekNum).padStart(2, "0")}`;

  let nextDropAt = null;
  if (!isActive) {
    const daysUntilFriday = (5 - utcDay + 7) % 7 || 7;
    nextDropAt = new Date(Date.UTC(
      now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + daysUntilFriday,
      0, 0, 0, 0
    )).toISOString();
  }

  return {
    weekId,
    startsAt: friday.toISOString(),
    endsAt: sunday.toISOString(),
    isActive,
    nextDropAt,
  };
}

app.post("/drop/submit", async (req, res) => {
  try {
    const {
      productId,
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      material,
      durabilityNote,
      careWarnings,
      shipsInMinDays,
      shipsInMaxDays,
    } = req.body;

    if (!sellerId || !name || !priceCents) {
      return res.status(400).json({ error: "sellerId, name, and priceCents are required" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) {
      return res.status(404).json({ error: "Seller not found. Create an account first." });
    }

    if (!normalizeMembership(sellers[sellerId].membership).hasActiveSubscription) {
      return res.status(403).json({
        error: "An active seller membership is required before submitting Weekly Drop products.",
      });
    }

    if (priceCents < DROP_MIN_PRICE_CENTS) {
      return res.status(400).json({ error: `Drop products must be over $10 (got $${(priceCents / 100).toFixed(2)})` });
    }

    const window = getCurrentDropWindow();
    if (!window.isActive) {
      return res.status(400).json({
        error: "Drop submissions are only open Friday through Sunday (UTC)",
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

    const catalog = await fetchCatalog();
    const catalogProducts = Array.isArray(catalog.products) ? catalog.products.map((product) => normalizeCatalogProduct(product)) : [];
    const resolvedProductId = sanitizePathSegment(productId || `drop-${crypto.randomUUID()}`, `drop-${crypto.randomUUID()}`);
    const existingProduct = catalogProducts.find((product) => product.id === resolvedProductId);
    if (existingProduct && existingProduct.sellerId !== sellerId) {
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
      material: material || "PLA+",
      durabilityNote: durabilityNote || "",
      careWarnings: careWarnings || [],
      shipsInMinDays: shipsInMinDays || 3,
      shipsInMaxDays: shipsInMaxDays || 7,
      isDrop: true,
      isActive: false,
      isApproved: true,
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
      submittedAt: existingProduct?.submittedAt || new Date().toISOString(),
    });
    weekData.entries = [...weekEntries, entry];
    saveDropsFile(drops);

    res.json(buildDropProduct(product, entry));
  } catch (err) {
    console.error("drop/submit error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.put("/drop/submission/:productId", async (req, res) => {
  try {
    const { productId } = req.params;
    const {
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      material,
      durabilityNote,
      careWarnings,
      shipsInMinDays,
      shipsInMaxDays,
    } = req.body;

    if (!sellerId || !name || !priceCents) {
      return res.status(400).json({ error: "sellerId, name, and priceCents are required" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) {
      return res.status(404).json({ error: "Seller not found. Create an account first." });
    }

    if (!normalizeMembership(sellers[sellerId].membership).hasActiveSubscription) {
      return res.status(403).json({
        error: "An active seller membership is required before submitting Weekly Drop products.",
      });
    }

    if (priceCents < DROP_MIN_PRICE_CENTS) {
      return res.status(400).json({ error: `Drop products must be over $10 (got $${(priceCents / 100).toFixed(2)})` });
    }

    const window = getCurrentDropWindow();
    if (!window.isActive) {
      return res.status(400).json({
        error: "Drop submissions are only open Friday through Sunday (UTC)",
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
      return res.status(403).json({ error: "You can only edit your own drop products." });
    }

    const catalog = await fetchCatalog();
    const catalogProducts = Array.isArray(catalog.products) ? catalog.products.map((product) => normalizeCatalogProduct(product)) : [];
    const existingProductIndex = catalogProducts.findIndex((product) => product.id === productId);
    if (existingProductIndex === -1) {
      return res.status(404).json({ error: "Drop product not found in catalog." });
    }

    const updatedProduct = normalizeCatalogProduct({
      ...catalogProducts[existingProductIndex],
      id: productId,
      sellerId,
      name,
      priceCents,
      category,
      imageURLs,
      demoVideoURL,
      material: material || "PLA+",
      durabilityNote: durabilityNote || "",
      careWarnings: careWarnings || [],
      shipsInMinDays: shipsInMinDays || 3,
      shipsInMaxDays: shipsInMaxDays || 7,
      isDrop: true,
      isActive: false,
      isApproved: true,
    });

    catalogProducts[existingProductIndex] = updatedProduct;
    saveCatalog({ ...catalog, products: catalogProducts });

    weekData.entries = weekEntries;
    saveDropsFile(drops);

    res.json(buildDropProduct(updatedProduct, entry));
  } catch (err) {
    console.error("drop/submission update error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/drop/current", async (req, res) => {
  const window = getCurrentDropWindow();
  const drops = loadDropsFile();
  const weekData = drops[window.weekId];
  const catalog = await fetchCatalog();
  const products = resolveDropProducts(weekData, catalog);

  if (!window.isActive || !weekData || !products.length) {
    return res.json({
      active: false,
      weekId: window.weekId,
      nextDropAt: window.nextDropAt,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      products: [],
    });
  }

  res.json({
    active: true,
    weekId: window.weekId,
    startsAt: weekData.startsAt || window.startsAt,
    endsAt: weekData.endsAt || window.endsAt,
    products,
    nextDropAt: null,
  });
});

app.get("/drop/my-submissions/:sellerId", async (req, res) => {
  const { sellerId } = req.params;
  const window = getCurrentDropWindow();
  const drops = loadDropsFile();
  const weekData = drops[window.weekId];
  const catalog = await fetchCatalog();
  const myProducts = resolveDropProducts(weekData, catalog).filter((product) => product.sellerId === sellerId);

  res.json({
    sellerId,
    weekId: window.weekId,
    isActive: window.isActive,
    nextDropAt: window.nextDropAt,
    slotsUsed: myProducts.length,
    slotsMax: DROP_MAX_SLOTS_PER_SELLER,
    products: myProducts,
  });
});

app.delete("/drop/submission/:productId", (req, res) => {
  const { productId } = req.params;
  const window = getCurrentDropWindow();

  if (!window.isActive) {
    return res.status(400).json({ error: "Cannot delete submissions outside the drop window" });
  }

  const drops = loadDropsFile();
  const weekData = drops[window.weekId];
  if (!weekData) return res.status(404).json({ error: "No drop data for this week" });

  const weekEntries = dropEntriesForWeek(weekData);
  const idx = weekEntries.findIndex((entry) => entry.productId === productId);
  if (idx === -1) return res.status(404).json({ error: "Product not found in this week's drop" });

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

app.get("/health", (_, res) => res.json({ ok: true }));

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`TenBelow backend → http://localhost:${PORT}`);
  console.log(`TenBelow public URL → ${BACKEND_URL}`);
  console.log(`TenBelow data directory → ${DATA_DIRECTORY_PATH}`);
  if (!resend) {
    console.warn("RESEND_API_KEY not configured; transactional emails are disabled.");
  }
});
