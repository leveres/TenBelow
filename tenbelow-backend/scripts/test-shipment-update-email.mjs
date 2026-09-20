#!/usr/bin/env node
import "dotenv/config";
import {
  buildShipmentShippedEmailHtml,
  shipmentShippedEmailSubject,
  shipmentShippedEmailPreviewText,
} from "../services/email/shipmentUpdateEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderNumber = "TB-8F42C7";
const config = getTransactionalEmailConfig({
  logoUrl: "",
  websiteUrl: "https://tenbelow.com",
  ordersUrl: "https://tenbelow.com",
  supportEmail: "support@tenbelow.com",
  backendBaseUrl: "https://tenbelow.onrender.com",
});

const buyer = { fullName: "Alex Buyer", email: "alex@example.com" };

const jordanShipment = {
  id: "SHP-JORDAN1",
  sellerId: "seller-a",
  sellerName: "Jordan Makes",
  status: "shipped",
  carrier: "USPS",
  trackingNumber: "9400111899562537869483",
  items: [
    { productName: "Modular Phone Stand", quantity: 1, selectedColorName: "Frost Blue" },
    { productName: "Cable Clip Set", quantity: 2, selectedColorName: "White" },
  ],
};

const printLabShipment = {
  id: "SHP-PRINT01",
  sellerId: "seller-b",
  sellerName: "Print Lab Co.",
  status: "preparing",
  items: [{ productName: "Desk Organizer", quantity: 1 }],
};

const partialHtml = buildShipmentShippedEmailHtml({
  order: {
    id: "11111111-2222-4333-8444-555555555555",
    orderNumber,
    buyerEmail: "alex@example.com",
    shipToCity: "Columbus",
    shipToState: "OH",
    shipments: [jordanShipment, printLabShipment],
  },
  shipment: jordanShipment,
  buyer,
  config,
});

const completeHtml = buildShipmentShippedEmailHtml({
  order: {
    id: "11111111-2222-4333-8444-555555555555",
    orderNumber,
    buyerEmail: "alex@example.com",
    shipToCity: "Columbus",
    shipToState: "OH",
    shipments: [jordanShipment],
  },
  shipment: jordanShipment,
  buyer,
  config,
});

console.log("Shipment update HTML previews generated.");
console.log(`Subject: ${shipmentShippedEmailSubject(orderNumber)}`);
console.log(`Partial preview: ${shipmentShippedEmailPreviewText({ isEntireOrderShipped: false })}`);
console.log(`Complete preview: ${shipmentShippedEmailPreviewText({ isEntireOrderShipped: true })}`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const partialOut = path.join(process.cwd(), "tmp-shipment-update-email-preview-partial.html");
  const completeOut = path.join(process.cwd(), "tmp-shipment-update-email-preview-complete.html");
  fs.writeFileSync(partialOut, partialHtml, "utf8");
  fs.writeFileSync(completeOut, completeHtml, "utf8");
  console.log(`Wrote ${partialOut}`);
  console.log(`Wrote ${completeOut}`);
}
