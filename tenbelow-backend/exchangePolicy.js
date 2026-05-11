import crypto from "crypto";

const ACTIVE_EXCHANGE_STATUSES = new Set([
  "submitted",
  "awaiting_buyer_proof",
  "under_review",
  "awaiting_seller_response",
  "approved",
  "replacement_preparing",
  "replacement_shipped",
]);

const COMPLETED_EXCHANGE_STATUSES = new Set([
  "approved",
  "replacement_preparing",
  "replacement_shipped",
  "replacement_delivered",
  "closed",
]);

export const DEFAULT_EXCHANGE_CONFIG = Object.freeze({
  exchangeWindowDays: 7,
  maxExchangeCountPerOrderItem: 1,
  minProofImages: 1,
  maxProofImages: 5,
  allowProofVideo: true,
  maxVideoDurationSeconds: 15,
  requireAdminForApproval: true,
});

export function mergeExchangeConfig(config = {}) {
  return {
    ...config,
    exchangeWindowDays: asPositiveInteger(config.exchangeWindowDays, DEFAULT_EXCHANGE_CONFIG.exchangeWindowDays),
    maxExchangeCountPerOrderItem: asPositiveInteger(
      config.maxExchangeCountPerOrderItem,
      DEFAULT_EXCHANGE_CONFIG.maxExchangeCountPerOrderItem
    ),
    minProofImages: asPositiveInteger(config.minProofImages, DEFAULT_EXCHANGE_CONFIG.minProofImages),
    maxProofImages: asPositiveInteger(config.maxProofImages, DEFAULT_EXCHANGE_CONFIG.maxProofImages),
    allowProofVideo:
      typeof config.allowProofVideo === "boolean"
        ? config.allowProofVideo
        : DEFAULT_EXCHANGE_CONFIG.allowProofVideo,
    maxVideoDurationSeconds: asPositiveInteger(
      config.maxVideoDurationSeconds,
      DEFAULT_EXCHANGE_CONFIG.maxVideoDurationSeconds
    ),
    requireAdminForApproval:
      typeof config.requireAdminForApproval === "boolean"
        ? config.requireAdminForApproval
        : DEFAULT_EXCHANGE_CONFIG.requireAdminForApproval,
  };
}

export function normalizeExchangeRequests(exchangeRequests = []) {
  if (!Array.isArray(exchangeRequests)) return [];
  return exchangeRequests.map(normalizeExchangeRequest);
}

export function normalizeExchangeRequest(request = {}) {
  return {
    id: String(request.id || `EX-${crypto.randomUUID().slice(0, 8).toUpperCase()}`),
    orderId: String(request.orderId || "").trim(),
    orderItemId: String(request.orderItemId || "").trim(),
    buyerUserId: String(request.buyerUserId || "").trim(),
    sellerUserId: String(request.sellerUserId || "").trim(),
    productId: String(request.productId || "").trim(),
    productTitle: String(request.productTitle || "").trim(),
    productImageURL: normalizeOptionalString(request.productImageURL),
    originalVariantSnapshot: normalizeStringMap(request.originalVariantSnapshot),
    reasonCode: normalizeEnum(
      request.reasonCode,
      ["damaged", "defective", "wrong_item", "poor_quality", "missing_part", "other"],
      "other"
    ),
    buyerExplanation: String(request.buyerExplanation || "").trim(),
    requestedResolution: normalizeEnum(
      request.requestedResolution,
      ["same_item_exchange"],
      "same_item_exchange"
    ),
    status: normalizeEnum(
      request.status,
      [
        "draft",
        "submitted",
        "awaiting_buyer_proof",
        "under_review",
        "awaiting_seller_response",
        "approved",
        "denied",
        "replacement_preparing",
        "replacement_shipped",
        "replacement_delivered",
        "closed",
        "cancelled",
      ],
      "draft"
    ),
    denialReason: normalizeOptionalString(request.denialReason),
    adminNotes: normalizeOptionalString(request.adminNotes),
    sellerNotes: normalizeOptionalString(request.sellerNotes),
    buyerProofAssets: Array.isArray(request.buyerProofAssets)
      ? request.buyerProofAssets.map(normalizeExchangeProofAsset)
      : [],
    buyerSubmittedAt: normalizeOptionalTimestamp(request.buyerSubmittedAt),
    reviewedAt: normalizeOptionalTimestamp(request.reviewedAt),
    approvedAt: normalizeOptionalTimestamp(request.approvedAt),
    deniedAt: normalizeOptionalTimestamp(request.deniedAt),
    replacementShippedAt: normalizeOptionalTimestamp(request.replacementShippedAt),
    replacementDeliveredAt: normalizeOptionalTimestamp(request.replacementDeliveredAt),
    closedAt: normalizeOptionalTimestamp(request.closedAt),
    eligibilityCheckedAt: normalizeOptionalTimestamp(request.eligibilityCheckedAt),
    eligibleAtSubmission: Boolean(request.eligibleAtSubmission),
    eligibilityFailureReason: normalizeOptionalString(request.eligibilityFailureReason),
    exchangeNumberForOrder: Number.isFinite(Number(request.exchangeNumberForOrder))
      ? Number(request.exchangeNumberForOrder)
      : 0,
    isAdminOverride: Boolean(request.isAdminOverride),
    trackingNumber: normalizeOptionalString(request.trackingNumber),
    shippingCarrier: normalizeOptionalString(request.shippingCarrier),
    replacementOrderId: normalizeOptionalString(request.replacementOrderId),
    timelineEvents: Array.isArray(request.timelineEvents)
      ? request.timelineEvents.map(normalizeExchangeTimelineEvent)
      : [],
    createdAt: normalizeTimestamp(request.createdAt),
    updatedAt: normalizeTimestamp(request.updatedAt),
  };
}

