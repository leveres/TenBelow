#!/usr/bin/env node
import "dotenv/config";
import { buildSellerWelcomeEmailHtml } from "../services/sellerWelcomeEmail.js";
import { getActiveSellerAgreementDocument } from "../legal/sellerAgreementDocuments.js";

const document = getActiveSellerAgreementDocument();
const seller = {
  sellerId: "preview-seller",
  email: "seller@example.com",
  legalName: "Jordan Example",
  sellerAgreement: {
    accepted: true,
    acceptedAt: new Date().toISOString(),
    version: document.versionSlug,
    versionLabel: document.versionLabel,
    documentId: document.id,
    documentHash: document.documentHash,
  },
};

const html = buildSellerWelcomeEmailHtml({
  seller,
  agreementAcceptance: {
    documentId: document.id,
    version: document.versionSlug,
    versionLabel: document.versionLabel,
    acceptedAt: seller.sellerAgreement.acceptedAt,
    sellerLegalName: seller.legalName,
  },
  agreementDocument: document,
});

console.log("Seller welcome email HTML preview generated.");
console.log(`Agreement document: ${document.id}`);
console.log(`PDF attachment available: ${document.pdfAvailable ? "yes" : "no (add PDF to legal/documents folder)"}`);
console.log(`HTML length: ${html.length} characters`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const out = path.join(process.cwd(), "tmp-seller-welcome-email-preview.html");
  fs.writeFileSync(out, html, "utf8");
  console.log(`Wrote ${out}`);
}
