#!/usr/bin/env node
import "dotenv/config";
import {
  BUYER_WELCOME_EMAIL_PREVIEW,
  BUYER_WELCOME_EMAIL_SUBJECT,
  buildBuyerWelcomeEmailHtml,
} from "../services/email/buyerWelcomeEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const buyer = {
  email: "buyer@example.com",
  fullName: "Jordan Example",
  emailVerified: true,
};

const config = getTransactionalEmailConfig();
const html = buildBuyerWelcomeEmailHtml({ buyer, config });

console.log("Buyer welcome email HTML preview generated.");
console.log(`Subject: ${BUYER_WELCOME_EMAIL_SUBJECT}`);
console.log(`Preview: ${BUYER_WELCOME_EMAIL_PREVIEW}`);
console.log(`Logo: ${config.logoUrl || "(text brand fallback — set TENBELOW_EMAIL_LOGO_URL)"}`);
console.log(`Shop CTA: ${config.shopUrl}`);
console.log(`HTML length: ${html.length} characters`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const out = path.join(process.cwd(), "tmp-buyer-welcome-email-preview.html");
  fs.writeFileSync(out, html, "utf8");
  console.log(`Wrote ${out}`);
}
