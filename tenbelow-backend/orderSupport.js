/**
 * Order-scoped support: cancel/refund requests and buyer↔seller message threads.
 */

const SUPPORT_REQUEST_TYPES = new Set(["cancel", "refund"]);
const SUPPORT_REQUEST_STATUSES = new Set(["pending", "approved", "denied", "withdrawn"]);

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
  return {
    id: String(record.id || "").trim(),
    type: SUPPORT_REQUEST_TYPES.has(type) ? type : "cancel",
    status: SUPPORT_REQUEST_STATUSES.has(status) ? status : "pending",
    sellerId: String(record.sellerId || "").trim(),
    shipmentId: String(record.shipmentId || "").trim() || null,
    reason: String(record.reason || "").trim(),
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

export function validateSupportRequestCreate({ type, reason, shipment, existingRequests, sellerId }) {
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
  if (normalizedType === "cancel" && !canRequestCancelForShipment(shipment)) {
    return { ok: false, error: "Cancel requests are only available before an item ships" };
  }
  if (normalizedType === "refund" && !canRequestRefundForShipment(shipment)) {
    return { ok: false, error: "Refund requests are available after an item has shipped" };
  }
  const duplicatePending = existingRequests.some(
    (request) =>
      request.status === "pending" &&
      request.type === normalizedType &&
      request.sellerId === sellerId &&
      (request.shipmentId ? request.shipmentId === shipment.id : true)
  );
  if (duplicatePending) {
    return { ok: false, error: "A pending request of this type already exists for this shipment" };
  }
  return { ok: true, type: normalizedType, reason: trimmedReason };
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
