import { readFileSync } from "fs";
import {
  buildAgreementPublicURL,
  getSellerAgreementDocument,
} from "../legal/sellerAgreementDocuments.js";
import { getTransactionalEmailConfig } from "./email/emailConfig.js";
import {
  emailButton,
  emailCard,
  escapeHtml,
  renderTransactionalEmail,
} from "./email/emailHtml.js";

export const SELLER_WELCOME_EMAIL_SUBJECT =
  "Welcome to TenBelow — Your Creator Store Starts Here ❄️";
export const SELLER_WELCOME_EMAIL_PREVIEW =
  "Your seller account is ready. Let's get your storefront ready for TenBelow.";

export function sellerFirstName(legalName = "") {
  const trimmed = String(legalName || "").trim();
  if (!trimmed) return "Creator";
  return trimmed.split(/\s+/)[0];
}

export function formatAgreementDate(isoString) {
  const parsed = new Date(isoString || Date.now());
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toLocaleString("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/New_York",
  });
}

export function buildSellerWelcomeEmailHtml({
  seller,
  agreementAcceptance,
  agreementDocument,
  config = getTransactionalEmailConfig(),
}) {
  const firstName = sellerFirstName(seller.legalName || agreementAcceptance?.sellerLegalName);
  const storeName = String(
    seller.businessName ||
    seller.profile?.displayName ||
    ""
  ).trim();
  const agreementVersion =
    agreementAcceptance?.versionLabel ||
    agreementDocument?.versionLabel ||
    agreementAcceptance?.version ||
    "1.0";
  const acceptedAt = formatAgreementDate(
    agreementAcceptance?.acceptedAt || seller?.sellerAgreement?.acceptedAt
  );
  const agreementUrl = buildAgreementPublicURL(
    agreementAcceptance?.documentId || agreementDocument?.id,
    config.backendBaseUrl
  );
  const agreementCopyLine = agreementDocument?.pdfAvailable
    ? `A PDF copy of the exact agreement you accepted is attached for your records.${
        agreementUrl
          ? ` You can also <a href="${escapeHtml(agreementUrl)}" style="color:#1f7fd4;text-decoration:none;">view your agreement online</a>.`
          : ""
      }`
    : agreementUrl
      ? `You can <a href="${escapeHtml(agreementUrl)}" style="color:#1f7fd4;text-decoration:none;">view or download your accepted agreement</a> any time.`
      : "Your accepted agreement version is recorded in your seller account.";

  const resourcesButton = config.sellerResourcesUrl
    ? emailButton("Seller Resources", config.sellerResourcesUrl, { primary: false })
    : "";

  const storeIntroduction = storeName
    ? `<strong>${escapeHtml(storeName)}</strong> is officially part of TenBelow&mdash;a marketplace built to help customers discover creative 3D-printed products and the creators behind them.`
    : "You&rsquo;re officially part of TenBelow&mdash;a marketplace built to help customers discover creative 3D-printed products and the creators behind them.";

  const sections = [
    emailCard(
      "Your TenBelow Store",
      `
        <p style="margin:0 0 12px 0;">Your storefront is where customers discover your products and creator brand.</p>
        <p style="margin:0 0 14px 0;">${emailButton("Open Seller Dashboard", config.sellerDashboardUrl, { primary: true })}${resourcesButton}</p>
        <p style="margin:0 0 6px 0;font-weight:700;color:#0b4f8a;">Finish setting up your store:</p>
        <ul style="margin:0;padding-left:20px;">
          <li style="margin:0 0 4px 0;">Complete your storefront profile</li>
          <li style="margin:0 0 4px 0;">Add your logo and banner</li>
          <li style="margin:0 0 4px 0;">Confirm processing and shipping information</li>
          <li style="margin:0 0 4px 0;">Complete payout setup</li>
          <li style="margin:0;">Start submitting products for review</li>
        </ul>
      `,
      { featured: true }
    ),
    emailCard(
      "Your Seller Agreement",
      `
        <p style="margin:0 0 6px 0;"><strong>Agreement version:</strong> ${escapeHtml(agreementVersion)}</p>
        <p style="margin:0 0 10px 0;"><strong>Accepted:</strong> ${escapeHtml(acceptedAt)}</p>
        <p style="margin:0;">${agreementCopyLine}</p>
      `
    ),
    emailCard(
      "Selling on TenBelow",
      `
        <p style="margin:0;">Sell only products and designs you have the right to sell. Keep listings accurate—including materials, options, and dimensions where applicable—set realistic processing and shipping details, package and fulfill responsibly, and respond appropriately to customer or support issues. Your Seller Agreement and TenBelow policies contain the complete rules.</p>
      `
    ),
    emailCard(
      "Show Off What You Make",
      `
        <p style="margin:0 0 10px 0;">TenBelow may feature creators, products, printing videos, Creator Clips, behind-the-scenes and workspace videos, product demonstrations, packaging videos, and creator stories through TenBelow-owned marketing and social channels.</p>
        <p style="margin:0 0 12px 0;">Watch for creator feature and content submission opportunities from TenBelow.</p>
        <p style="margin:0;padding-top:10px;border-top:1px solid #d5e8fb;"><strong>Need help?</strong> Contact Seller Support at <a href="mailto:${escapeHtml(config.sellerSupportEmail || config.supportEmail)}" style="color:#1f7fd4;text-decoration:none;">${escapeHtml(config.sellerSupportEmail || config.supportEmail)}</a>.</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config: {
      ...config,
      supportEmail: config.sellerSupportEmail || config.supportEmail,
    },
    title: SELLER_WELCOME_EMAIL_SUBJECT,
    previewText: SELLER_WELCOME_EMAIL_PREVIEW,
    heading: `Welcome to TenBelow, ${firstName} ❄️`,
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">Your seller account is ready. ${storeIntroduction}</p>`,
    sectionsHtml: sections,
    extraFooterLinksHtml: agreementUrl
      ? `<a href="${escapeHtml(agreementUrl)}" style="color:#1f7fd4;text-decoration:none;">Seller Agreement</a> · `
      : "",
  });
}

export function buildSellerWelcomeEmailAttachments(agreementDocument) {
  if (!agreementDocument?.pdfAvailable || !agreementDocument.pdfPath) {
    return [];
  }

  const content = readFileSync(agreementDocument.pdfPath);
  return [
    {
      filename: `${agreementDocument.id}.pdf`,
      content: content.toString("base64"),
    },
  ];
}

export async function sendSellerWelcomeEmail({
  seller,
  sellerId,
  sendTransactionalEmail,
  agreementAcceptance,
}) {
  const documentId =
    agreementAcceptance?.documentId ||
    seller?.sellerAgreement?.documentId ||
    seller?.sellerAgreement?.version;
  const agreementDocument = getSellerAgreementDocument(documentId);
  const html = buildSellerWelcomeEmailHtml({
    seller,
    agreementAcceptance: agreementAcceptance || {
      acceptedAt: seller?.sellerAgreement?.acceptedAt,
      documentId: agreementDocument.id,
      version: agreementDocument.versionSlug,
      versionLabel: agreementDocument.versionLabel,
      sellerLegalName: seller?.legalName,
    },
    agreementDocument,
  });

  const attachments = buildSellerWelcomeEmailAttachments(agreementDocument);
  const result = await sendTransactionalEmail({
    to: seller.email,
    subject: SELLER_WELCOME_EMAIL_SUBJECT,
    html,
    attachments,
    idempotencyKey: `seller-welcome:${sellerId}:${agreementDocument.id}`,
  });

  return {
    messageId: result?.messageId || null,
    agreementDocument,
  };
}
