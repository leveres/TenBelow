import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailButton, escapeHtml } from "./emailHtml.js";
import { formatMoneyCents, resolveEmailAssetURL } from "./orderConfirmationEmail.js";
import {
  buildAgreementPublicURL,
  getActiveSellerAgreementDocument,
} from "../../legal/sellerAgreementDocuments.js";

export function normalizeProductEmailAttempt(record = {}) {
  const state = record || {};
  return {
    status: state.status || (state.sentAt ? "sent" : "pending"),
    sentAt: state.sentAt || null,
    messageId: state.messageId || null,
    lastError: state.lastError || null,
    attemptCount: Math.max(0, Math.floor(Number(state.attemptCount) || 0)),
    cycleId: state.cycleId ? String(state.cycleId) : null,
    decision: state.decision ? String(state.decision) : null,
  };
}

export function normalizeProductReviewEmails(product = {}) {
  const state = product.reviewEmails || {};
  return {
    submitted: normalizeProductEmailAttempt(state.submitted),
    decision: normalizeProductEmailAttempt(state.decision),
  };
}

export function productReviewStatusLabel(approvalStatus = "") {
  const status = String(approvalStatus || "").trim().toLowerCase();
  if (status === "approved") return "Approved";
  if (status === "rejected") return "Changes needed";
  if (status === "archived") return "Archived";
  return "In review";
}

export function formatProductCategory(category = "") {
  const raw = String(category || "").trim();
  if (!raw) return "";
  return raw.charAt(0).toUpperCase() + raw.slice(1);
}

export function sellerProductsDestination(config = getTransactionalEmailConfig()) {
  return config.sellerProductsUrl || config.sellerDashboardUrl || config.websiteUrl;
}

export function sellerAgreementFooterLink(config = getTransactionalEmailConfig()) {
  try {
    const document = getActiveSellerAgreementDocument();
    const url = buildAgreementPublicURL(document?.id, config.backendBaseUrl);
    if (!url) return "";
    return `<a href="${escapeHtml(url)}" style="color:#1f7fd4;text-decoration:none;">Seller Agreement</a> · `;
  } catch {
    return "";
  }
}

export function productCardHtml(product = {}, { statusLabel = "" } = {}) {
  const name = String(product.name || "Your listing").trim() || "Your listing";
  const imageUrl = resolveEmailAssetURL(
    Array.isArray(product.imageURLs) ? product.imageURLs[0] : product.imageURL
  );
  const imageCell = imageUrl
    ? `<td width="72" valign="top" style="padding:0 14px 0 0;">
        <img src="${escapeHtml(imageUrl)}" alt="" width="64" height="64" style="display:block;border-radius:12px;border:1px solid #d5e8fb;object-fit:cover;" />
      </td>`
    : "";
  const category = formatProductCategory(product.category);
  const price = formatMoneyCents(product.priceCents || 0, product.currency || "USD");
  const status = statusLabel || productReviewStatusLabel(product.approvalStatus);

  return `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
      <tr>
        ${imageCell}
        <td valign="top" style="font-size:15px;line-height:1.5;color:#23486b;">
          <p style="margin:0 0 4px 0;font-weight:700;color:#0b4f8a;">${escapeHtml(name)}</p>
          <p style="margin:0 0 4px 0;">${escapeHtml(price)}${category ? ` · ${escapeHtml(category)}` : ""}</p>
          <p style="margin:0;">Status: ${escapeHtml(status)}</p>
        </td>
      </tr>
    </table>
  `;
}

export function escapedMultilineHtml(text = "") {
  return escapeHtml(text).replace(/\r\n|\r|\n/g, "<br />");
}

export function viewProductsButton(config, label = "View My Products") {
  return emailButton(label, sellerProductsDestination(config), { primary: true });
}

export async function persistProductReviewEmails({
  productId,
  reviewEmails,
  loadCatalog,
  saveCatalog,
}) {
  if (typeof loadCatalog !== "function" || typeof saveCatalog !== "function") {
    return null;
  }
  const catalog = await loadCatalog();
  const products = Array.isArray(catalog?.products) ? [...catalog.products] : [];
  const index = products.findIndex((entry) => String(entry?.id || "").trim() === String(productId || "").trim());
  if (index < 0) return null;
  products[index] = {
    ...products[index],
    reviewEmails: normalizeProductReviewEmails({ reviewEmails }),
  };
  await saveCatalog({ ...catalog, products });
  return products[index];
}
