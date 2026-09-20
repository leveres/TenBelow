import { getTransactionalEmailConfig } from "./emailConfig.js";
import { emailButton, emailCard, renderTransactionalEmail } from "./emailHtml.js";

export const BUYER_WELCOME_EMAIL_SUBJECT = "Welcome to TenBelow ❄️ Your account is ready";
export const BUYER_WELCOME_EMAIL_PREVIEW =
  "Discover original 3D-printed finds from independent creators.";

export function normalizeBuyerWelcomeEmailFields(record = {}) {
  const welcome = record.welcomeEmail || {};
  return {
    status: welcome.status || (welcome.sentAt ? "sent" : "pending"),
    sentAt: welcome.sentAt || null,
    messageId: welcome.messageId || null,
    lastError: welcome.lastError || null,
    attemptCount: Math.max(0, Number(welcome.attemptCount) || 0),
  };
}

export function buyerFirstName(fullName = "") {
  const trimmed = String(fullName || "").trim();
  if (!trimmed) return "";
  return trimmed.split(/\s+/)[0];
}

export function buildBuyerWelcomeEmailHtml({ buyer, config = getTransactionalEmailConfig() } = {}) {
  const firstName = buyerFirstName(buyer?.fullName);
  const shopUrl = config.shopUrl || config.websiteUrl;
  const heading = firstName
    ? `Welcome to TenBelow, ${firstName} ❄️`
    : "Welcome to TenBelow ❄️";

  const sectionsHtml = [
    emailCard(
      "Find something different.",
      `
        <p style="margin:0 0 10px 0;">Discover creative, useful, and affordable 3D-printed finds made by independent creators.</p>
        <p style="margin:0 0 14px 0;">Explore creator storefronts, watch Creator Clips, and catch featured finds and Weekly Drops.</p>
        ${emailButton("Start Shopping", shopUrl, { primary: true })}
      `,
      { featured: true }
    ),
    emailCard(
      "Shopping on TenBelow",
      `
        <p style="margin:0;">Products are made and fulfilled by independent creators, so processing and shipping times may vary. Check each listing for available timing details, then manage orders and view status or tracking in TenBelow after purchase.</p>
      `
    ),
  ].join("");

  return renderTransactionalEmail({
    config,
    title: BUYER_WELCOME_EMAIL_SUBJECT,
    previewText: BUYER_WELCOME_EMAIL_PREVIEW,
    heading,
    greetingHtml: `<p style="margin:9px 0 0 0;font-size:16px;line-height:1.5;color:#23486b;">Your account is verified and you&rsquo;re officially in.</p>`,
    sectionsHtml,
  });
}

export async function sendBuyerWelcomeEmail({
  buyer,
  email,
  sendTransactionalEmail,
  config = getTransactionalEmailConfig(),
}) {
  if (typeof sendTransactionalEmail !== "function") {
    throw new Error("sendTransactionalEmail is required");
  }

  const recipient = String(email || buyer?.email || "")
    .trim()
    .toLowerCase();
  if (!recipient) {
    throw new Error("Buyer email is required");
  }

  const html = buildBuyerWelcomeEmailHtml({ buyer: { ...buyer, email: recipient }, config });
  const result = await sendTransactionalEmail({
    to: recipient,
    subject: BUYER_WELCOME_EMAIL_SUBJECT,
    html,
    idempotencyKey: `buyer-welcome:${recipient}`,
  });

  return {
    messageId: result?.messageId || null,
    recipients: result?.recipients || [recipient],
    bypassed: result?.bypassed === true,
  };
}

/**
 * Durable delivery with duplicate protection persisted on the buyer record.
 * Safe to call after verification; never throws to callers that catch queue errors.
 */
export async function deliverBuyerWelcomeEmailIfNeeded({
  email,
  loadBuyersFile,
  saveBuyersFile,
  sendTransactionalEmail,
  isEmailBypassed = () => false,
}) {
  const normalizedEmail = String(email || "")
    .trim()
    .toLowerCase();
  if (!normalizedEmail) {
    return { skipped: true, reason: "missing_email" };
  }

  if (typeof isEmailBypassed === "function" && isEmailBypassed()) {
    return { skipped: true, reason: "bypass_email" };
  }

  const buyers = loadBuyersFile();
  const buyer = buyers[normalizedEmail];
  if (!buyer) {
    return { skipped: true, reason: "buyer_not_found" };
  }
  if (buyer.emailVerified !== true) {
    return { skipped: true, reason: "not_verified" };
  }

  const welcome = normalizeBuyerWelcomeEmailFields(buyer);
  if (welcome.status === "sent") {
    return { skipped: true, reason: "already_sent" };
  }

  buyer.welcomeEmail = {
    ...welcome,
    status: "pending",
    attemptCount: welcome.attemptCount + 1,
  };
  buyers[normalizedEmail] = buyer;
  saveBuyersFile(buyers);

  try {
    const result = await sendBuyerWelcomeEmail({
      buyer,
      email: normalizedEmail,
      sendTransactionalEmail,
    });

    if (result.bypassed) {
      return { skipped: true, reason: "bypass_email" };
    }

    const refreshed = loadBuyersFile();
    const updated = refreshed[normalizedEmail];
    if (updated) {
      updated.welcomeEmail = {
        status: "sent",
        sentAt: new Date().toISOString(),
        messageId: result.messageId || null,
        lastError: null,
        attemptCount: updated.welcomeEmail?.attemptCount || buyer.welcomeEmail.attemptCount,
      };
      refreshed[normalizedEmail] = updated;
      saveBuyersFile(refreshed);
    }

    return { sent: true, messageId: result.messageId || null };
  } catch (error) {
    const refreshed = loadBuyersFile();
    const updated = refreshed[normalizedEmail];
    if (updated) {
      updated.welcomeEmail = {
        status: "failed",
        sentAt: updated.welcomeEmail?.sentAt || null,
        messageId: updated.welcomeEmail?.messageId || null,
        lastError: String(error?.message || error || "Buyer welcome email failed"),
        attemptCount: updated.welcomeEmail?.attemptCount || buyer.welcomeEmail.attemptCount,
      };
      refreshed[normalizedEmail] = updated;
      saveBuyersFile(refreshed);
    }

    console.error(`buyer welcome email failed email=${normalizedEmail}:`, error?.message || error);
    return { sent: false, error: String(error?.message || error || "Buyer welcome email failed") };
  }
}

export function queueBuyerWelcomeEmail(deliveryArgs) {
  setImmediate(() => {
    deliverBuyerWelcomeEmailIfNeeded(deliveryArgs).catch((error) => {
      console.error("buyer welcome email queue error:", error?.message || error);
    });
  });
}

/**
 * Called only after successful OTP verification.
 * Never blocks verification; skips entirely when BYPASS_EMAIL is active.
 */
export function scheduleBuyerWelcomeAfterVerification({
  email,
  bypassEnabled = false,
  deliveryArgs = {},
}) {
  if (bypassEnabled) {
    return { queued: false, reason: "bypass_email" };
  }

  queueBuyerWelcomeEmail({
    ...deliveryArgs,
    email,
    isEmailBypassed: () => bypassEnabled,
  });

  return { queued: true };
}
