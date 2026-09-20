/**
 * Shared email-safe HTML building blocks for TenBelow transactional emails.
 * Table-based layout, inline styles only — no JS, animations, or heavy decoration.
 */

export function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function emailCard(title, bodyHtml, { featured = false } = {}) {
  const background = featured ? "#ffffff" : "#f8fbff";
  const border = featured ? "#b8d9fb" : "#d5e8fb";
  const topAccent = featured ? "border-top:3px solid #1f7fd4;" : "";
  return `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 12px 0;border-collapse:separate;border-spacing:0;background:${background};border:1px solid ${border};${topAccent}border-radius:16px;overflow:hidden;">
      <tr>
        <td style="padding:${featured ? "20px" : "16px 18px"};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
          <h2 style="margin:0 0 8px 0;font-size:${featured ? "20px" : "16px"};line-height:1.35;color:#0b4f8a;font-weight:700;">${escapeHtml(title)}</h2>
          <div style="font-size:15px;line-height:1.55;color:#23486b;">${bodyHtml}</div>
        </td>
      </tr>
    </table>
  `;
}

export function emailButton(label, href, { primary = true } = {}) {
  const bg = primary ? "#1f7fd4" : "#eef6ff";
  const color = primary ? "#ffffff" : "#0b4f8a";
  const border = primary ? "#1f7fd4" : "#b8d9fb";
  return `
    <a href="${escapeHtml(href)}" style="display:inline-block;margin:4px 8px 0 0;padding:13px 20px;background:${bg};color:${color};text-decoration:none;border-radius:999px;font-size:15px;font-weight:700;border:1px solid ${border};">
      ${escapeHtml(label)}
    </a>
  `;
}

function brandHeader(config) {
  if (config.logoUrl) {
    return `
      <img src="${escapeHtml(config.logoUrl)}" alt="${escapeHtml(config.brandName || "TenBelow")}" width="132" style="display:block;border:0;max-width:132px;height:auto;" />
    `;
  }

  return `
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:28px;line-height:1.2;font-weight:800;letter-spacing:-0.02em;color:#0b4f8a;">
      ${escapeHtml(config.brandName || "TenBelow")}
    </div>
  `;
}

function emailFooter(config, { extraLinksHtml = "" } = {}) {
  return `
    <p style="margin:0 0 6px 0;"><strong>${escapeHtml(config.brandName || "TenBelow")}</strong><br />Operated by ${escapeHtml(config.companyName || "Innovative CodeWorks LLC")}</p>
    <p style="margin:0 0 6px 0;">
      <a href="${escapeHtml(config.termsUrl)}" style="color:#1f7fd4;text-decoration:none;">Terms</a> ·
      <a href="${escapeHtml(config.privacyUrl)}" style="color:#1f7fd4;text-decoration:none;">Privacy Policy</a> ·
      ${extraLinksHtml}
      <a href="mailto:${escapeHtml(config.supportEmail)}" style="color:#1f7fd4;text-decoration:none;">Support</a>
    </p>
    <p style="margin:0 0 6px 0;">
      <a href="${escapeHtml(config.websiteUrl)}" style="color:#1f7fd4;text-decoration:none;">${escapeHtml(config.websiteUrl.replace(/^https?:\/\//, ""))}</a>
    </p>
    <p style="margin:0;">This is a transactional email related to your TenBelow account.</p>
  `;
}

/**
 * Full document shell shared by all future TenBelow transactional emails.
 */
export function renderTransactionalEmail({
  config,
  title,
  previewText = "",
  heading,
  greetingHtml = "",
  sectionsHtml = "",
  ctaHtml = "",
  extraFooterLinksHtml = "",
}) {
  const preview = String(previewText || "")
    .replace(/\s+/g, " ")
    .trim();

  return `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(title)}</title>
  </head>
  <body style="margin:0;padding:0;background:#edf6ff;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
      ${escapeHtml(preview)}
    </div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#edf6ff;padding:18px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;border-collapse:collapse;">
            <tr>
              <td align="center" style="padding:4px 0 14px 0;">
                ${brandHeader(config)}
              </td>
            </tr>
            <tr>
              <td style="padding:0 4px 10px 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
                <h1 style="margin:0;font-size:26px;line-height:1.25;color:#0b4f8a;font-weight:800;">${escapeHtml(heading)}</h1>
                ${greetingHtml}
              </td>
            </tr>
            <tr>
              <td style="padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
                ${sectionsHtml}
              </td>
            </tr>
            ${
              ctaHtml
                ? `<tr>
              <td align="center" style="padding:4px 0 20px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
                ${ctaHtml}
              </td>
            </tr>`
                : ""
            }
            <tr>
              <td style="padding:5px 12px 14px 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#5b7694;text-align:center;">
                ${emailFooter(config, { extraLinksHtml: extraFooterLinksHtml })}
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}