export function normalizeExchangeProofAsset(asset = {}) {
  return {
    id: String(asset.id || crypto.randomUUID()),
    type: normalizeEnum(asset.type, ["image", "video"], "image"),
    url: String(asset.url || "").trim(),
    storagePath: String(asset.storagePath || "").trim(),
    thumbnailURL: normalizeOptionalString(asset.thumbnailURL),
    uploadedAt: normalizeTimestamp(asset.uploadedAt),
    uploadedByUserId: String(asset.uploadedByUserId || "").trim(),
  };
}

export function normalizeExchangeTimelineEvent(event = {}) {
  return {
    id: String(event.id || crypto.randomUUID()),
    type: normalizeEnum(
      event.type,
      [
        "request_created",
        "request_submitted",
        "proof_uploaded",
        "buyer_message",
        "seller_message",
        "admin_review_started",
        "request_approved",
        "request_denied",
        "replacement_started",
        "tracking_added",
        "replacement_shipped",
        "replacement_delivered",
        "request_closed",
        "request_cancelled",
        "admin_override",
        "status_changed",
      ],
      "status_changed"
    ),
    message: String(event.message || "").trim(),
    actorType: normalizeEnum(event.actorType, ["buyer", "seller", "admin", "system"], "system"),
    actorId: normalizeOptionalString(event.actorId),
    createdAt: normalizeTimestamp(event.createdAt),
  };
}

export function createExchangeTimelineEvent(type, message, actorType = "system", actorId = null) {
  return normalizeExchangeTimelineEvent({
    id: crypto.randomUUID(),
    type,
    message,
    actorType,
    actorId,
    createdAt: new Date().toISOString(),
  });
}

export function exchangeBuyerUserId(email) {
  const normalized = String(email || "").trim().toLowerCase();
  return normalized ? `buyer:${normalized}` : "guest";
}

export function exchangeSellerUserId(sellerId) {
  const normalized = String(sellerId || "").trim();
  return normalized ? `seller:${normalized}` : "";
}

