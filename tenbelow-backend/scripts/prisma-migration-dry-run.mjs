#!/usr/bin/env node
/**
 * Dry-run migration report: reads JSON source files and estimates normalized row counts.
 * Does not write to PostgreSQL. Run before maintenance-window bulk migration.
 *
 * Usage:
 *   cd TenBelow/tenbelow-backend
 *   npm run migrate:prisma:dry-run
 */
import "dotenv/config";
import { existsSync, readFileSync } from "fs";
import { fileURLToPath } from "url";
import { DATA_DIRECTORY_PATH } from "../storagePaths.js";

function readJson(relativePath, fallback) {
  const filePath = `${DATA_DIRECTORY_PATH}/${relativePath}`;
  if (!existsSync(filePath)) return fallback;
  try {
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch (err) {
    return { __parseError: err.message, fallback };
  }
}

function countEmbeddedOrderRows(orders = []) {
  let sellerOrders = 0;
  let shipments = 0;
  let orderItems = 0;
  let supportRequests = 0;
  let orderMessages = 0;

  for (const order of orders) {
    const orderShipments = Array.isArray(order?.shipments) ? order.shipments : [];
    sellerOrders += orderShipments.length;
    shipments += orderShipments.length;
    for (const shipment of orderShipments) {
      orderItems += Array.isArray(shipment?.items) ? shipment.items.length : 0;
    }
    supportRequests += Array.isArray(order?.supportRequests) ? order.supportRequests.length : 0;
    orderMessages += Array.isArray(order?.orderMessages) ? order.orderMessages.length : 0;
  }

  return { sellerOrders, shipments, orderItems, supportRequests, orderMessages };
}

function countProductMedia(products = []) {
  let images = 0;
  let demoVideos = 0;
  let productionPreviews = 0;
  for (const product of products) {
    images += Array.isArray(product?.imageURLs) ? product.imageURLs.length : 0;
    if (product?.demoVideoURL) demoVideos += 1;
    if (product?.productionPreviewURL) productionPreviews += 1;
  }
  return { images, demoVideos, productionPreviews };
}

function countExchangeChildren(exchanges = []) {
  let proofAssets = 0;
  let timelineEvents = 0;
  for (const exchange of exchanges) {
    proofAssets += Array.isArray(exchange?.buyerProofAssets) ? exchange.buyerProofAssets.length : 0;
    timelineEvents += Array.isArray(exchange?.timelineEvents) ? exchange.timelineEvents.length : 0;
  }
  return { proofAssets, timelineEvents };
}

function countInquiryMessages(threads = []) {
  return threads.reduce((sum, thread) => sum + (Array.isArray(thread?.messages) ? thread.messages.length : 0), 0);
}

function countDropEntries(drops = {}) {
  return Object.values(drops).reduce(
    (sum, week) => sum + (Array.isArray(week?.entries) ? week.entries.length : 0),
    0
  );
}

function countPushDevices(store = {}) {
  if (store?.version === 2 && store?.byUser) {
    return Object.values(store.byUser).reduce(
      (sum, tokens) => sum + (Array.isArray(tokens) ? tokens.length : 0),
      0
    );
  }
  return Object.entries(store).reduce((sum, [key, tokens]) => {
    if (key === "version" || key === "byUser" || key === "tokenToUser") return sum;
    return sum + (Array.isArray(tokens) ? tokens.length : 0);
  }, 0);
}

function countAuditLogLines() {
  const filePath = `${DATA_DIRECTORY_PATH}/audit-log.jsonl`;
  if (!existsSync(filePath)) return 0;
  try {
    return readFileSync(filePath, "utf8")
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean).length;
  } catch {
    return 0;
  }
}

function relationshipWarnings({ buyers, sellers, products, orders, reviews, exchanges, drops }) {
  const warnings = [];
  const sellerIds = new Set(Object.keys(sellers || {}));
  const buyerEmails = new Set(Object.keys(buyers || {}).map((e) => e.toLowerCase()));
  const productIds = new Set((products?.products || []).map((p) => p.id));

  for (const product of products?.products || []) {
    if (product.sellerId && !sellerIds.has(product.sellerId)) {
      warnings.push(`Product ${product.id} references missing seller ${product.sellerId}`);
    }
  }

  for (const order of orders || []) {
    if (order.buyerEmail && !buyerEmails.has(String(order.buyerEmail).toLowerCase())) {
      warnings.push(`Order ${order.id} references unregistered buyer ${order.buyerEmail}`);
    }
    for (const shipment of order.shipments || []) {
      if (shipment.sellerId && !sellerIds.has(shipment.sellerId)) {
        warnings.push(`Order ${order.id} shipment references missing seller ${shipment.sellerId}`);
      }
      for (const item of shipment.items || []) {
        if (item.productId && !productIds.has(item.productId)) {
          warnings.push(`Order ${order.id} item references missing product ${item.productId}`);
        }
      }
    }
  }

  for (const review of reviews || []) {
    if (review.productId && !productIds.has(review.productId)) {
      warnings.push(`Review ${review.id} references missing product ${review.productId}`);
    }
  }

  for (const exchange of exchanges || []) {
    if (exchange.orderId && !(orders || []).some((o) => o.id === exchange.orderId)) {
      warnings.push(`Exchange ${exchange.id} references missing order ${exchange.orderId}`);
    }
  }

  for (const [weekId, week] of Object.entries(drops || {})) {
    for (const entry of week?.entries || []) {
      if (entry.productId && !productIds.has(entry.productId)) {
        warnings.push(`Drop ${weekId} entry references missing product ${entry.productId}`);
      }
    }
  }

  return warnings.slice(0, 50);
}

