#!/usr/bin/env node
import "dotenv/config";
import {
  buildDeliveryConfirmationEmailHtml,
  deliveryConfirmationEmailPreviewText,
  deliveryConfirmationEmailSubject,
} from "../services/email/deliveryConfirmationEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderNumber = "TB-8F42C7";
const config = getTransactionalEmailConfig({
  logoUrl: "",
  websiteUrl: "https://tenbelow.com",
  ordersUrl: "https://tenbelow.com",
  supportEmail: "support@tenbelow.com",
});

const buyer = { fullName: "Alex Buyer", email: "alex@example.com" };

const jordanShipment = {
  id: "SHP-JORDAN1",
  sellerId: "seller-a",
  sellerName: "Jordan Makes",
  status: "delivered",
  deliveredAt: "2026-09-24T15:30:00.000Z",
  carrier: "USPS",
  trackingNumber: "9400111899562537869483",
  items: [
    { productName: "Modular Phone Stand", quantity: 1, selectedColorName: "Frost Blue" },
    { productName: "Cable Clip Set", quantity: 2, selectedColorName: "White" },
  ],
};

const printLabPreparing = {
  id: "SHP-PRINT01",
  sellerId: "seller-b",
  sellerName: "Print Lab Co.",
  status: "preparing",
  items: [{ productName: "Desk Organizer", quantity: 1 }],
};

const printLabShipped = {
  ...printLabPreparing,
  status: "shipped",
  carrier: "UPS",
  trackingNumber: "1Z999AA10123456784",
};

const partialHtml = buildDeliveryConfirmationEmailHtml({
  order: {
    id: "11111111-2222-4333-8444-555555555555",
    orderNumber,
    buyerEmail: "alex@example.com",
    shipments: [jordanShipment, printLabShipped],
  },
  shipment: jordanShipment,
  buyer,
  config,
});

const completeHtml = buildDeliveryConfirmationEmailHtml({
  order: {
    id: "11111111-2222-4333-8444-555555555555",
    orderNumber,
    buyerEmail: "alex@example.com",
    shipments: [jordanShipment],
  },
  shipment: jordanShipment,
  buyer,
  config,
});

console.log("Delivery confirmation HTML previews generated.");
console.log(`Partial subject: ${deliveryConfirmationEmailSubject({ isEntireOrderDelivered: false })}`);
console.log(`Complete subject: ${deliveryConfirmationEmailSubject({ isEntireOrderDelivered: true })}`);
console.log(`Partial preview: ${deliveryConfirmationEmailPreviewText({ isEntireOrderDelivered: false })}`);
console.log(`Complete preview: ${deliveryConfirmationEmailPreviewText({ isEntireOrderDelivered: true })}`);

if (process.argv.includes("--write-preview")) {
  const fs = await import("fs");
  const path = await import("path");
  const partialOut = path.join(process.cwd(), "tmp-delivery-confirmation-email-preview-partial.html");
  const completeOut = path.join(process.cwd(), "tmp-delivery-confirmation-email-preview-complete.html");
  fs.writeFileSync(partialOut, partialHtml, "utf8");
  fs.writeFileSync(completeOut, completeHtml, "utf8");
  console.log(`Wrote ${partialOut}`);
  console.log(`Wrote ${completeOut}`);
}
