import {
  buildAgreementPublicURL,
  getActiveSellerAgreementDocument,
} from "../../legal/sellerAgreementDocuments.js";
import { customerFacingOrderNumber } from "../../domain/phase1/orderNumber.js";
import { sellerFirstName } from "../sellerWelcomeEmail.js";
import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailButton, emailCard, escapeHtml, renderTransactionalEmail } from "./emailHtml.js";
import { formatMoneyCents, resolveEmailAssetURL } from "./orderConfirmationEmail.js";

export const SELLER_NEW_ORDER_PREVIEW =
  "A customer ordered from your TenBelow store. It's time to get it ready.";

export function sellerNewOrderEmailSubject(displayNumber = "") {
  const label = String(displayNumber || "").trim();
  return label ? `You made a sale ❄️ Order ${label}` : "You made a sale ❄️ TenBelow";
}

export function sellerNewOrderIdempotencyKey(orderId = "", sellerId = "") {
  return `seller-new-order:${String(orderId || "").trim()}:${String(sellerId || "").trim()}`;
}

export function normalizeSellerNewOrderEmailFields(record = {}) {
  const state = record || {};
  return {
    status: state.status || (state.sentAt ? "sent" : "pending"),
    sentAt: state.sentAt || null,
    messageId: state.messageId || null,
    lastError: state.lastError || null,
    attemptCount: Math.max(0, Math.floor(Number(state.attemptCount) || 0)),
  };
}

export function sellerShipmentsForSeller(order = {}, sellerId = "") {
  const target = String(sellerId || "").trim();
  return (Array.isArray(order.shipments) ? order.shipments : []).filter(
    (shipment) => String(shipment?.sellerId || "").trim() === target
  );
}

export function uniqueSellerIdsFromOrder(order = {}) {
  const ids = [];
  const seen = new Set();
  for (const shipment of Array.isArray(order.shipments) ? order.shipments : []) {
    const sellerId = String(shipment?.sellerId || "").trim();
    if (!sellerId || seen.has(sellerId)) continue;
    seen.add(sellerId);
    ids.push(sellerId);
  }
  return ids;
}

