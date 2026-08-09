import { readFileSync } from "fs";
import {
  buildAgreementPublicURL,
  getSellerAgreementDocument,
} from "../legal/sellerAgreementDocuments.js";

const DEFAULT_SUPPORT_EMAIL = "support@tenbelow.com";
const DEFAULT_WEBSITE_URL = "https://tenbelow.com";

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function sellerFirstName(legalName = "") {
  const trimmed = String(legalName || "").trim();
  if (!trimmed) return "Creator";
  return trimmed.split(/\s+/)[0];
}

function formatAgreementDate(isoString) {
  const parsed = new Date(isoString || Date.now());
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toLocaleString("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/New_York",
  });
}

function emailConfig() {
  const backendBaseUrl = String(process.env.BACKEND_URL || "http://localhost:3000").replace(/\/$/, "");
  return {
    supportEmail: process.env.SELLER_SUPPORT_EMAIL || process.env.SUPPORT_EMAIL || DEFAULT_SUPPORT_EMAIL,
    websiteUrl: process.env.TENBELOW_WEBSITE_URL || DEFAULT_WEBSITE_URL,
    logoUrl:
      process.env.TENBELOW_EMAIL_LOGO_URL ||
      `${backendBaseUrl}/public/email/tenbelow-logo.png`,
    sellerDashboardUrl:
      process.env.TENBELOW_SELLER_DASHBOARD_URL ||
      process.env.TENBELOW_WEBSITE_URL ||
      DEFAULT_WEBSITE_URL,
    sellerResourcesUrl: process.env.TENBELOW_SELLER_RESOURCES_URL || "",
    termsUrl: process.env.TENBELOW_TERMS_URL || `${backendBaseUrl}/terms.html`,
    privacyUrl: process.env.TENBELOW_PRIVACY_URL || `${backendBaseUrl}/privacy.html`,
    backendBaseUrl,
  };
}

function card(title, bodyHtml) {
  return `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 18px 0;border-collapse:separate;border-spacing:0;background:#ffffff;border:1px solid #d9ecff;border-radius:18px;overflow:hidden;">
      <tr>
        <td style="padding:18px 20px 8px 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
          <h2 style="margin:0 0 10px 0;font-size:18px;line-height:1.35;color:#0b4f8a;">${escapeHtml(title)}</h2>
          <div style="font-size:15px;line-height:1.65;color:#23486b;">${bodyHtml}</div>
        </td>
      </tr>
    </table>
  `;
}

function button(label, href, primary = true) {
  const bg = primary ? "#1f7fd4" : "#eef6ff";
  const color = primary ? "#ffffff" : "#0b4f8a";
  const border = primary ? "#1f7fd4" : "#b8d9fb";
  return `
    <a href="${escapeHtml(href)}" style="display:inline-block;margin:8px 8px 0 0;padding:13px 18px;background:${bg};color:${color};text-decoration:none;border-radius:999px;font-size:15px;font-weight:700;border:1px solid ${border};">
      ${escapeHtml(label)}
    </a>
  `;
}

