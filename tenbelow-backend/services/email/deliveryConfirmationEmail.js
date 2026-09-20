import { customerFacingOrderNumber } from "../../domain/phase1/orderNumber.js";
import { buyerFirstName } from "./buyerWelcomeEmail.js";
import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailButton, emailCard, escapeHtml, renderTransactionalEmail } from "./emailHtml.js";
import { resolveEmailAssetURL } from "./orderConfirmationEmail.js";
import { activeShipments, findShipment } from "./shipmentUpdateEmail.js";

export function deliveryConfirmationEmailPreviewText({ isEntireOrderDelivered = false } = {}) {
  return isEntireOrderDelivered
    ? "Your TenBelow order has been marked delivered."
    : "A shipment from your TenBelow order has been marked delivered.";
}

export function deliveryConfirmationEmailSubject({ isEntireOrderDelivered = false } = {}) {
  return isEntireOrderDelivered
    ? "Delivered ❄️ Your TenBelow order has arrived"
    : "Delivered ❄️ Part of your TenBelow order has arrived";
}

export function deliveryConfirmationIdempotencyKey(orderId = "", shipmentId = "") {
  return `shipment-delivered:${String(orderId || "").trim()}:${String(shipmentId || "").trim()}`;
}

export function normalizeShipmentDeliveredEmailFields(record = {}) {
  const state = record.deliveredEmail || record || {};
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

export function isEntireOrderDelivered(order = {}) {
  const active = activeShipments(order);
  if (!active.length) return false;
  return active.every((shipment) => shipmentStatus(shipment) === "delivered");
}

export function remainingUndeliveredShipments(order = {}, deliveredShipmentId = "") {
  const target = String(deliveredShipmentId || "").trim();
  return activeShipments(order).filter((shipment) => {
    if (String(shipment?.id || "").trim() === target) return false;
    return shipmentStatus(shipment) !== "delivered";
  });
}

export function remainingOrderStatusCopy(order = {}, deliveredShipmentId = "") {
  const remaining = remainingUndeliveredShipments(order, deliveredShipmentId);
  if (!remaining.length) return "";

  const preparing = remaining.some((shipment) => shipmentStatus(shipment) === "preparing");
  const shipped = remaining.some((shipment) => shipmentStatus(shipment) === "shipped");

  if (shipped && preparing) {
    return "Other items in this order are still on the way or being prepared.";
  }
  if (shipped) {
    return "Other items in this order are still on the way.";
  }
  return "Other items in this order are still being prepared.";
}

function formatDeliveredAt(isoString) {
  const parsed = new Date(isoString || "");
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toLocaleString("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/New_York",
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

function compactTrackingHtml(shipment = {}) {
  const carrier = String(shipment.carrier || "").trim();
  const trackingNumber = String(shipment.trackingNumber || "").trim();
  if (!carrier && !trackingNumber) return "";
  const parts = [carrier, trackingNumber].filter(Boolean).map((value) => escapeHtml(value));
  return `<p style="margin:8px 0 0 0;font-size:13px;color:#5b7694;">${parts.join(" · ")}</p>`;
}

export function buildDeliveryConfirmationEmailHtml({
  order = {},
  shipment = {},
  buyer = {},
  config = getTransactionalEmailConfig(),
} = {}) {
  const firstName = buyerFirstName(buyer?.fullName);
  const greetingName = firstName || "there";
  const displayNumber = customerFacingOrderNumber(order);
  const sellerName = String(shipment.sellerName || "A creator").trim() || "A creator";
  const entireOrderDelivered = isEntireOrderDelivered(order);
  const remainingCopy = remainingOrderStatusCopy(order, shipment.id);
  const items = Array.isArray(shipment.items) ? shipment.items : [];
  const deliveredAt = formatDeliveredAt(shipment.deliveredAt);
  const ordersDestination = config.ordersUrl || config.websiteUrl || config.shopUrl;
  const orderLabel = displayNumber ? `Order ${escapeHtml(displayNumber)}` : "Your TenBelow order";
  const greeting = entireOrderDelivered
    ? `Good news, ${escapeHtml(greetingName)} &mdash; your TenBelow order has been marked delivered.`
    : `Good news, ${escapeHtml(greetingName)} &mdash; your shipment from ${escapeHtml(sellerName)} has been marked delivered.`;

  const sectionsHtml = [
    emailCard(
      orderLabel,
      `
        <p style="margin:0 0 10px 0;font-weight:700;color:#0b4f8a;">${escapeHtml(sellerName)}</p>
        ${items.map((item) => lineItemRow(item)).join("") || `<p style="margin:0;">This shipment will appear in TenBelow.</p>`}
      `,
      { featured: true }
    ),
    emailCard(
      "Delivered",
      `
        ${deliveredAt ? `<p style="margin:0;font-size:18px;font-weight:700;color:#0b4f8a;">${escapeHtml(deliveredAt)}</p>` : `<p style="margin:0;">This shipment has been marked delivered in TenBelow.</p>`}
        ${compactTrackingHtml(shipment)}
      `
    ),
    remainingCopy
      ? emailCard("The rest of your order", `<p style="margin:0;">${escapeHtml(remainingCopy)}</p>`)
      : "",
    emailCard(
      "View this order",
      `
        <p style="margin:0;">${emailButton("View Order", ordersDestination, { primary: true })}</p>
        <p style="margin:10px 0 0 0;font-size:13px;color:#5b7694;">Open the TenBelow app and go to <strong>Orders</strong> to see this shipment.</p>
      `
    ),
    emailCard(
      "Something not right?",
      `
        <p style="margin:0 0 10px 0;">If you can&rsquo;t find your package or there&rsquo;s an issue with your order, open the order in TenBelow to contact the seller or TenBelow Support.</p>
        <p style="margin:0 0 8px 0;font-size:13px;color:#5b7694;">Once you&rsquo;ve had a chance to check out your order, you can share your experience in TenBelow.</p>
        <p style="margin:0;">Support: <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;text-decoration:none;">${escapeHtml(config.supportEmail)}</a></p>
      `
    ),
  ]
    .filter(Boolean)
    .join("");

  return renderTransactionalEmail({
    config,
    title: deliveryConfirmationEmailSubject({ isEntireOrderDelivered: entireOrderDelivered }),
    previewText: deliveryConfirmationEmailPreviewText({ isEntireOrderDelivered: entireOrderDelivered }),
    heading: "Delivered! 📦",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">${greeting}</p>`,
    sectionsHtml,
  });
}

function writeDeliveredEmailState(orders, orderIndex, shipmentId, state) {
  const order = orders[orderIndex];
  const shipments = (Array.isArray(order.shipments) ? order.shipments : []).map((shipment) => {
    if (String(shipment?.id || "").trim() !== String(shipmentId || "").trim()) return shipment;
    return { ...shipment, deliveredEmail: state };
  });
  orders[orderIndex] = { ...order, shipments };
}

export async function deliverBuyerDeliveryConfirmationEmail({
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

  const previous = normalizeShipmentDeliveredEmailFields(shipment.deliveredEmail || {});
  if (previous.status === "sent") {
    return { skipped: true, reason: "already_sent", shipmentId: normalizedShipmentId };
  }

  const buyerEmail = String(order.buyerEmail || "").trim().toLowerCase();
  if (!buyerEmail) {
    return { skipped: true, reason: "missing_buyer_email", shipmentId: normalizedShipmentId };
  }

  const buyers = typeof loadBuyersFile === "function" ? loadBuyersFile() : {};
  const buyer = buyers[buyerEmail] || { email: buyerEmail, fullName: "" };
  const html = buildDeliveryConfirmationEmailHtml({
    order,
    shipment,
    buyer,
    config,
  });
  const nextAttemptCount = previous.attemptCount + 1;

  try {
    const result = await sendTransactionalEmail({
      to: buyerEmail,
      subject: deliveryConfirmationEmailSubject({
        isEntireOrderDelivered: isEntireOrderDelivered(order),
      }),
      html,
      idempotencyKey: deliveryConfirmationIdempotencyKey(normalizedOrderId, normalizedShipmentId),
    });

    writeDeliveredEmailState(orders, orderIndex, normalizedShipmentId, {
      status: "sent",
      sentAt: new Date().toISOString(),
      messageId: result?.messageId || null,
      lastError: null,
      attemptCount: nextAttemptCount,
    });
    saveOrdersFile(orders);
    return { sent: true, shipmentId: normalizedShipmentId, messageId: result?.messageId || null };
  } catch (error) {
    writeDeliveredEmailState(orders, orderIndex, normalizedShipmentId, {
      ...previous,
      status: "failed",
      lastError: String(error?.message || error || "Delivery confirmation email failed"),
      attemptCount: nextAttemptCount,
    });
    saveOrdersFile(orders);
    console.error(
      `delivery confirmation email failed orderId=${normalizedOrderId} shipmentId=${normalizedShipmentId}:`,
      error?.message || error
    );
    return {
      sent: false,
      shipmentId: normalizedShipmentId,
      error: String(error?.message || error || "Delivery confirmation email failed"),
    };
  }
}
