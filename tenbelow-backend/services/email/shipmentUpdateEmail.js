import { customerFacingOrderNumber } from "../../domain/phase1/orderNumber.js";
import { buyerFirstName } from "./buyerWelcomeEmail.js";
import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailButton, emailCard, escapeHtml, renderTransactionalEmail } from "./emailHtml.js";
import { resolveEmailAssetURL } from "./orderConfirmationEmail.js";

export function shipmentShippedEmailPreviewText({ isEntireOrderShipped = false } = {}) {
  return isEntireOrderShipped
    ? "Good news — your TenBelow order has shipped."
    : "Good news — part of your TenBelow order has shipped.";
}

export function shipmentShippedEmailSubject(displayNumber = "") {
  const label = String(displayNumber || "").trim();
  return label
    ? `Your TenBelow order ${label} is on the way ❄️`
    : "Your TenBelow order is on the way ❄️";
}

export function shipmentShippedIdempotencyKey(orderId = "", shipmentId = "") {
  return `shipment-shipped:${String(orderId || "").trim()}:${String(shipmentId || "").trim()}`;
}

export function normalizeShipmentShippedEmailFields(record = {}) {
  const state = record.shippedEmail || record || {};
  return {
    status: state.status || (state.sentAt ? "sent" : "pending"),
    sentAt: state.sentAt || null,
    messageId: state.messageId || null,
    lastError: state.lastError || null,
    attemptCount: Math.max(0, Math.floor(Number(state.attemptCount) || 0)),
  };
}

function shipmentStatus(shipment = {}) {
  return String(shipment?.status || "").trim().toLowerCase();
}

export function activeShipments(order = {}) {
  return (Array.isArray(order.shipments) ? order.shipments : []).filter(
    (shipment) => shipmentStatus(shipment) !== "cancelled"
  );
}

export function findShipment(order = {}, shipmentId = "") {
  const target = String(shipmentId || "").trim();
  return (Array.isArray(order.shipments) ? order.shipments : []).find(
    (shipment) => String(shipment?.id || "").trim() === target
  ) || null;
}

export function isEntireOrderShipped(order = {}) {
  const active = activeShipments(order);
  if (!active.length) return false;
  return active.every((shipment) => {
    const status = shipmentStatus(shipment);
    return status === "shipped" || status === "delivered";
  });
}

export function remainingUnshippedShipments(order = {}, shippedShipmentId = "") {
  const target = String(shippedShipmentId || "").trim();
  return activeShipments(order).filter((shipment) => {
    if (String(shipment?.id || "").trim() === target) return false;
    const status = shipmentStatus(shipment);
    return status !== "shipped" && status !== "delivered";
  });
}

function lineItemRow(item) {
  const qty = Math.max(1, Math.floor(Number(item.quantity) || 1));
  const variant = String(item.selectedColorName || "").trim();
  const imageUrl = resolveEmailAssetURL(item.thumbnailURL);
  const imageCell = imageUrl
    ? `<td width="56" valign="top" style="padding:0 12px 12px 0;">
        <img src="${escapeHtml(imageUrl)}" alt="" width="48" height="48" style="display:block;border-radius:10px;border:1px solid #d5e8fb;object-fit:cover;" />
      </td>`
    : "";

  return `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 12px 0;border-collapse:collapse;">
      <tr>
        ${imageCell}
        <td valign="top" style="padding:0 0 12px 0;font-size:15px;line-height:1.5;color:#23486b;">
          <p style="margin:0 0 4px 0;font-weight:700;color:#0b4f8a;">${escapeHtml(item.productName || item.name || "Item")}</p>
          ${variant ? `<p style="margin:0 0 4px 0;">Option: ${escapeHtml(variant)}</p>` : ""}
          <p style="margin:0;">Qty ${qty}</p>
        </td>
      </tr>
    </table>
  `;
}

function trackingSectionHtml(shipment = {}) {
  const carrier = String(shipment.carrier || "").trim();
  const trackingNumber = String(shipment.trackingNumber || "").trim();
  if (!carrier && !trackingNumber) {
    return `<p style="margin:0;">Tracking information wasn&rsquo;t provided for this shipment. You can continue following its status in TenBelow.</p>`;
  }

  return `
    ${carrier ? `<p style="margin:0 0 6px 0;"><strong>Carrier:</strong> ${escapeHtml(carrier)}</p>` : ""}
    ${trackingNumber ? `<p style="margin:0;"><strong>Tracking number:</strong> ${escapeHtml(trackingNumber)}</p>` : ""}
  `;
}

function destinationHtml(order = {}) {
  const city = String(order.shipToCity || "").trim();
  const state = String(order.shipToState || "").trim();
  const line = [city, state].filter(Boolean).join(", ");
  if (!line) return "";
  return `<p style="margin:0;">${escapeHtml(line)}</p>`;
}

