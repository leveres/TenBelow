#!/usr/bin/env node
import "dotenv/config";
import { buildProductSubmittedEmailHtml, productSubmittedEmailSubject } from "../services/email/productSubmittedEmail.js";
import {
  buildProductApprovedEmailHtml,
  buildProductNeedsChangesEmailHtml,
  productApprovedEmailSubject,
  productNeedsChangesEmailSubject,
} from "../services/email/productReviewEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const config = getTransactionalEmailConfig({
  logoUrl: "",
  websiteUrl: "https://tenbelow.com",
  sellerDashboardUrl: "https://tenbelow.com",
  sellerProductsUrl: "https://tenbelow.com",
  sellerSupportEmail: "support@tenbelow.com",
  backendBaseUrl: "https://tenbelow.onrender.com",
});

const seller = { businessName: "Jordan Makes", legalName: "Jordan Maker", email: "jordan@example.com" };
const product = {
  id: "prod_phone_stand",
  sellerId: "seller-a",
  name: "Modular Phone Stand",
  priceCents: 899,
  category: "desk",
  approvalStatus: "submitted",
  submittedAt: "2026-09-18T12:00:00.000Z",
};

const submittedHtml = buildProductSubmittedEmailHtml({ product, seller, config });
const approvedHtml = buildProductApprovedEmailHtml({
  product: { ...product, approvalStatus: "approved" },
  seller,
  config,
});
const needsHtml = buildProductNeedsChangesEmailHtml({
  product: { ...product, approvalStatus: "rejected" },
  seller,
  notes: "Please add a clear size photo and confirm the filament type in the description.",
  config,
});

console.log("Product lifecycle HTML previews generated.");
console.log(`Submitted: ${productSubmittedEmailSubject(product.name)}`);
console.log(`Approved: ${productApprovedEmailSubject(product.name)}`);
console.log(`Needs changes: ${productNeedsChangesEmailSubject(product.name)}`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const files = [
    ["tmp-product-submitted-email-preview.html", submittedHtml],
    ["tmp-product-approved-email-preview.html", approvedHtml],
    ["tmp-product-needs-changes-email-preview.html", needsHtml],
  ];
  for (const [name, html] of files) {
    const out = path.join(process.cwd(), name);
    fs.writeFileSync(out, html, "utf8");
    console.log(`Wrote ${out}`);
  }
}