export function sellerGreetingName(seller = {}) {
  const storeName = String(seller.businessName || seller.profile?.displayName || "").trim();
  if (storeName) return storeName;
  return sellerFirstName(seller.legalName);
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

function formatPrepareByDate(isoString) {
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

function earliestPrepareBy(shipments = []) {
  const sorted = shipments
    .map((shipment) => ({ raw: shipment.shipByDate, label: formatPrepareByDate(shipment.shipByDate) }))
    .filter((entry) => entry.label)
    .sort((a, b) => new Date(a.raw) - new Date(b.raw));
  return sorted[0]?.label || "";
}

function lineItemRow(item) {
  const qty = Math.max(1, Math.floor(Number(item.quantity) || 1));
  const unitCents = Math.max(0, Math.floor(Number(item.unitPriceCents ?? item.priceCents) || 0));
  const lineTotal = unitCents * qty;
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
          <p style="margin:0;">Qty ${qty} · ${escapeHtml(formatMoneyCents(unitCents))} each · ${escapeHtml(formatMoneyCents(lineTotal))}</p>
        </td>
      </tr>
    </table>
  `;
}

function sellerAgreementFooterLink(config) {
  try {
    const document = getActiveSellerAgreementDocument();
    const url = buildAgreementPublicURL(document?.id, config.backendBaseUrl);
    if (!url) return "";
    return `<a href="${escapeHtml(url)}" style="color:#1f7fd4;text-decoration:none;">Seller Agreement</a> · `;
  } catch {
    return "";
  }
}

export function buildSellerNewOrderEmailHtml({
  order = {},
  sellerId = "",
  seller = {},
  shippingAddress = {},
  config = getTransactionalEmailConfig(),
} = {}) {
  const greetingName = sellerGreetingName(seller);
  const displayNumber = customerFacingOrderNumber(order);
  const orderDate = formatOrderDate(order.createdAt);
  const shipments = sellerShipmentsForSeller(order, sellerId);
  const itemsHtml = shipments
    .flatMap((shipment) => (Array.isArray(shipment.items) ? shipment.items : []))
    .map((item) => lineItemRow(item))
    .join("");
  const prepareBy = earliestPrepareBy(shipments);
  const addressLines = shippingAddressLines(shippingAddress);
  const destination = config.sellerOrdersUrl || config.sellerDashboardUrl || config.websiteUrl;
  const orderLabel = displayNumber
    ? `Order ${displayNumber}`
    : "Your TenBelow order";

  const sectionsHtml = [
    emailCard(
      orderLabel,
      `
        ${orderDate ? `<p style="margin:0 0 12px 0;"><strong>Placed:</strong> ${escapeHtml(orderDate)}</p>` : ""}
        ${itemsHtml || `<p style="margin:0;">Your items for this order will appear in TenBelow.</p>`}
      `,
      { featured: true }
    ),
    emailCard(
      "Ship to",
      addressLines.length
        ? `<p style="margin:0;white-space:pre-line;">${addressLines.map((line) => escapeHtml(line)).join("\n")}</p>`
        : `<p style="margin:0;">Open this order in TenBelow to view the shipping destination.</p>`
    ),
    emailCard(
      "Prepare by",
      prepareBy
        ? `
          <p style="margin:0 0 8px 0;font-size:20px;font-weight:700;color:#0b4f8a;">${escapeHtml(prepareBy)}</p>
          <p style="margin:0;">Please have this order prepared for shipment by the date above.</p>
        `
        : `<p style="margin:0;">Please have this order prepared for shipment by the date above.</p>`
    ),
    emailCard(
      "What to do next",
      `
        <ol style="margin:0;padding-left:20px;">
          <li style="margin:0 0 4px 0;">Review the order.</li>
          <li style="margin:0 0 4px 0;">Prepare the item(s).</li>
          <li style="margin:0 0 4px 0;">Package the order securely.</li>
          <li style="margin:0;">Open TenBelow to complete the shipping and fulfillment steps.</li>
        </ol>
      `
    ),
    emailCard(
      "Fulfill this order",
      `
        <p style="margin:0;">${emailButton("View Order", destination, { primary: true })}</p>
        <p style="margin:10px 0 0 0;font-size:13px;color:#5b7694;">Open TenBelow and go to <strong>Seller Dashboard → Orders</strong> to fulfill this sale.</p>
      `
    ),
    emailCard(
      "Need help with this order?",
      `
        <p style="margin:0 0 8px 0;">For buyer questions, message through the order in TenBelow. For seller support, contact <a href="mailto:${escapeHtml(config.sellerSupportEmail || config.supportEmail)}" style="color:#1f7fd4;text-decoration:none;">${escapeHtml(config.sellerSupportEmail || config.supportEmail)}</a>.</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config: {
      ...config,
      supportEmail: config.sellerSupportEmail || config.supportEmail,
    },
    title: sellerNewOrderEmailSubject(displayNumber),
    previewText: SELLER_NEW_ORDER_PREVIEW,
    heading: "You made a sale! ❄️",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">Good news, ${escapeHtml(greetingName)} &mdash; you have a new TenBelow order.</p>`,
    sectionsHtml,
    extraFooterLinksHtml: sellerAgreementFooterLink(config),
  });
}

function writeSellerEmailState(orders, orderIndex, sellerId, state) {
  const order = orders[orderIndex];
  const previous = order.sellerNewOrderEmails && typeof order.sellerNewOrderEmails === "object"
    ? order.sellerNewOrderEmails
    : {};
  orders[orderIndex] = {
    ...order,
    sellerNewOrderEmails: {
      ...previous,
      [sellerId]: state,
    },
  };
}

