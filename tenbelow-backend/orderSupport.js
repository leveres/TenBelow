/**
 * Order-scoped support: cancel/refund requests and buyer↔seller message threads.
 */

const SUPPORT_REQUEST_TYPES = new Set(["cancel", "refund"]);
const SUPPORT_REQUEST_STATUSES = new Set(["pending", "approved", "denied", "withdrawn"]);

export const REFUND_DAMAGE_REASON_CODES = new Set([
  "damaged",
  "defective",
  "wrong_item",
  "poor_quality",
  "missing_part",
]);

export const MIN_REFUND_EVIDENCE_COUNT = 1;

function normalizeReasonCode(value) {
  const code = String(value || "").trim().toLowerCase();
  return REFUND_DAMAGE_REASON_CODES.has(code) ? code : null;
}

export function normalizeSupportRequest(record = {}) {
  const type = String(record.type || "").trim().toLowerCase();
  const status = String(record.status || "pending").trim().toLowerCase();
  const evidenceAssets = Array.isArray(record.evidenceAssets)
    ? record.evidenceAssets
        .filter((asset) => asset && typeof asset.id === "string" && typeof asset.url === "string")
        .map((asset) => ({
          id: String(asset.id),
          type: String(asset.type || "image").trim().toLowerCase() === "video" ? "video" : "image",
          url: String(asset.url),
          uploadedAt: asset.uploadedAt || new Date().toISOString(),
        }))
    : [];
  const reasonCode = normalizeReasonCode(record.reasonCode);
  return {
    id: String(record.id || "").trim(),
    type: SUPPORT_REQUEST_TYPES.has(type) ? type : "cancel",
    status: SUPPORT_REQUEST_STATUSES.has(status) ? status : "pending",
    sellerId: String(record.sellerId || "").trim(),
    shipmentId: String(record.shipmentId || "").trim() || null,
    reason: String(record.reason || "").trim(),
    reasonCode: reasonCode || null,
    requestedBy: String(record.requestedBy || "buyer").trim().toLowerCase() === "seller" ? "seller" : "buyer",
    resolutionNote: String(record.resolutionNote || "").trim() || null,
    evidenceAssets,
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || record.createdAt || new Date().toISOString(),
  };
}

export function normalizeOrderMessage(record = {}) {
  return {
    id: String(record.id || "").trim(),
    sellerId: String(record.sellerId || "").trim(),
    senderRole: String(record.senderRole || "").trim().toLowerCase() === "seller" ? "seller" : "buyer",
    senderEmail: String(record.senderEmail || "").trim().toLowerCase() || null,
    senderName: String(record.senderName || "").trim() || null,
    text: String(record.text || "").trim(),
    createdAt: record.createdAt || new Date().toISOString(),
  };
}

export function normalizeOrderSupportFields(order = {}) {
  const supportRequests = Array.isArray(order.supportRequests)
    ? order.supportRequests.map((entry) => normalizeSupportRequest(entry)).filter((entry) => entry.id)
    : [];
  const orderMessages = Array.isArray(order.orderMessages)
    ? order.orderMessages.map((entry) => normalizeOrderMessage(entry)).filter((entry) => entry.id && entry.text)
    : [];
  return { supportRequests, orderMessages };
}

export function orderMessagesForSeller(orderMessages, sellerId) {
  const normalizedSellerId = String(sellerId || "").trim();
  return orderMessages
    .filter((message) => message.sellerId === normalizedSellerId)
    .sort((lhs, rhs) => new Date(lhs.createdAt).getTime() - new Date(rhs.createdAt).getTime());
}

export function canRequestCancelForShipment(shipment) {
  const status = String(shipment?.status || "").trim().toLowerCase();
  return status === "preparing";
}

export function canRequestRefundForShipment(shipment) {
  const status = String(shipment?.status || "").trim().toLowerCase();
  return status === "shipped" || status === "delivered";
}

export function isWithinCancellationWindow(orderCreatedAt, cancellationWindowHours = 12) {
  const windowHours = Math.max(0, Number(cancellationWindowHours) || 0);
  if (!windowHours) return true;
  const createdAt = new Date(orderCreatedAt).getTime();
  if (Number.isNaN(createdAt)) return true;
  return Date.now() - createdAt <= windowHours * 60 * 60 * 1000;
}

export function refundRequestsForShipment(existingRequests = [], { sellerId, shipmentId } = {}) {
  const normalizedSellerId = String(sellerId || "").trim();
  const normalizedShipmentId = String(shipmentId || "").trim();
  return existingRequests.filter(
    (request) =>
      request.type === "refund" &&
      request.sellerId === normalizedSellerId &&
      request.shipmentId === normalizedShipmentId &&
      request.status !== "withdrawn"
  );
}

export function hasUsedRefundForShipment(existingRequests = [], { sellerId, shipmentId } = {}) {
  return refundRequestsForShipment(existingRequests, { sellerId, shipmentId }).length > 0;
}

