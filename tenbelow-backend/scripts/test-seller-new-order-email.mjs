#!/usr/bin/env node
import "dotenv/config";
import {
  SELLER_NEW_ORDER_PREVIEW,
  buildSellerNewOrderEmailHtml,
  sellerNewOrderEmailSubject,
} from "../services/email/sellerNewOrderEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderNumber = "TB-8F42C7";
const config = getTransactionalEmailConfig({
  logoUrl: "",
  websiteUrl: "https://tenbelow.com",
  sellerDashboardUrl: "https://tenbelow.com",
  sellerOrdersUrl: "https://tenbelow.com",
  sellerSupportEmail: "support@tenbelow.com",
  backendBaseUrl: "https://tenbelow.onrender.com",
});

const order = {
  id: "11111111-2222-4333-8444-555555555555",
  orderNumber,
  createdAt: "2026-09-18T04:00:00.000Z",
  currency: "USD",
  shipments: [
    {
      sellerId: "seller-a",
      sellerName: "Jordan Makes",
      shipByDate: "2026-09-22T04:00:00.000Z",
      items: [
        {
          productName: "Modular Phone Stand",
          quantity: 1,
          unitPriceCents: 899,
          selectedColorName: "Frost Blue",
        },
        {
          productName: "Cable Clip Set",
          quantity: 2,
          unitPriceCents: 499,
          selectedColorName: "White",
        },
      ],
    },
    {
      sellerId: "seller-b",
      sellerName: "Print Lab Co.",
      shipByDate: "2026-09-24T04:00:00.000Z",
      items: [
        {
          productName: "Desk Organizer",
          quantity: 1,
          unitPriceCents: 1299,
        },
      ],
    },
  ],
};

const html = buildSellerNewOrderEmailHtml({
  order,
  sellerId: "seller-a",
  seller: { businessName: "Jordan Makes", legalName: "Jordan Maker", email: "jordan@example.com" },
  shippingAddress: {
    name: "Alex Buyer",
    line1: "123 Maker Lane",
    line2: "Apt 4B",
    city: "Columbus",
    state: "OH",
    postalCode: "43215",
    country: "US",
  },
  config,
});

console.log("Seller new-order HTML preview generated.");
console.log(`Subject: ${sellerNewOrderEmailSubject(orderNumber)}`);
console.log(`Preview: ${SELLER_NEW_ORDER_PREVIEW}`);
console.log(`HTML length: ${html.length} characters`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const out = path.join(process.cwd(), "tmp-seller-new-order-email-preview.html");
  fs.writeFileSync(out, html, "utf8");
  console.log(`Wrote ${out}`);
}