export async function deliverSellerNewOrderEmail({
  orderId,
  sellerId,
  shippingAddress,
  loadOrdersFile,
  saveOrdersFile,
  loadSellersFile,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  const normalizedOrderId = String(orderId || "").trim();
  const normalizedSellerId = String(sellerId || "").trim();
  if (!normalizedOrderId || !normalizedSellerId) {
    return { skipped: true, reason: "missing_order_or_seller", sellerId: normalizedSellerId };
  }

  const orders = loadOrdersFile();
  const orderIndex = orders.findIndex((entry) => entry.id === normalizedOrderId);
  if (orderIndex < 0) {
    return { skipped: true, reason: "order_not_found", sellerId: normalizedSellerId };
  }

  const order = orders[orderIndex];
  const sellerShipments = sellerShipmentsForSeller(order, normalizedSellerId);
  if (!sellerShipments.length) {
    return { skipped: true, reason: "no_seller_shipments", sellerId: normalizedSellerId };
  }

  const previous = normalizeSellerNewOrderEmailFields(order.sellerNewOrderEmails?.[normalizedSellerId]);
  if (previous.status === "sent") {
    return { skipped: true, reason: "already_sent", sellerId: normalizedSellerId };
  }

  const sellers = loadSellersFile();
  const seller = sellers[normalizedSellerId] || {};
  const sellerEmail = String(seller.email || "").trim().toLowerCase();
  if (!sellerEmail) {
    return { skipped: true, reason: "missing_seller_email", sellerId: normalizedSellerId };
  }

  const html = buildSellerNewOrderEmailHtml({
    order,
    sellerId: normalizedSellerId,
    seller,
    shippingAddress,
    config,
  });

  const nextAttemptCount = previous.attemptCount + 1;

  try {
    const result = await sendTransactionalEmail({
      to: sellerEmail,
      subject: sellerNewOrderEmailSubject(customerFacingOrderNumber(order)),
      html,
      idempotencyKey: sellerNewOrderIdempotencyKey(normalizedOrderId, normalizedSellerId),
    });

    writeSellerEmailState(orders, orderIndex, normalizedSellerId, {
      status: "sent",
      sentAt: new Date().toISOString(),
      messageId: result?.messageId || null,
      lastError: null,
      attemptCount: nextAttemptCount,
    });
    saveOrdersFile(orders);
    return { sent: true, sellerId: normalizedSellerId, messageId: result?.messageId || null };
  } catch (error) {
    writeSellerEmailState(orders, orderIndex, normalizedSellerId, {
      ...previous,
      status: "failed",
      lastError: String(error?.message || error || "Seller new-order email failed"),
      attemptCount: nextAttemptCount,
    });
    saveOrdersFile(orders);
    console.error(
      `seller new-order email failed orderId=${normalizedOrderId} sellerId=${normalizedSellerId}:`,
      error?.message || error
    );
    return {
      sent: false,
      sellerId: normalizedSellerId,
      error: String(error?.message || error || "Seller new-order email failed"),
    };
  }
}

export async function deliverSellerNewOrderEmailsForPaidOrder({
  orderId,
  shippingAddress,
  loadOrdersFile,
  saveOrdersFile,
  loadSellersFile,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  const orders = loadOrdersFile();
  const order = orders.find((entry) => entry.id === String(orderId || "").trim());
  if (!order) {
    return { skipped: true, reason: "order_not_found", results: [] };
  }

  const results = [];
  for (const sellerId of uniqueSellerIdsFromOrder(order)) {
    try {
      results.push(
        await deliverSellerNewOrderEmail({
          orderId: order.id,
          sellerId,
          shippingAddress,
          loadOrdersFile,
          saveOrdersFile,
          loadSellersFile,
          sendTransactionalEmail,
          config,
        })
      );
    } catch (error) {
      console.error(`seller new-order email crashed sellerId=${sellerId}:`, error?.message || error);
      results.push({
        sent: false,
        sellerId,
        error: String(error?.message || error || "Seller new-order email failed"),
      });
    }
  }

  return { results };
}
