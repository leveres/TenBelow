#!/usr/bin/env node
import "dotenv/config";
import {
  ORDER_CONFIRMATION_PREVIEW,
  buildOrderConfirmationEmailHtml,
  orderConfirmationEmailSubject,
} from "../services/email/orderConfirmationEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderId = "11111111-2222-4333-8444-555555555555";
const orderNumber = "TB-8F42C7";
const config = getTransactionalEmailConfig({
  logoUrl: "",
  websiteUrl: "https://tenbelow.com",
  ordersUrl: "https://tenbelow.com",
  supportEmail: "support@tenbelow.com",
  backendBaseUrl: "https://tenbelow.onrender.com",
});

const order = {
  id: orderId,
  orderNumber,
  createdAt: "2026-09-18T04:00:00.000Z",
  currency: "USD",
  totalCents: 4597,
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

const html = buildOrderConfirmationEmailHtml({
  order,
  buyer: { fullName: "Alex Buyer", email: "alex@example.com" },
  paymentSummary: {
    subtotalCents: 3996,
    shippingCents: 601,
    totalCents: 4597,
    currency: "USD",
  },
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

console.log("Buyer order confirmation HTML preview generated.");
console.log(`Subject: ${orderConfirmationEmailSubject(orderNumber)}`);
console.log(`Preview: ${ORDER_CONFIRMATION_PREVIEW}`);
console.log(`HTML length: ${html.length} characters`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const out = path.join(process.cwd(), "tmp-order-confirmation-email-preview.html");
  fs.writeFileSync(out, html, "utf8");
  console.log(`Wrote ${out}`);
}
