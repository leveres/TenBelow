#!/usr/bin/env node
/**
 * Prints Stripe env readiness without calling Stripe APIs.
 * Usage: node scripts/print-stripe-checklist.mjs
 */
import "dotenv/config";

const secret = String(process.env.STRIPE_SECRET_KEY || "").trim();
const webhook = String(process.env.STRIPE_WEBHOOK_SECRET || "").trim();
const backend = String(process.env.BACKEND_URL || "").trim();
const appKey = String(process.env.APP_API_KEY || "").trim();

function ok(value, invalidHints = []) {
  if (!value) return false;
  return !invalidHints.some((h) => value.includes(h));
}

const checks = [
  ["STRIPE_SECRET_KEY", ok(secret, ["REPLACE", "YOUR_", "missing"]), secret ? `${secret.slice(0, 12)}…` : "(empty)"],
  ["STRIPE_WEBHOOK_SECRET", ok(webhook, ["REPLACE", "YOUR_"]), webhook ? `${webhook.slice(0, 10)}…` : "(empty)"],
  ["BACKEND_URL", ok(backend), backend || "(empty)"],
  ["APP_API_KEY", ok(appKey), appKey ? "set" : "(empty)"],
];

console.log("\nTenBelow Stripe environment checklist\n");
for (const [name, pass, detail] of checks) {
  console.log(`${pass ? "✓" : "○"} ${name}: ${detail}`);
}
console.log("\nWebhook endpoint to register in Stripe Dashboard:");
console.log(`  ${backend ? backend.replace(/\/$/, "") : "https://<BACKEND_URL>"}/webhook`);
console.log("\nSee docs/stripe-setup.md for full setup.\n");

process.exit(checks.every(([, pass]) => pass) ? 0 : 1);