export function attachExchangeSummariesToOrders(orders = [], exchangeRequests = [], rawConfig = {}) {
  const config = mergeExchangeConfig(rawConfig);
  const normalizedRequests = normalizeExchangeRequests(exchangeRequests);

  return (Array.isArray(orders) ? orders : []).map((order) => {
    const shipments = Array.isArray(order.shipments) ? order.shipments : [];
    const shipmentDeliveredAtValues = shipments
      .map((shipment) => shipment?.deliveredAt || null)
      .filter(Boolean);
    const latestDeliveredAt = shipmentDeliveredAtValues.length
      ? shipmentDeliveredAtValues.sort().slice(-1)[0]
      : null;

    const nextShipments = shipments.map((shipment) => {
      const itemDeliveredAt = normalizeOptionalTimestamp(shipment.deliveredAt);
      const nextItems = (Array.isArray(shipment.items) ? shipment.items : []).map((item) => {
        const itemRequests = normalizedRequests.filter(
          (request) => request.orderId === order.id && request.orderItemId === item.id
        );
        const latestRequest = latestExchangeRequest(itemRequests);
        const completedExchangeCount = itemRequests.filter((request) =>
          COMPLETED_EXCHANGE_STATUSES.has(request.status)
        ).length;
        const isActive = itemRequests.some((request) => ACTIVE_EXCHANGE_STATUSES.has(request.status));
        const exchangeEligibleUntil = computeExchangeEligibleUntil(itemDeliveredAt, config.exchangeWindowDays);

        return {
          ...item,
          fulfillmentStatus: item.fulfillmentStatus || shipment.status || null,
          deliveredAt: item.deliveredAt || itemDeliveredAt,
          orderStatus: item.orderStatus || order.status || null,
          exchangeEligibleUntil: item.exchangeEligibleUntil || exchangeEligibleUntil,
          hasExchangeRequest: item.hasExchangeRequest ?? (isActive || completedExchangeCount > 0),
          exchangeRequestId: item.exchangeRequestId || latestRequest?.id || null,
          exchangeCount:
            Number.isFinite(Number(item.exchangeCount)) && Number(item.exchangeCount) >= 0
              ? Number(item.exchangeCount)
              : completedExchangeCount,
        };
      });

      return {
        ...shipment,
        items: nextItems,
      };
    });

    const flattenedItems = nextShipments.flatMap((shipment) => shipment.items || []);
    const orderRequests = normalizedRequests.filter((request) => request.orderId === order.id);
    const latestOrderRequest = latestExchangeRequest(orderRequests);
    const orderExchangeCount = flattenedItems.reduce(
      (total, item) => total + (Number(item.exchangeCount) || 0),
      0
    );
    const hasExchangeRequest = flattenedItems.some((item) => Boolean(item.hasExchangeRequest));
    const orderEligibleUntil = flattenedItems
      .map((item) => item.exchangeEligibleUntil || null)
      .filter(Boolean)
      .sort()
      .slice(-1)[0] || null;

    return {
      ...order,
      shipments: nextShipments,
      deliveredAt: order.deliveredAt || latestDeliveredAt,
      exchangeEligibleUntil: order.exchangeEligibleUntil || orderEligibleUntil,
      hasExchangeRequest: order.hasExchangeRequest ?? hasExchangeRequest,
      exchangeRequestId: order.exchangeRequestId || latestOrderRequest?.id || null,
      exchangeCount:
        Number.isFinite(Number(order.exchangeCount)) && Number(order.exchangeCount) >= 0
          ? Number(order.exchangeCount)
          : orderExchangeCount,
    };
  });
}

export function evaluateExchangeEligibility({
  orders = [],
  exchangeRequests = [],
  buyerEmail,
  orderId,
  orderItemId,
  requestedResolution = "same_item_exchange",
  config = {},
  isAdminOverride = false,
} = {}) {
  const exchangeConfig = mergeExchangeConfig(config);
  const normalizedBuyerEmail = String(buyerEmail || "").trim().toLowerCase();
  const normalizedOrderId = String(orderId || "").trim();
  const normalizedOrderItemId = String(orderItemId || "").trim();

  if (requestedResolution !== "same_item_exchange" && !isAdminOverride) {
    return ineligible("same_item_only", "Approved exchanges are replacements of the same item only.");
  }

  const order = (Array.isArray(orders) ? orders : []).find((candidate) => candidate.id === normalizedOrderId);
  if (!order) {
    return ineligible("order_not_found", "We couldn't find that order.");
  }

  const orderBuyerEmail = String(order.buyerEmail || "").trim().toLowerCase();
  if (!isAdminOverride && normalizedBuyerEmail && orderBuyerEmail !== normalizedBuyerEmail) {
    return ineligible("unauthorized", "That order is not available for this account.");
  }

  if (!isAdminOverride && isBlockedOrder(order)) {
    return ineligible("order_ineligible", "This order isn't eligible for an exchange request.");
  }

  const shipment = (Array.isArray(order.shipments) ? order.shipments : []).find((candidate) =>
    (Array.isArray(candidate.items) ? candidate.items : []).some((item) => item.id === normalizedOrderItemId)
  );
  const item = shipment?.items?.find((candidate) => candidate.id === normalizedOrderItemId);
  if (!shipment || !item) {
    return ineligible("order_not_found", "We couldn't find that order item.");
  }

  if (!isAdminOverride && isUnsupportedItemType(item)) {
    return ineligible("unsupported_item_type", "This item type is not eligible for exchange requests.");
  }

  const deliveredAt = normalizeOptionalTimestamp(item.deliveredAt || shipment.deliveredAt || null);
  const exchangeEligibleUntil = computeExchangeEligibleUntil(deliveredAt, exchangeConfig.exchangeWindowDays);
  const itemRequests = normalizeExchangeRequests(exchangeRequests).filter(
    (request) => request.orderId === order.id && request.orderItemId === item.id
  );
  const completedExchangeCount = itemRequests.filter((request) =>
    COMPLETED_EXCHANGE_STATUSES.has(request.status)
  ).length;
  const hasActiveExchange = itemRequests.some((request) => ACTIVE_EXCHANGE_STATUSES.has(request.status));

  if (!isAdminOverride && !deliveredAt) {
    return ineligible(
      "not_delivered",
      "Exchanges can be requested after delivery.",
      exchangeEligibleUntil,
      completedExchangeCount,
      exchangeConfig
    );
  }

  if (
    !isAdminOverride &&
    exchangeEligibleUntil &&
    new Date(exchangeEligibleUntil).getTime() < Date.now()
  ) {
    return ineligible(
      "outside_window",
      "The exchange window has ended for this item.",
      exchangeEligibleUntil,
      completedExchangeCount,
      exchangeConfig
    );
  }

  if (!isAdminOverride && hasActiveExchange) {
    return ineligible(
      "active_exchange_exists",
      "This item already has an active exchange request.",
      exchangeEligibleUntil,
      completedExchangeCount,
      exchangeConfig
    );
  }

  if (!isAdminOverride && completedExchangeCount >= exchangeConfig.maxExchangeCountPerOrderItem) {
    return ineligible(
      "already_exchanged",
      "This item has already used its one-time exchange.",
      exchangeEligibleUntil,
      completedExchangeCount,
      exchangeConfig
    );
  }

  return {
    isEligible: true,
    failureCode: null,
    failureMessage: null,
    exchangeEligibleUntil,
    exchangeCount: completedExchangeCount,
    needsAdminReview: Boolean(exchangeConfig.requireAdminForApproval),
    allowedResolutionTypes: ["same_item_exchange"],
  };
}

