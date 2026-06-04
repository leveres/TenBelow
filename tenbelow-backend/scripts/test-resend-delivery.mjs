#!/usr/bin/env node
/**
 * Verifies RESEND_API_KEY and attempts a test send to ADMIN_LOGIN_EMAIL.
 * Usage: node scripts/test-resend-delivery.mjs
 */
import "dotenv/config";
import { Resend } from "resend";

const resendKey = String(process.env.RESEND_API_KEY || "").trim();
const emailFrom = String(process.env.EMAIL_FROM || "TenBelow <onboarding@resend.dev>").trim();
const adminEmail = String(
  process.env.ADMIN_LOGIN_EMAIL || process.env.CUSTOM_ORDER_ADMIN_EMAIL || ""
).trim().toLowerCase();

if (!resendKey) {
  console.error("RESEND_API_KEY is missing.");
  process.exit(1);
}

const resend = new Resend(resendKey);

console.log("\nTenBelow Resend delivery test\n");
console.log(`FROM: ${emailFrom}`);
console.log(`TO:   ${adminEmail || "(set ADMIN_LOGIN_EMAIL)"}`);

const { error: domainsError } = await resend.domains.list();
if (domainsError) {
  console.error(`\n✗ Resend API key check failed: ${domainsError.message}`);
  console.error("\nFix: Resend → API Keys → create a new key → update Render RESEND_API_KEY → redeploy.");
  process.exit(1);
}
console.log("\n✓ Resend API key is valid");

const fromMatch = emailFrom.match(/<([^>]+)>/);
const fromDomain = (fromMatch?.[1] || emailFrom).split("@")[1] || "";
if (fromDomain === "resend.dev") {
  console.log(
    "\nNote: onboarding@resend.dev only delivers to your Resend account email."
  );
  console.log("Either verify innovativecodeworks.com in Resend and update EMAIL_FROM,");
  console.log("or set ADMIN_LOGIN_EMAIL to the email on your Resend account.");
}

if (!adminEmail) {
  console.log("\n○ Skipping send test (ADMIN_LOGIN_EMAIL not set in .env)");
  process.exit(0);
}

const { data, error } = await resend.emails.send({
  from: emailFrom,
  to: [adminEmail],
  subject: "TenBelow admin email test",
  html: "<p>If you received this, admin login codes should work after redeploy.</p>",
});

if (error) {
  console.error(`\n✗ Send to ${adminEmail} failed: ${error.message}`);
  process.exit(1);
}

console.log(`\n✓ Test email accepted by Resend (id: ${data?.id || "n/a"})`);
console.log(`  Check inbox for ${adminEmail}\n`);
