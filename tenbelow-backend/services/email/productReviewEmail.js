import { sellerGreetingName } from "./sellerNewOrderEmail.js";
import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailCard, escapeHtml, renderTransactionalEmail } from "./emailHtml.js";
import {
  escapedMultilineHtml,
  normalizeProductReviewEmails,
  persistProductReviewEmails,
  productCardHtml,
  sellerAgreementFooterLink,
  viewProductsButton,
} from "./productEmailShared.js";

export function productApprovedEmailSubject(productName = "") {
  const name = String(productName || "Your product").trim() || "Your product";
  return `Your product is approved 🎉 ${name} is ready on TenBelow`;
}

export function productNeedsChangesEmailSubject(productName = "") {
  const name = String(productName || "your product").trim() || "your product";
  return `Changes needed for ${name}`;
}

export function productDecisionIdempotencyKey(productId = "", decision = "", cycleId = "") {
  const normalizedDecision = String(decision || "").trim().toLowerCase() === "approve" ? "approve" : "reject";
  return `product-review:${String(productId || "").trim()}:${normalizedDecision}:${String(cycleId || "").trim()}`;
}

export function shouldSendProductDecisionEmail({
  previousApprovalStatus,
  decision,
  decisionEmail,
  cycleId,
} = {}) {
  const normalizedDecision = String(decision || "").trim().toLowerCase() === "approve" ? "approve" : "reject";
  const expectedStatus = normalizedDecision === "approve" ? "approved" : "rejected";
  const previous = String(previousApprovalStatus || "").trim().toLowerCase();
  const last = decisionEmail || {};

  if (last.status === "sent" && last.decision === normalizedDecision && last.cycleId === String(cycleId || "")) {
    return false;
  }
  if (last.status === "sent" && last.decision === normalizedDecision && previous === expectedStatus) {
    return false;
  }
  return true;
}

export function buildProductApprovedEmailHtml({
  product = {},
  seller = {},
  config = getTransactionalEmailConfig(),
} = {}) {
  const greetingName = sellerGreetingName(seller);
  const productName = String(product.name || "your product").trim() || "your product";

  const sectionsHtml = [
    emailCard(productName, productCardHtml(product, { statusLabel: "Approved" }), { featured: true }),
    emailCard(
      "It's live on TenBelow",
      `
        <p style="margin:0 0 10px 0;">${escapeHtml(productName)} has been approved and is ready for customers to discover on TenBelow.</p>
        <p style="margin:0 0 12px 0;font-size:13px;color:#5b7694;">Creator Clips and strong product photos can help customers understand what makes your product special.</p>
        <p style="margin:0;">${viewProductsButton(config, "View My Products")}</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config: {
      ...config,
      supportEmail: config.sellerSupportEmail || config.supportEmail,
    },
    title: productApprovedEmailSubject(productName),
    previewText: `${productName} has been approved and is ready on TenBelow.`,
    heading: "You're approved! 🎉",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">Good news, ${escapeHtml(greetingName)} &mdash; ${escapeHtml(productName)} is live.</p>`,
    sectionsHtml,
    extraFooterLinksHtml: sellerAgreementFooterLink(config),
  });
}

export function buildProductNeedsChangesEmailHtml({
  product = {},
  seller = {},
  notes = "",
  config = getTransactionalEmailConfig(),
} = {}) {
  const greetingName = sellerGreetingName(seller);
  const productName = String(product.name || "your product").trim() || "your product";
  const feedback = String(notes || product.reviewNotes || "").trim();

  const sectionsHtml = [
    emailCard(productName, productCardHtml(product, { statusLabel: "Changes needed" }), { featured: true }),
    emailCard(
      "What to update",
      feedback
        ? `<p style="margin:0;">${escapedMultilineHtml(feedback)}</p>`
        : `<p style="margin:0;">Open My Products in TenBelow to review the requested updates.</p>`
    ),
    emailCard(
      "What to do next",
      `
        <p style="margin:0 0 12px 0;">Open My Products, make the requested updates, and resubmit the product for review.</p>
        <p style="margin:0;">${viewProductsButton(config, "View My Products")}</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config: {
      ...config,
      supportEmail: config.sellerSupportEmail || config.supportEmail,
    },
    title: productNeedsChangesEmailSubject(productName),
    previewText: `We reviewed ${productName} and need a few updates before it can be approved.`,
    heading: "A few changes are needed",
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">We reviewed ${escapeHtml(productName)} and need a few updates before it can be approved.</p>`,
    sectionsHtml,
    extraFooterLinksHtml: sellerAgreementFooterLink(config),
  });
}

export async function deliverProductDecisionEmail({
  product,
  previousApprovalStatus,
  decision,
  notes,
  loadSellersFile,
  loadCatalog,
  saveCatalog,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  const productId = String(product?.id || "").trim();
  const sellerId = String(product?.sellerId || "").trim();
  const cycleId = String(product?.reviewedAt || "").trim();
  const normalizedDecision = String(decision || "").trim().toLowerCase() === "approve" ? "approve" : "reject";
  if (!productId || !sellerId || !cycleId) {
    return { skipped: true, reason: "missing_product_or_cycle" };
  }

  const reviewEmails = normalizeProductReviewEmails(product);
  if (
    !shouldSendProductDecisionEmail({
      previousApprovalStatus,
      decision: normalizedDecision,
      decisionEmail: reviewEmails.decision,
      cycleId,
    })
  ) {
    return { skipped: true, reason: "already_sent_this_cycle", productId };
  }

  const sellers = typeof loadSellersFile === "function" ? loadSellersFile() : {};
  const seller = sellers[sellerId] || {};
  const sellerEmail = String(seller.email || "").trim().toLowerCase();
  if (!sellerEmail) {
    return { skipped: true, reason: "missing_seller_email", productId };
  }

  const html =
    normalizedDecision === "approve"
      ? buildProductApprovedEmailHtml({ product, seller, config })
      : buildProductNeedsChangesEmailHtml({ product, seller, notes, config });
  const subject =
    normalizedDecision === "approve"
      ? productApprovedEmailSubject(product.name)
      : productNeedsChangesEmailSubject(product.name);
  const nextAttemptCount = reviewEmails.decision.attemptCount + 1;

  try {
    const result = await sendTransactionalEmail({
      to: sellerEmail,
      subject,
      html,
      idempotencyKey: productDecisionIdempotencyKey(productId, normalizedDecision, cycleId),
    });
    const nextEmails = {
      ...reviewEmails,
      decision: {
        status: "sent",
        sentAt: new Date().toISOString(),
        messageId: result?.messageId || null,
        lastError: null,
        attemptCount: nextAttemptCount,
        cycleId,
        decision: normalizedDecision,
      },
    };
    await persistProductReviewEmails({ productId, reviewEmails: nextEmails, loadCatalog, saveCatalog });
    return { sent: true, productId, cycleId, decision: normalizedDecision, messageId: result?.messageId || null };
  } catch (error) {
    const nextEmails = {
      ...reviewEmails,
      decision: {
        ...reviewEmails.decision,
        status: "failed",
        lastError: String(error?.message || error || "Product review email failed"),
        attemptCount: nextAttemptCount,
        cycleId,
        decision: normalizedDecision,
      },
    };
    await persistProductReviewEmails({ productId, reviewEmails: nextEmails, loadCatalog, saveCatalog });
    console.error(`product review email failed productId=${productId}:`, error?.message || error);
    return { sent: false, productId, error: String(error?.message || error || "Product review email failed") };
  }
}