export function isActiveExchangeStatus(status) {
  return ACTIVE_EXCHANGE_STATUSES.has(String(status || "").trim());
}

function ineligible(failureCode, failureMessage, exchangeEligibleUntil = null, exchangeCount = 0, config = {}) {
  const normalizedConfig = mergeExchangeConfig(config);
  return {
    isEligible: false,
    failureCode,
    failureMessage,
    exchangeEligibleUntil,
    exchangeCount,
    needsAdminReview: Boolean(normalizedConfig.requireAdminForApproval),
    allowedResolutionTypes: ["same_item_exchange"],
  };
}

function latestExchangeRequest(requests = []) {
  if (!requests.length) return null;
  return [...requests].sort((lhs, rhs) => {
    const lhsTime = new Date(lhs.updatedAt || lhs.createdAt || 0).getTime();
    const rhsTime = new Date(rhs.updatedAt || rhs.createdAt || 0).getTime();
    return rhsTime - lhsTime;
  })[0];
}

function computeExchangeEligibleUntil(deliveredAt, exchangeWindowDays) {
  const deliveredDate = normalizeOptionalTimestamp(deliveredAt);
  if (!deliveredDate) return null;
  const deliveredMs = new Date(deliveredDate).getTime();
  if (!Number.isFinite(deliveredMs)) return null;
  return new Date(deliveredMs + exchangeWindowDays * 24 * 60 * 60 * 1000).toISOString();
}

function isBlockedOrder(order = {}) {
  return Boolean(order.isCancelled || order.cancelledAt || order.fraudFlagged || order.isTestOrder);
}

function isUnsupportedItemType(item = {}) {
  const rawType = String(item.itemType || item.productType || "").trim().toLowerCase();
  return rawType === "digital" || rawType === "non_physical";
}

function normalizeStringMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .map(([key, entryValue]) => [String(key).trim(), normalizeOptionalString(entryValue)])
      .filter(([key, entryValue]) => key && entryValue != null)
  );
}

function normalizeOptionalString(value) {
  const normalized = String(value ?? "").trim();
  return normalized ? normalized : null;
}

function normalizeTimestamp(value) {
  const normalized = normalizeOptionalTimestamp(value);
  return normalized || new Date().toISOString();
}

function normalizeOptionalTimestamp(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) return null;
  return date.toISOString();
}

function normalizeEnum(value, allowedValues, fallbackValue) {
  const normalized = String(value || "").trim().toLowerCase();
  return allowedValues.includes(normalized) ? normalized : fallbackValue;
}

function asPositiveInteger(value, fallbackValue) {
  const normalized = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(normalized) && normalized > 0 ? normalized : fallbackValue;
}
