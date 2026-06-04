#!/usr/bin/env node
/**
 * Prints transactional email env readiness (Resend or SMTP).
 * Usage: node scripts/print-email-checklist.mjs
 */
import "dotenv/config";
import { Resend } from "resend";

const resendKey = String(process.env.RESEND_API_KEY || "").trim();
const emailFrom = String(process.env.EMAIL_FROM || "").trim();
const adminLoginEmail = String(
  process.env.ADMIN_LOGIN_EMAIL || process.env.CUSTOM_ORDER_ADMIN_EMAIL || ""
).trim();
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

let resendKeyLive = null;
let resendKeyError = "";
if (resendOk) {
  const client = new Resend(resendKey);
  const { error } = await client.domains.list();
  if (error) {
    resendKeyLive = false;
    resendKeyError = error.message || "Resend API error";
  } else {
    resendKeyLive = true;
  }
}

const checks = [
  [
    "RESEND_API_KEY",
    resendOk,
    resendKey ? `${resendKey.slice(0, 6)}…` : "(empty)",
  ],
  [
    "RESEND_API_KEY (live)",
    resendKeyLive === true,
    resendKeyLive === false ? `FAILED — ${resendKeyError}` : resendKeyLive ? "valid" : "(not checked)",
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
  [
    "ADMIN_LOGIN_EMAIL",
    Boolean(adminLoginEmail),
    adminLoginEmail || "(empty)",
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

if (resendKeyLive === false) {
  console.log("\nAction: Create a new API key at https://resend.com/api-keys and update Render + local .env.");
}

console.log("\nSend test:");
console.log("  node scripts/test-resend-delivery.mjs");
console.log("\nProduction check:");
console.log("  curl -s https://tenbelow.onrender.com/ready");
console.log("\nSee docs/email-setup.md for Render + Resend steps.\n");

const exitOk = configured && resendKeyLive !== false;
process.exit(exitOk ? 0 : 1);
