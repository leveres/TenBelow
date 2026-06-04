#!/usr/bin/env node
/**
 * Prints transactional email env readiness (Resend or SMTP).
 * Usage: node scripts/print-email-checklist.mjs
 */
import "dotenv/config";

const resendKey = String(process.env.RESEND_API_KEY || "").trim();
const emailFrom = String(process.env.EMAIL_FROM || "").trim();
const smtpHost = String(process.env.SMTP_HOST || "").trim();
const smtpUser = String(process.env.SMTP_USER || "").trim();
const smtpPass = String(process.env.SMTP_PASS || "").trim();
const smtpPort = Number(process.env.SMTP_PORT);

function ok(value, invalidHints = []) {
  if (!value) return false;
  return !invalidHints.some((h) => value.includes(h));
}

const resendOk = ok(resendKey, ["REPLACE", "YOUR_"]);
const smtpOk = Boolean(smtpHost && smtpUser && smtpPass && Number.isFinite(smtpPort));
const fromOk = ok(emailFrom) || !emailFrom; // default server fallback if empty
const configured = resendOk || smtpOk;

const checks = [
  [
    "RESEND_API_KEY",
    resendOk,
    resendKey ? `${resendKey.slice(0, 6)}…` : "(empty)",
  ],
  [
    "SMTP (HOST/USER/PASS/PORT)",
    smtpOk,
    smtpOk ? `${smtpHost}:${smtpPort}` : "(incomplete)",
  ],
  [
    "EMAIL_FROM",
    fromOk,
    emailFrom || "(empty — server default: TenBelow <noreply@tenbelow.com>)",
  ],
  ["Transactional email", configured, configured ? "configured" : "not configured"],
];

console.log("\nTenBelow transactional email checklist\n");
for (const [name, pass, detail] of checks) {
  console.log(`${pass ? "✓" : "○"} ${name}: ${detail}`);
}

const fromMatch = emailFrom.match(/<([^>]+)>/);
if (fromMatch) {
  const addr = fromMatch[1];
  const domain = addr.split("@")[1] || "";
  if (domain === "resend.dev") {
    console.log(
      "\nNote: onboarding@resend.dev only delivers to your Resend account email until you verify a custom domain."
    );
  }
}

console.log("\nProduction check:");
console.log("  curl -s https://tenbelow.onrender.com/ready");
console.log("\nSee docs/email-setup.md for Render + Resend steps.\n");

process.exit(configured ? 0 : 1);