export function evaluateShipmentSupportEligibility({
  shipment,
  orderCreatedAt,
  sellerPolicies = {},
  existingRequests = [],
}) {
  const sellerId = String(shipment?.sellerId || "").trim();
  const shipmentId = String(shipment?.id || "").trim();
  const policies = {
    allowsCancellations: sellerPolicies.allowsCancellations !== false,
    allowsRefunds: sellerPolicies.allowsRefunds === true,
    cancellationWindowHours: Math.max(0, Number(sellerPolicies.cancellationWindowHours) || 12),
  };

  const result = {
    canRequestCancel: false,
    canRequestRefund: false,
    cancelDisabledReason: null,
    refundDisabledReason: null,
  };

  const pendingCancel = existingRequests.some(
    (request) =>
      request.type === "cancel" &&
      request.status === "pending" &&
      request.sellerId === sellerId &&
      request.shipmentId === shipmentId
  );
  const pendingRefund = existingRequests.some(
    (request) =>
      request.type === "refund" &&
      request.status === "pending" &&
      request.sellerId === sellerId &&
      request.shipmentId === shipmentId
  );

  if (!canRequestCancelForShipment(shipment)) {
    result.cancelDisabledReason = "Cancellation is only available before this shipment ships";
  } else if (!policies.allowsCancellations) {
    result.cancelDisabledReason = "This seller does not accept cancellation requests";
  } else if (!isWithinCancellationWindow(orderCreatedAt, policies.cancellationWindowHours)) {
    result.cancelDisabledReason = `The ${policies.cancellationWindowHours}-hour cancellation window has passed`;
  } else if (pendingCancel) {
    result.cancelDisabledReason = "Cancellation request pending";
  } else {
    result.canRequestCancel = true;
  }

  if (!canRequestRefundForShipment(shipment)) {
    result.refundDisabledReason = "Refund requests are available after this shipment ships";
  } else if (!policies.allowsRefunds) {
    result.refundDisabledReason = "This seller does not accept refund requests";
  } else if (hasUsedRefundForShipment(existingRequests, { sellerId, shipmentId })) {
    result.refundDisabledReason = "You already used your one-time refund request for this shipment";
  } else if (pendingRefund) {
    result.refundDisabledReason = "Refund request pending";
  } else {
    result.canRequestRefund = true;
  }

  return result;
}

export function attachSupportEligibilityToOrder(order = {}, sellersMap = {}, normalizePolicies = (seller) => seller?.policies || {}) {
  const support = normalizeOrderSupportFields(order);
  const shipments = (Array.isArray(order.shipments) ? order.shipments : []).map((shipment) => {
    const seller = sellersMap[String(shipment?.sellerId || "").trim()] || {};
    const policies = normalizePolicies(seller);
    return {
      ...shipment,
      supportEligibility: evaluateShipmentSupportEligibility({
        shipment,
        orderCreatedAt: order.createdAt,
        sellerPolicies: policies,
        existingRequests: support.supportRequests,
      }),
    };
  });
  return {
    ...order,
    shipments,
    supportRequests: support.supportRequests,
    orderMessages: support.orderMessages,
  };
}

export function validateSupportRequestCreate({
  type,
  reason,
  reasonCode,
  shipment,
  existingRequests,
  sellerId,
  sellerPolicies = {},
  orderCreatedAt,
}) {
  const normalizedType = String(type || "").trim().toLowerCase();
  const trimmedReason = String(reason || "").trim();
  if (!SUPPORT_REQUEST_TYPES.has(normalizedType)) {
    return { ok: false, error: "Request type must be cancel or refund" };
  }
  if (trimmedReason.length < 8) {
    return { ok: false, error: "Please describe your request in at least 8 characters" };
  }
  if (!shipment || String(shipment.sellerId || "").trim() !== String(sellerId || "").trim()) {
    return { ok: false, error: "Shipment not found for this seller" };
  }

  const eligibility = evaluateShipmentSupportEligibility({
    shipment,
    orderCreatedAt,
    sellerPolicies,
    existingRequests,
  });

  if (normalizedType === "cancel") {
    if (!eligibility.canRequestCancel) {
      return { ok: false, error: eligibility.cancelDisabledReason || "Cancellation is not available" };
    }
  }

  if (normalizedType === "refund") {
    if (!eligibility.canRequestRefund) {
      return { ok: false, error: eligibility.refundDisabledReason || "Refund is not available" };
    }
    const normalizedReasonCode = normalizeReasonCode(reasonCode);
    if (!normalizedReasonCode) {
      return { ok: false, error: "Select a damage or defect reason for refund requests" };
    }
  }

  return {
    ok: true,
    type: normalizedType,
    reason: trimmedReason,
    reasonCode: normalizedType === "refund" ? normalizeReasonCode(reasonCode) : null,
  };
}

export function validateSupportRequestApproval(request = {}) {
  if (request.type !== "refund" || request.status !== "approved") {
    return { ok: true };
  }
  const evidenceCount = Array.isArray(request.evidenceAssets) ? request.evidenceAssets.length : 0;
  if (evidenceCount < MIN_REFUND_EVIDENCE_COUNT) {
    return {
      ok: false,
      error: "Refund requests require at least one photo of the damage before approval",
    };
  }
  if (!request.reasonCode || !REFUND_DAMAGE_REASON_CODES.has(request.reasonCode)) {
    return { ok: false, error: "Refund requests must include a valid damage or defect reason" };
  }
  return { ok: true };
}

export function applyApprovedSupportRequest(order, request) {
  if (request.status !== "approved") {
    return order;
  }
  const shipmentIndex = order.shipments.findIndex((shipment) => shipment.id === request.shipmentId);
  if (shipmentIndex < 0) {
    return order;
  }
  if (request.type === "cancel") {
    order.shipments[shipmentIndex].status = "cancelled";
  }
  order.status = deriveOrderStatusFromShipments(order.shipments, order.status);
  return order;
}

export function deriveOrderStatusFromShipments(shipments, current = "placed") {
  if (!Array.isArray(shipments) || !shipments.length) return current;
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
