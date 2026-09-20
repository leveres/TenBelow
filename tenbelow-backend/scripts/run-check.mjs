#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const syntaxChecks = [
  "server.js",
  "admin/admin-review.js",
  "services/email/emailConfig.js",
  "services/email/emailHtml.js",
  "services/email/buyerWelcomeEmail.js",
  "services/sellerWelcomeEmail.js",
  "services/email/orderConfirmationEmail.js",
  "services/email/sellerNewOrderEmail.js",
  "services/email/shipmentUpdateEmail.js",
  "services/email/deliveryConfirmationEmail.js",
  "services/email/productEmailShared.js",
  "services/email/productSubmittedEmail.js",
  "services/email/productReviewEmail.js",
  "domain/phase1/orderNumber.js",
  "domain/phase1/shipmentActions.js",
];

const verifyScripts = [
  "scripts/verify-product-colors.mjs",
  "scripts/verify-buyer-welcome-email.mjs",
  "scripts/verify-seller-welcome-email.mjs",
  "scripts/verify-order-confirmation-email.mjs",
  "scripts/verify-seller-new-order-email.mjs",
  "scripts/verify-shipment-update-email.mjs",
  "scripts/verify-delivery-confirmation-email.mjs",
  "scripts/verify-shipment-action-transitions.mjs",
  "scripts/verify-product-lifecycle-email.mjs",
];

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
    env: process.env,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

for (const file of syntaxChecks) {
  run(process.execPath, ["--check", file]);
}

for (const script of verifyScripts) {
  run(process.execPath, [script]);
}