export function buildShipmentShippedEmailHtml({
  order = {},
  shipment = {},
  buyer = {},
  config = getTransactionalEmailConfig(),
} = {}) {
  const firstName = buyerFirstName(buyer?.fullName);
  const greetingName = firstName || "there";
  const displayNumber = customerFacingOrderNumber(order);
  const sellerName = String(shipment.sellerName || "A creator").trim() || "A creator";
  const entireOrderShipped = isEntireOrderShipped(order);
  const remaining = remainingUnshippedShipments(order, shipment.id);
  const items = Array.isArray(shipment.items) ? shipment.items : [];
  const ordersDestination = config.ordersUrl || config.websiteUrl || config.shopUrl;
  const orderLabel = displayNumber ? `Order ${escapeHtml(displayNumber)}` : "Your TenBelow order";
  const greeting = entireOrderShipped
    ? `Good news, ${escapeHtml(greetingName)} &mdash; your TenBelow order has shipped.`
    : `Good news, ${escapeHtml(greetingName)} &mdash; ${escapeHtml(sellerName)} has shipped their part of your TenBelow order.`;

  const sectionsHtml = [
    emailCard(
      orderLabel,
      `
        <p style="margin:0 0 10px 0;font-weight:700;color:#0b4f8a;">${escapeHtml(sellerName)}</p>
        ${items.map((item) => lineItemRow(item)).join("") || `<p style="margin:0;">This shipment will appear in TenBelow.</p>`}
      `,
      { featured: true }
    ),
    emailCard("Tracking", trackingSectionHtml(shipment)),
    destinationHtml(order) ? emailCard("Shipping to", destinationHtml(order)) : "",
    remaining.length
      ? emailCard(
          "The rest of your order",
          `<p style="margin:0;">Other items in this order are still being prepared and will update separately.</p>`
        )
      : "",
    emailCard(
      "Follow this shipment",
      `
        <p style="margin:0;">${emailButton("View Order", ordersDestination, { primary: true })}</p>
        <p style="margin:10px 0 0 0;font-size:13px;color:#5b7694;">Open the TenBelow app and go to <strong>Orders</strong> to follow this shipment.</p>
      `
    ),
    emailCard(
      "Need help with this shipment?",
      `
        <p style="margin:0;">For questions about this shipment, message the seller from your order in TenBelow or contact support at <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;text-decoration:none;">${escapeHtml(config.supportEmail)}</a>.</p>
      `
    ),
  ]
    .filter(Boolean)
    .join("");

  return renderTransactionalEmail({
    config,
    title: shipmentShippedEmailSubject(displayNumber),
    previewText: shipmentShippedEmailPreviewText({ isEntireOrderShipped: entireOrderShipped }),
    heading: "It's on the way! ❄️",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">${greeting}</p>`,
    sectionsHtml,
  });
}

function writeShipmentEmailState(orders, orderIndex, shipmentId, state) {
  const order = orders[orderIndex];
  const shipments = (Array.isArray(order.shipments) ? order.shipments : []).map((shipment) => {
    if (String(shipment?.id || "").trim() !== String(shipmentId || "").trim()) return shipment;
    return { ...shipment, shippedEmail: state };
  });
  orders[orderIndex] = { ...order, shipments };
}

export async function deliverBuyerShipmentShippedEmail({
  orderId,
  shipmentId,
  loadBuyersFile,
  loadOrdersFile,
  saveOrdersFile,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  const normalizedOrderId = String(orderId || "").trim();
  const normalizedShipmentId = String(shipmentId || "").trim();
  if (!normalizedOrderId || !normalizedShipmentId) {
    return { skipped: true, reason: "missing_order_or_shipment" };
  }

  const orders = loadOrdersFile();
  const orderIndex = orders.findIndex((entry) => entry.id === normalizedOrderId);
  if (orderIndex < 0) {
    return { skipped: true, reason: "order_not_found" };
  }

  const order = orders[orderIndex];
  const shipment = findShipment(order, normalizedShipmentId);
  if (!shipment) {
    return { skipped: true, reason: "shipment_not_found" };
  }

  const previous = normalizeShipmentShippedEmailFields(shipment.shippedEmail || {});
  if (previous.status === "sent") {
    return { skipped: true, reason: "already_sent", shipmentId: normalizedShipmentId };
  }

  const buyerEmail = String(order.buyerEmail || "").trim().toLowerCase();
  if (!buyerEmail) {
    return { skipped: true, reason: "missing_buyer_email", shipmentId: normalizedShipmentId };
  }

  const buyers = typeof loadBuyersFile === "function" ? loadBuyersFile() : {};
  const buyer = buyers[buyerEmail] || { email: buyerEmail, fullName: "" };
  const html = buildShipmentShippedEmailHtml({
    order,
    shipment,
    buyer,
    config,
  });
  const nextAttemptCount = previous.attemptCount + 1;

  try {
    const result = await sendTransactionalEmail({
      to: buyerEmail,
      subject: shipmentShippedEmailSubject(customerFacingOrderNumber(order)),
      html,
      idempotencyKey: shipmentShippedIdempotencyKey(normalizedOrderId, normalizedShipmentId),
    });

    writeShipmentEmailState(orders, orderIndex, normalizedShipmentId, {
      status: "sent",
      sentAt: new Date().toISOString(),
      messageId: result?.messageId || null,
      lastError: null,
      attemptCount: nextAttemptCount,
    });
    saveOrdersFile(orders);
    return { sent: true, shipmentId: normalizedShipmentId, messageId: result?.messageId || null };
  } catch (error) {
    writeShipmentEmailState(orders, orderIndex, normalizedShipmentId, {
      ...previous,
      status: "failed",
      lastError: String(error?.message || error || "Shipment email failed"),
      attemptCount: nextAttemptCount,
    });
    saveOrdersFile(orders);
    console.error(
      `shipment shipped email failed orderId=${normalizedOrderId} shipmentId=${normalizedShipmentId}:`,
      error?.message || error
    );
    return {
      sent: false,
      shipmentId: normalizedShipmentId,
      error: String(error?.message || error || "Shipment email failed"),
    };
  }
}
