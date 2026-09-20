import { getTransactionalEmailConfig } from "./emailConfig.js";
import { buyerFirstName } from "./buyerWelcomeEmail.js";
import { emailButton, emailCard, escapeHtml, renderTransactionalEmail } from "./emailHtml.js";
import { customerFacingOrderNumber } from "../../domain/phase1/orderNumber.js";

export const ORDER_CONFIRMATION_PREVIEW =
  "We've received your TenBelow order. Here's what happens next.";

export function orderConfirmationEmailSubject(displayNumber = "") {
  const label = String(displayNumber || "").trim();
  return label ? `Order confirmed ❄️ TenBelow #${label}` : "Order confirmed ❄️ TenBelow";
}

export function orderConfirmationIdempotencyKey(orderId = "") {
  return `order-confirmation:${String(orderId || "").trim()}`;
}

export function normalizeOrderConfirmationEmailFields(record = {}) {
  const confirmation = record.confirmationEmail || {};
  return {
    status: confirmation.status || (confirmation.sentAt ? "sent" : "pending"),
    sentAt: confirmation.sentAt || null,
    messageId: confirmation.messageId || null,
    lastError: confirmation.lastError || null,
  };
}

export function formatMoneyCents(cents, currency = "USD") {
  const amount = Math.max(0, Math.floor(Number(cents) || 0)) / 100;
  const code = String(currency || "USD").trim().toUpperCase() || "USD";
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: code }).format(amount);
  } catch {
    return `$${amount.toFixed(2)}`;
  }
}

export function resolveEmailAssetURL(url) {
  const raw = String(url || "").trim();
  if (!raw) return null;
  if (!/^https?:\/\//i.test(raw)) return null;
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
    if (!parsed.hostname) return null;
    return parsed.href;
  } catch {
    return null;
  }
}

function formatOrderDate(isoString) {
  const parsed = new Date(isoString || Date.now());
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toLocaleString("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/New_York",
  });
}

function formatShipByDate(isoString) {
  const parsed = new Date(isoString || "");
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toLocaleDateString("en-US", {
    dateStyle: "medium",
    timeZone: "America/New_York",
  });
}

function shippingAddressLines(shippingAddress = {}) {
  const lines = [];
  const name = String(shippingAddress.name || "").trim();
  const line1 = String(shippingAddress.line1 || "").trim();
  const line2 = String(shippingAddress.line2 || "").trim();
  const city = String(shippingAddress.city || "").trim();
  const state = String(shippingAddress.state || "").trim();
  const postalCode = String(shippingAddress.postalCode || "").trim();
  const country = String(shippingAddress.country || "").trim();

  if (name) lines.push(name);
  if (line1) lines.push(line1);
  if (line2) lines.push(line2);
  const cityLine = [city, state, postalCode].filter(Boolean).join(", ");
  if (cityLine) lines.push(cityLine);
  if (country) lines.push(country);
  return lines;
}

function variantLabel(item = {}) {
  const name = String(item.selectedColorName || "").trim();
  if (!name) return "";
  return name;
}

