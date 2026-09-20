import { sellerGreetingName } from "./sellerNewOrderEmail.js";
import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailCard, escapeHtml, renderTransactionalEmail } from "./emailHtml.js";
import {
  normalizeProductReviewEmails,
  persistProductReviewEmails,
  productCardHtml,
  sellerAgreementFooterLink,
  viewProductsButton,
} from "./productEmailShared.js";

export const PRODUCT_SUBMITTED_PREVIEW =
  "We received your product submission and will let you know when the review is complete.";

export function productSubmittedEmailSubject(productName = "") {
  const name = String(productName || "your product").trim() || "your product";
  return `Product submitted ❄️ TenBelow is reviewing ${name}`;
}

export function productSubmittedIdempotencyKey(productId = "", cycleId = "") {
  return `product-submitted:${String(productId || "").trim()}:${String(cycleId || "").trim()}`;
}

export function shouldSendProductSubmittedEmail({ previousApprovalStatus, submittedEmail } = {}) {
  const previous = String(previousApprovalStatus || "").trim().toLowerCase();
  const last = submittedEmail || {};
  if (previous === "submitted" && last.status === "sent") {
    return false;
  }
  return true;
}

export function buildProductSubmittedEmailHtml({
  product = {},
  seller = {},
  config = getTransactionalEmailConfig(),
} = {}) {
  const greetingName = sellerGreetingName(seller);
  const productName = String(product.name || "your product").trim() || "your product";

  const sectionsHtml = [
    emailCard(productName, productCardHtml(product, { statusLabel: "In review" }), { featured: true }),
    emailCard(
      "What happens next",
      `
        <ul style="margin:0;padding-left:20px;">
          <li style="margin:0 0 6px 0;">TenBelow reviews the listing.</li>
          <li style="margin:0 0 6px 0;">You&rsquo;ll be notified when a decision is made.</li>
          <li style="margin:0;">If changes are needed, you&rsquo;ll receive the relevant feedback and can update and resubmit in My Products.</li>
        </ul>
      `
    ),
    emailCard(
      "Follow this submission",
      `
        <p style="margin:0;">${viewProductsButton(config, "View My Products")}</p>
        <p style="margin:10px 0 0 0;font-size:13px;color:#5b7694;">Open TenBelow and go to <strong>Seller Dashboard → My Products</strong>.</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config: {
      ...config,
      supportEmail: config.sellerSupportEmail || config.supportEmail,
    },
    title: productSubmittedEmailSubject(productName),
    previewText: PRODUCT_SUBMITTED_PREVIEW,
    heading: "Product submitted ❄️",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">Thanks, ${escapeHtml(greetingName)}. We&rsquo;ve received ${escapeHtml(productName)} and it&rsquo;s now in review.</p>`,
    sectionsHtml,
    extraFooterLinksHtml: sellerAgreementFooterLink(config),
  });
}

export async function deliverProductSubmittedEmail({
  product,
  previousApprovalStatus,
  loadSellersFile,
  loadCatalog,
  saveCatalog,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  const productId = String(product?.id || "").trim();
  const sellerId = String(product?.sellerId || "").trim();
  const cycleId = String(product?.submittedAt || "").trim();
  if (!productId || !sellerId || !cycleId) {
    return { skipped: true, reason: "missing_product_or_cycle" };
  }

  const reviewEmails = normalizeProductReviewEmails(product);
  if (!shouldSendProductSubmittedEmail({ previousApprovalStatus, submittedEmail: reviewEmails.submitted })) {
    return { skipped: true, reason: "already_sent_this_cycle", productId };
  }
  if (reviewEmails.submitted.status === "sent" && reviewEmails.submitted.cycleId === cycleId) {
    return { skipped: true, reason: "already_sent_this_cycle", productId };
  }

  const sellers = typeof loadSellersFile === "function" ? loadSellersFile() : {};
  const seller = sellers[sellerId] || {};
  const sellerEmail = String(seller.email || "").trim().toLowerCase();
  if (!sellerEmail) {
    return { skipped: true, reason: "missing_seller_email", productId };
  }

  const html = buildProductSubmittedEmailHtml({ product, seller, config });
  const nextAttemptCount = reviewEmails.submitted.attemptCount + 1;

  try {
    const result = await sendTransactionalEmail({
      to: sellerEmail,
      subject: productSubmittedEmailSubject(product.name),
      html,
      idempotencyKey: productSubmittedIdempotencyKey(productId, cycleId),
    });
    const nextEmails = {
      ...reviewEmails,
      submitted: {
        status: "sent",
        sentAt: new Date().toISOString(),
        messageId: result?.messageId || null,
        lastError: null,
        attemptCount: nextAttemptCount,
        cycleId,
        decision: null,
      },
    };
    await persistProductReviewEmails({ productId, reviewEmails: nextEmails, loadCatalog, saveCatalog });
    return { sent: true, productId, cycleId, messageId: result?.messageId || null };
  } catch (error) {
    const nextEmails = {
      ...reviewEmails,
      submitted: {
        ...reviewEmails.submitted,
        status: "failed",
        lastError: String(error?.message || error || "Product submitted email failed"),
        attemptCount: nextAttemptCount,
        cycleId,
      },
    };
    await persistProductReviewEmails({ productId, reviewEmails: nextEmails, loadCatalog, saveCatalog });
    console.error(`product submitted email failed productId=${productId}:`, error?.message || error);
    return { sent: false, productId, error: String(error?.message || error || "Product submitted email failed") };
  }
}