function main() {
  console.log("TenBelow Prisma migration dry-run report");
  console.log(`Data directory: ${DATA_DIRECTORY_PATH}`);
  console.log(`Generated at: ${new Date().toISOString()}\n`);

  const buyers = readJson("buyers.json", {});
  const sellers = readJson("sellers.json", {});
  const productsDoc = readJson("products.json", { products: [] });
  const orders = readJson("orders.json", []);
  const drops = readJson("drops.json", {});
  const reviews = readJson("product-reviews.json", []);
  const exchanges = readJson("exchange-requests.json", []);
  const customOrders = readJson("custom-order-requests.json", []);
  const inquiries = readJson("seller-inquiries.json", []);
  const webhookEvents = readJson("webhook-events.json", { ids: [] });
  const pushDevices = readJson("push_devices.json", { version: 2, byUser: {}, tokenToUser: {} });
  const config = readJson("config.json", {});

  const products = Array.isArray(productsDoc?.products) ? productsDoc.products : [];
  const orderEmbedded = countEmbeddedOrderRows(orders);
  const productMedia = countProductMedia(products);
  const exchangeChildren = countExchangeChildren(exchanges);

  const counts = {
    buyers: Object.keys(buyers || {}).length,
    sellers: Object.keys(sellers || {}).length,
    sellerProfiles: Object.keys(sellers || {}).length,
    sellerMemberships: Object.keys(sellers || {}).length,
    sellerAgreements: Object.keys(sellers || {}).length,
    foundingCreatorAccess: Object.values(sellers || {}).filter((s) => s?.isFoundingCreator === true).length,
    products: products.length,
    productVariants: products.length,
    inventoryItems: products.length,
    productMediaImages: productMedia.images,
    productMediaDemoVideos: productMedia.demoVideos,
    productMediaProductionPreviews: productMedia.productionPreviews,
    productRights: products.filter((p) => p.rightsOwnershipType || p.rightsCertificationAccepted).length,
    orders: orders.length,
    sellerOrders: orderEmbedded.sellerOrders,
    shipments: orderEmbedded.shipments,
    orderItems: orderEmbedded.orderItems,
    supportRequests: orderEmbedded.supportRequests,
    orderMessages: orderEmbedded.orderMessages,
    payments: 0,
    paymentTransfers: 0,
    refunds: 0,
    productReviews: reviews.length,
    exchangeRequests: exchanges.length,
    exchangeProofAssets: exchangeChildren.proofAssets,
    exchangeTimelineEvents: exchangeChildren.timelineEvents,
    weeklyDrops: Object.keys(drops || {}).length,
    dropEntries: countDropEntries(drops),
    customOrderRequests: customOrders.length,
    sellerInquiryThreads: inquiries.length,
    inquiryMessages: countInquiryMessages(inquiries),
    pushDevices: countPushDevices(pushDevices),
    processedWebhookEvents: Array.isArray(webhookEvents?.ids) ? webhookEvents.ids.length : 0,
    auditLogEntries: countAuditLogLines(),
    appConfig: existsSync(`${DATA_DIRECTORY_PATH}/config.json`) ? 1 : 0,
    carts: 0,
    cartItems: 0,
    notificationDeliveries: 0,
    moderationRecords: 0,
  };

  console.log("Estimated normalized row counts:");
  for (const [key, value] of Object.entries(counts)) {
    console.log(`  ${key}: ${value}`);
  }

  console.log("\nNotes:");
  console.log("  - payments/transfers/refunds/carts/notifications/moderation start empty (not in JSON today)");
  console.log("  - each product gets one default ProductVariant + InventoryItem row");
  console.log("  - each JSON shipment becomes SellerOrder + Shipment (1:1)");

  const warnings = relationshipWarnings({
    buyers,
    sellers,
    products: productsDoc,
    orders,
    reviews,
    exchanges,
    drops,
  });

  console.log(`\nRelationship warnings (${warnings.length} shown, max 50):`);
  if (!warnings.length) {
    console.log("  none");
  } else {
    for (const warning of warnings) {
      console.log(`  - ${warning}`);
    }
  }

  if (config?.__parseError) {
    console.log(`\nConfig parse error: ${config.__parseError}`);
  }

  console.log("\nDry-run complete. No database writes were performed.");
}

main();