function lineItemRow(item) {
  const qty = Math.max(1, Math.floor(Number(item.quantity) || 1));
  const unitCents = Math.max(0, Math.floor(Number(item.unitPriceCents ?? item.priceCents) || 0));
  const lineTotal = unitCents * qty;
  const variant = variantLabel(item);
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
          <p style="margin:0;">Qty ${qty} · ${escapeHtml(formatMoneyCents(unitCents))} each · ${escapeHtml(formatMoneyCents(lineTotal))}</p>
        </td>
      </tr>
    </table>
  `;
}

function shipmentBlocks(order = {}) {
  const shipments = Array.isArray(order.shipments) ? order.shipments : [];
  if (!shipments.length) return `<p style="margin:0;">Your order details will appear in the TenBelow app.</p>`;

  return shipments
    .map((shipment) => {
      const sellerName = String(shipment.sellerName || shipment.sellerId || "Independent creator").trim();
      const items = Array.isArray(shipment.items) ? shipment.items : [];
      const itemHtml = items.map((item) => lineItemRow(item)).join("");
      const shipBy = formatShipByDate(shipment.shipByDate);
      const shipByLine = shipBy
        ? `<p style="margin:8px 0 0 0;font-size:14px;color:#5b7694;">Estimated prepare-by: ${escapeHtml(shipBy)}</p>`
        : "";

      return `
        <div style="margin:0 0 14px 0;padding-bottom:12px;border-bottom:1px solid #e3f0fb;">
          <p style="margin:0 0 8px 0;font-weight:700;color:#0b4f8a;">${escapeHtml(sellerName)}</p>
          ${itemHtml}
          ${shipByLine}
        </div>
      `;
    })
    .join("");
}

function paymentSummaryHtml(paymentSummary = {}, currency = "USD") {
  const subtotal = Math.max(0, Math.floor(Number(paymentSummary.subtotalCents) || 0));
  const shipping = Math.max(0, Math.floor(Number(paymentSummary.shippingCents) || 0));
  const total = Math.max(0, Math.floor(Number(paymentSummary.totalCents) || 0));
  const cur = String(paymentSummary.currency || currency || "USD").toUpperCase();

  const row = (label, cents, { strong = false } = {}) => `
    <tr>
      <td style="padding:4px 0;font-size:15px;color:#23486b;">${escapeHtml(label)}</td>
      <td align="right" style="padding:4px 0;font-size:15px;color:#23486b;${strong ? "font-weight:700;color:#0b4f8a;font-size:17px;" : ""}">${escapeHtml(formatMoneyCents(cents, cur))}</td>
    </tr>
  `;

  return `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
      ${row("Subtotal", subtotal)}
      ${row("Shipping", shipping)}
      ${row("Total paid", total, { strong: true })}
    </table>
  `;
}

export function buildOrderConfirmationEmailHtml({
  order = {},
  buyer = {},
  paymentSummary = {},
  shippingAddress = {},
  config = getTransactionalEmailConfig(),
} = {}) {
  const firstName = buyerFirstName(buyer?.fullName);
  const greetingName = firstName || "there";
  const displayNumber = customerFacingOrderNumber(order);
  const orderDate = formatOrderDate(order.createdAt);
  const addressLines = shippingAddressLines(shippingAddress);
  const ordersDestination = config.ordersUrl || config.websiteUrl || config.shopUrl;
  const orderLabelHtml = displayNumber
    ? `<p style="margin:0 0 10px 0;"><strong>Order:</strong> ${escapeHtml(displayNumber)}</p>`
    : `<p style="margin:0 0 10px 0;"><strong>Your TenBelow order</strong></p>`;

  const sectionsHtml = [
    emailCard(
      "Order summary",
      `
        ${orderLabelHtml}
        ${orderDate ? `<p style="margin:0 0 12px 0;"><strong>Placed:</strong> ${escapeHtml(orderDate)}</p>` : ""}
        ${shipmentBlocks(order)}
      `,
      { featured: true }
    ),
    emailCard("Payment", paymentSummaryHtml(paymentSummary, order.currency)),
    emailCard(
      "Ship to",
      addressLines.length
        ? `<p style="margin:0;white-space:pre-line;">${addressLines.map((line) => escapeHtml(line)).join("\n")}</p>`
        : `<p style="margin:0;">Shipping details are saved to your TenBelow order.</p>`
    ),
    emailCard(
      "What's next",
      `
        <p style="margin:0 0 10px 0;">TenBelow products are made and fulfilled by independent creators, so processing times can vary by item.</p>
        <p style="margin:0 0 10px 0;">You can follow your order status in TenBelow. Tracking information will appear when it becomes available.</p>
        <p style="margin:0;">${emailButton("View Order", ordersDestination, { primary: true })}</p>
        <p style="margin:10px 0 0 0;font-size:13px;color:#5b7694;">Open the TenBelow app and go to <strong>Orders</strong> to see this purchase.</p>
      `
    ),
    emailCard(
      "Need help with your order?",
      `
        <p style="margin:0 0 8px 0;">For order questions, open your order in the TenBelow app to message the seller or contact support at <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;text-decoration:none;">${escapeHtml(config.supportEmail)}</a>.</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config,
    title: orderConfirmationEmailSubject(displayNumber),
    previewText: ORDER_CONFIRMATION_PREVIEW,
    heading: "Order confirmed ❄️",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">Thanks for your order, ${escapeHtml(greetingName)}. We&rsquo;ve received your order and your creator(s) can now begin preparing it.</p>`,
    sectionsHtml,
  });
}

export async function deliverBuyerOrderConfirmationEmail({
  orderId,
  buyerEmail,
  paymentSummary,
  shippingAddress,
  paymentIntentId = "",
  loadBuyersFile,
  loadOrdersFile,
  saveOrdersFile,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  const normalizedOrderId = String(orderId || "").trim();
  const normalizedEmail = String(buyerEmail || "").trim().toLowerCase();
  if (!normalizedOrderId || !normalizedEmail) {
    return { skipped: true, reason: "missing_order_or_email" };
  }

  const orders = loadOrdersFile();
  const orderIndex = orders.findIndex((entry) => entry.id === normalizedOrderId);
  if (orderIndex < 0) {
    return { skipped: true, reason: "order_not_found" };
  }

  const order = orders[orderIndex];
  const confirmation = normalizeOrderConfirmationEmailFields(order);
  if (confirmation.status === "sent") {
    return { skipped: true, reason: "already_sent" };
  }

  const buyers = loadBuyersFile();
  const buyer = buyers[normalizedEmail] || { email: normalizedEmail, fullName: "" };

  const html = buildOrderConfirmationEmailHtml({
    order,
    buyer,
    paymentSummary,
    shippingAddress,
    config,
  });

  try {
    const result = await sendTransactionalEmail({
      to: normalizedEmail,
      subject: orderConfirmationEmailSubject(customerFacingOrderNumber(order)),
      html,
      idempotencyKey: orderConfirmationIdempotencyKey(normalizedOrderId),
    });

    orders[orderIndex] = {
      ...order,
      confirmationEmail: {
        status: "sent",
        sentAt: new Date().toISOString(),
        messageId: result?.messageId || null,
        lastError: null,
        paymentIntentId: String(paymentIntentId || "").trim() || null,
      },
    };
    saveOrdersFile(orders);

    return { sent: true, messageId: result?.messageId || null };
  } catch (error) {
    orders[orderIndex] = {
      ...order,
      confirmationEmail: {
        ...confirmation,
        status: "failed",
        lastError: String(error?.message || error || "Order confirmation email failed"),
        paymentIntentId: String(paymentIntentId || "").trim() || confirmation.paymentIntentId || null,
      },
    };
    saveOrdersFile(orders);
    console.error(`order confirmation email failed orderId=${normalizedOrderId}:`, error?.message || error);
    return { sent: false, error: String(error?.message || error || "Order confirmation email failed") };
  }
}
