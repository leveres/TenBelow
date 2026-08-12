const DEFAULT_SUPPORT_EMAIL = "support@tenbelow.com";

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function emailConfig() {
  const backendBaseUrl = String(process.env.BACKEND_URL || "http://localhost:3000").replace(/\/$/, "");
  return {
    supportEmail: process.env.SUPPORT_EMAIL || DEFAULT_SUPPORT_EMAIL,
    websiteUrl: process.env.TENBELOW_WEBSITE_URL || "https://tenbelow.com",
    logoUrl:
      process.env.TENBELOW_EMAIL_LOGO_URL ||
      `${backendBaseUrl}/public/email/tenbelow-logo.png`,
    termsUrl: process.env.TENBELOW_TERMS_URL || `${backendBaseUrl}/terms.html`,
    privacyUrl: process.env.TENBELOW_PRIVACY_URL || `${backendBaseUrl}/privacy.html`,
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

export function buildAccountModerationEmailHtml({
  accountKind = "seller",
  action = "flag",
  displayName = "",
  reason = "",
} = {}) {
  const config = emailConfig();
  const normalizedAction = String(action || "").trim().toLowerCase();
  const accountLabel = accountKind === "buyer" ? "buyer" : "seller";
  const greetingName = String(displayName || "").trim() || "there";
  const isFreeze = normalizedAction === "freeze";
  const title = isFreeze
    ? "Your TenBelow account has been frozen"
    : "Your TenBelow account has been flagged for review";
  const intro = isFreeze
    ? `Your TenBelow ${accountLabel} account has been temporarily frozen while we review a policy concern.`
    : `Your TenBelow ${accountLabel} account has been flagged for review after a policy concern was reported.`;
  const nextSteps = isFreeze
    ? "While your account is frozen, sign-in and marketplace activity are paused until the review is complete."
    : "Your account may remain available while we review this concern, but please address the issue below promptly.";

  return `
    <!DOCTYPE html>
    <html lang="en">
      <body style="margin:0;padding:24px;background:#eef6ff;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;margin:0 auto;">
          <tr>
            <td style="padding:8px 0 18px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <img src="${escapeHtml(config.logoUrl)}" alt="TenBelow" width="132" style="display:block;border:0;" />
            </td>
          </tr>
          <tr>
            <td style="padding:0 0 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <h1 style="margin:0;font-size:28px;line-height:1.25;color:#0b4f8a;">${escapeHtml(title)}</h1>
              <p style="margin:12px 0 0 0;font-size:16px;line-height:1.6;color:#23486b;">Hi ${escapeHtml(greetingName)},</p>
            </td>
          </tr>
          <tr>
            <td>
              ${card("What happened", `<p style="margin:0 0 12px 0;">${escapeHtml(intro)}</p><p style="margin:0;">${escapeHtml(nextSteps)}</p>`)}
              ${card(
                "Reason provided by TenBelow",
                `<p style="margin:0;white-space:pre-wrap;">${escapeHtml(reason)}</p>`
              )}
              ${card(
                "Need help?",
                `<p style="margin:0 0 8px 0;">Reply to this email or contact <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;">${escapeHtml(config.supportEmail)}</a> if you believe this action was made in error.</p>
                 <p style="margin:0;">Review our policies at <a href="${escapeHtml(config.termsUrl)}" style="color:#1f7fd4;">Terms</a> and <a href="${escapeHtml(config.privacyUrl)}" style="color:#1f7fd4;">Privacy</a>.</p>`
              )}
            </td>
          </tr>
        </table>
      </body>
    </html>
  `;
}

export function accountModerationEmailSubject({ accountKind = "seller", action = "flag" } = {}) {
  const accountLabel = accountKind === "buyer" ? "buyer" : "seller";
  if (String(action || "").trim().toLowerCase() === "freeze") {
    return `TenBelow ${accountLabel} account frozen — action required`;
  }
  return `TenBelow ${accountLabel} account flagged — action required`;
}

export async function sendAccountModerationEmail({
  sendTransactionalEmail,
  to,
  accountKind = "seller",
  action = "flag",
  displayName = "",
  reason = "",
  accountId = "",
} = {}) {
  if (typeof sendTransactionalEmail !== "function") {
    throw new Error("sendTransactionalEmail is required");
  }
  const recipient = String(to || "").trim().toLowerCase();
  if (!recipient) {
    throw new Error("Account email is required");
  }

  const normalizedAction = String(action || "").trim().toLowerCase();
  const trimmedReason = String(reason || "").trim();
  if (!trimmedReason) {
    throw new Error("A reason is required for moderation email");
  }

  const subject = accountModerationEmailSubject({ accountKind, action: normalizedAction });
  const html = buildAccountModerationEmailHtml({
    accountKind,
    action: normalizedAction,
    displayName,
    reason: trimmedReason,
  });
  const idempotencyKey = `account-moderation:${accountKind}:${accountId}:${normalizedAction}:${Date.now()}`;

  return sendTransactionalEmail({
    to: recipient,
    subject,
    html,
    idempotencyKey,
  });
}