export function buildSellerWelcomeEmailHtml({
  seller,
  agreementAcceptance,
  agreementDocument,
  config = emailConfig(),
}) {
  const firstName = sellerFirstName(seller.legalName || agreementAcceptance?.sellerLegalName);
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
    ? "A PDF copy of the exact agreement you accepted is attached to this email for your records."
    : agreementUrl
      ? `You can view or download your accepted agreement any time here: <a href="${escapeHtml(agreementUrl)}" style="color:#1f7fd4;">View Your Agreement</a>.`
      : "Your accepted agreement version is recorded in your seller account.";

  const resourcesButton = config.sellerResourcesUrl
    ? button("View Seller Resources", config.sellerResourcesUrl, false)
    : "";

  const sections = [
    card(
      "Welcome to TenBelow",
      `
        <p style="margin:0 0 12px 0;">Welcome to TenBelow, <strong>${escapeHtml(firstName)}</strong>!</p>
        <p style="margin:0 0 12px 0;">TenBelow is a marketplace dedicated to affordable, useful, creative, practical, and innovative 3D-printed products.</p>
        <p style="margin:0;">Creators are an important part of the marketplace. TenBelow is designed to help customers discover both great products and the people and businesses creating them.</p>
      `
    ),
    card(
      "Your Seller Account",
      `
        <p style="margin:0 0 12px 0;">Your seller account has been created. Your seller tools help you:</p>
        <ul style="margin:0;padding-left:20px;">
          <li>Create and customize your storefront</li>
          <li>Upload products and manage listings</li>
          <li>Add product photos and Creator Clips</li>
          <li>Manage orders and fulfillment</li>
          <li>Manage shipping information</li>
          <li>Configure payouts</li>
          <li>Participate in eligible marketplace promotional opportunities</li>
        </ul>
      `
    ),
    card(
      "Your Seller Agreement",
      `
        <p style="margin:0 0 12px 0;">You accepted the TenBelow Seller Agreement during registration.</p>
        <p style="margin:0 0 6px 0;"><strong>Agreement version:</strong> ${escapeHtml(agreementVersion)}</p>
        <p style="margin:0 0 12px 0;"><strong>Accepted:</strong> ${escapeHtml(acceptedAt)}</p>
        <p style="margin:0;">${agreementCopyLine}</p>
      `
    ),
    card(
      "Get Your Store Ready",
      `
        <p style="margin:0 0 10px 0;"><strong>1. Complete your store</strong></p>
        <p style="margin:0 0 12px 0;">Add your store name, creator logo, banner, bio, specialties/categories, and shipping/fulfillment information.</p>
        <p style="margin:0 0 10px 0;"><strong>2. Add your products</strong></p>
        <p style="margin:0 0 12px 0;">Include clear photos, titles, accurate descriptions, pricing, options/variants, materials, dimensions where appropriate, processing/fulfillment details, and shipping information.</p>
        <p style="margin:0 0 10px 0;"><strong>3. Show your work</strong></p>
        <p style="margin:0 0 12px 0;">Use Creator Clips, demonstrations, printing timelapses, product-in-use videos, assembly demos, and behind-the-scenes content.</p>
        <p style="margin:0 0 10px 0;"><strong>4. Complete payout setup</strong></p>
        <p style="margin:0;">Finish the required Stripe Connect payout setup in the TenBelow app before receiving payouts. TenBelow will never collect banking information through email.</p>
      `
    ),
    card(
      "Seller Responsibilities",
      `
        <p style="margin:0 0 8px 0;"><strong>Create responsibly</strong> — only sell products you have the legal right to produce and sell.</p>
        <p style="margin:0 0 8px 0;"><strong>Represent products accurately</strong> — listings should match what customers receive.</p>
        <p style="margin:0 0 8px 0;"><strong>Fulfill reliably</strong> — ship within the processing times shown to customers.</p>
        <p style="margin:0 0 8px 0;"><strong>Communicate</strong> — respond appropriately to order issues and required support communications.</p>
        <p style="margin:0;"><strong>Quality</strong> — take reasonable care with printing, finishing, packaging, and fulfillment.</p>
      `
    ),
    card(
      "Content & Social Media",
      `
        <p style="margin:0 0 12px 0;">TenBelow is built around product and creator discovery. Share demonstrations, printing videos, timelapses, workspace clips, new designs, packaging videos, and storefront content when it helps customers understand your work.</p>
        <p style="margin:0;">You may have opportunities to be featured through TenBelow marketing and discovery features, subject to permissions and platform policies. The Seller Agreement remains controlling for intellectual property and marketing rights.</p>
      `
    ),
    card(
      "Build Your Brand",
      `
        <p style="margin:0 0 12px 0;font-size:17px;font-weight:700;color:#0b4f8a;">Products bring customers in. Creators give them a reason to come back.</p>
        <p style="margin:0;">Build a recognizable storefront and tell the story behind your products so customers remember you.</p>
      `
    ),
    card(
      "Getting Paid",
      `
        <p style="margin:0 0 12px 0;">Seller payouts are handled through TenBelow’s existing Stripe / Stripe Connect setup. Complete payout setup in the app to receive payouts.</p>
        <p style="margin:0;"><strong>Security notice:</strong> TenBelow will never ask you to send sensitive banking information through email or social media.</p>
      `
    ),
    card(
      "Marketplace Discovery",
      `
        <p style="margin:0 0 12px 0;">TenBelow includes discovery features such as Fresh Favorites, Creator/Maker Spotlight, Deal of the Day, Weekly Drop, search/categories, and Creator Clips.</p>
        <p style="margin:0;">Placement is not guaranteed. Eligibility may depend on marketplace rules, quality, availability, activity, and other criteria.</p>
      `
    ),
    card(
      "Support",
      `
        <p style="margin:0 0 8px 0;"><strong>Seller Support:</strong> <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;">${escapeHtml(config.supportEmail)}</a></p>
        <p style="margin:0 0 8px 0;"><strong>Website:</strong> <a href="${escapeHtml(config.websiteUrl)}" style="color:#1f7fd4;">${escapeHtml(config.websiteUrl)}</a></p>
        <p style="margin:0 0 14px 0;">Open the TenBelow app to access your seller dashboard and start building your store.</p>
        ${button("Open Seller Dashboard", config.sellerDashboardUrl, true)}
        ${resourcesButton}
      `
    ),
  ].join("");

  return `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Welcome to TenBelow</title>
  </head>
  <body style="margin:0;padding:0;background:#edf6ff;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
      Your seller account is ready. Here's everything you need to know about selling, creating, and growing with TenBelow.
    </div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:linear-gradient(180deg,#edf6ff 0%,#f8fbff 100%);padding:24px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;border-collapse:collapse;">
            <tr>
              <td align="center" style="padding:8px 0 18px 0;">
                <img src="${escapeHtml(config.logoUrl)}" alt="TenBelow" width="132" style="display:block;border:0;max-width:132px;height:auto;" />
              </td>
            </tr>
            <tr>
              <td style="padding:0 0 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
                ${sections}
              </td>
            </tr>
            <tr>
              <td style="padding:8px 12px 24px 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#5b7694;text-align:center;">
                <p style="margin:0 0 8px 0;"><strong>TenBelow</strong><br />Operated by Innovative CodeWorks LLC</p>
                <p style="margin:0 0 8px 0;">
                  <a href="${escapeHtml(config.termsUrl)}" style="color:#1f7fd4;">Terms</a> ·
                  <a href="${escapeHtml(config.privacyUrl)}" style="color:#1f7fd4;">Privacy Policy</a> ·
                  ${agreementUrl ? `<a href="${escapeHtml(agreementUrl)}" style="color:#1f7fd4;">Seller Agreement</a> ·` : ""}
                  <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;">Support</a>
                </p>
                <p style="margin:0;">This is a transactional email related to your TenBelow seller account.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
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
  const subject = "Welcome to TenBelow — Your Seller Journey Starts Here ❄️";

  const result = await sendTransactionalEmail({
    to: seller.email,
    subject,
    html,
    attachments,
    idempotencyKey: `seller-welcome:${sellerId}:${agreementDocument.id}`,
  });

  return {
    messageId: result?.messageId || null,
    agreementDocument,
  };
}
