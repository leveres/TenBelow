#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  buildShipmentShippedEmailHtml,
  deliverBuyerShipmentShippedEmail,
  isEntireOrderShipped,
  remainingUnshippedShipments,
  shipmentShippedEmailPreviewText,
  shipmentShippedEmailSubject,
  shipmentShippedIdempotencyKey,
} from "../services/email/shipmentUpdateEmail.js";
import { resolveEmailAssetURL } from "../services/email/orderConfirmationEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderId = "11111111-2222-4333-8444-555555555555";
const orderNumber = "TB-8F42C7";

function multiSellerOrder(overrides = {}) {
  return {
    id: orderId,
    orderNumber,
    buyerEmail: "alex@example.com",
    shipToCity: "Columbus",
    shipToState: "OH",
    totalCents: 4597,
    shipments: [
      {
        id: "SHP-A",
        sellerId: "seller-a",
        sellerName: "Jordan Makes",
        status: "shipped",
        carrier: "USPS",
        trackingNumber: "9400111899562537869483",
        items: [
          {
            productName: "Phone Stand",
            quantity: 1,
            selectedColorName: "Blue",
            thumbnailURL: "https://cdn.example/stand.png",
          },
          { productName: "Cable Clip Set", quantity: 2, selectedColorName: "White" },
        ],
      },
      {
        id: "SHP-B",
        sellerId: "seller-b",
        sellerName: "Print Lab Co.",
        status: "preparing",
        carrier: null,
        trackingNumber: null,
        items: [{ productName: "Desk Organizer", quantity: 1, thumbnailURL: "/media/private.jpg" }],
      },
    ],
    ...overrides,
  };
}

function createOrderStore(initialOrders) {
  let orders = structuredClone(initialOrders);
  return {
    loadOrdersFile: () => structuredClone(orders),
    saveOrdersFile: (next) => {
      orders = structuredClone(next);
    },
    getOrders: () => orders,
  };
}

async function run() {
  const config = getTransactionalEmailConfig({
    logoUrl: "",
    websiteUrl: "https://tenbelow.com",
    ordersUrl: "https://tenbelow.com/orders",
    supportEmail: "support@tenbelow.com",
  });

  assert.equal(shipmentShippedEmailSubject(orderNumber), `Your TenBelow order ${orderNumber} is on the way ❄️`);
  assert.equal(shipmentShippedEmailSubject(""), "Your TenBelow order is on the way ❄️");
  assert.equal(
    shipmentShippedEmailPreviewText({ isEntireOrderShipped: false }),
    "Good news — part of your TenBelow order has shipped."
  );
  assert.equal(
    shipmentShippedEmailPreviewText({ isEntireOrderShipped: true }),
    "Good news — your TenBelow order has shipped."
  );
  assert.equal(shipmentShippedIdempotencyKey(orderId, "SHP-A"), `shipment-shipped:${orderId}:SHP-A`);
  assert.equal(isEntireOrderShipped(multiSellerOrder()), false);
  assert.equal(remainingUnshippedShipments(multiSellerOrder(), "SHP-A").length, 1);
  assert.equal(resolveEmailAssetURL("/media/private.jpg"), null);

  const partialHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder(),
    shipment: multiSellerOrder().shipments[0],
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.match(partialHtml, /It&#39;s on the way! ❄️/);
  assert.match(partialHtml, /Good news, Alex/);
  assert.match(partialHtml, /Jordan Makes has shipped their part/);
  assert.match(partialHtml, /TB-8F42C7/);
  assert.doesNotMatch(partialHtml, new RegExp(orderId));
  assert.match(partialHtml, /Phone Stand/);
  assert.match(partialHtml, /Cable Clip Set/);
  assert.match(partialHtml, /Option: Blue/);
  assert.match(partialHtml, /Qty 2/);
  assert.match(partialHtml, /<img src="https:\/\/cdn\.example\/stand\.png"/);
  assert.match(partialHtml, /USPS/);
  assert.match(partialHtml, /9400111899562537869483/);
  assert.doesNotMatch(partialHtml, /Track Package/);
  assert.match(partialHtml, /Columbus, OH/);
  assert.match(partialHtml, /still being prepared and will update separately/);
  assert.match(partialHtml, /View Order/);
  assert.match(partialHtml, /Need help with this shipment/);
  assert.match(partialHtml, /support@tenbelow\.com/);
  assert.doesNotMatch(partialHtml, /Desk Organizer/);
  assert.doesNotMatch(partialHtml, /Print Lab Co/);
  assert.doesNotMatch(partialHtml, /seller-b/);

  const completeHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder({
      shipments: [
        multiSellerOrder().shipments[0],
        { ...multiSellerOrder().shipments[1], status: "shipped", carrier: "UPS", trackingNumber: "1Z999" },
      ],
    }),
    shipment: { ...multiSellerOrder().shipments[1], status: "shipped", carrier: "UPS", trackingNumber: "1Z999" },
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.equal(
    isEntireOrderShipped(
      multiSellerOrder({
        shipments: [
          multiSellerOrder().shipments[0],
          { ...multiSellerOrder().shipments[1], status: "shipped" },
        ],
      })
    ),
    true
  );
  assert.match(completeHtml, /your TenBelow order has shipped/);
  assert.match(completeHtml, /Desk Organizer/);
  assert.doesNotMatch(completeHtml, /still being prepared/);
  assert.doesNotMatch(completeHtml, /Phone Stand/);
  assert.doesNotMatch(completeHtml, /9400111899562537869483/);

  const singleHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder({ shipments: [multiSellerOrder().shipments[0]] }),
    shipment: multiSellerOrder().shipments[0],
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.match(singleHtml, /your TenBelow order has shipped/);
  assert.doesNotMatch(singleHtml, /still being prepared/);

  const noImageHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder(),
    shipment: {
      ...multiSellerOrder().shipments[0],
      items: [{ productName: "Phone Stand", quantity: 1, thumbnailURL: "/media/x.jpg" }],
    },
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.doesNotMatch(noImageHtml, /<img /);

  const noTrackingHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder(),
    shipment: { ...multiSellerOrder().shipments[0], carrier: "", trackingNumber: "" },
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.match(noTrackingHtml, /Tracking information wasn&rsquo;t provided/);
  assert.doesNotMatch(noTrackingHtml, /Carrier:/);
  assert.doesNotMatch(noTrackingHtml, /Tracking number:/);

  const historicalHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder({ orderNumber: undefined, shipToCity: "", shipToState: "" }),
    shipment: multiSellerOrder().shipments[0],
    buyer: { fullName: "" },
    config,
  });
  assert.match(historicalHtml, /Your TenBelow order/);
  assert.doesNotMatch(historicalHtml, new RegExp(orderId));
  assert.match(historicalHtml, /Good news, there/);
  assert.doesNotMatch(historicalHtml, /Shipping to/);

  const escapedHtml = buildShipmentShippedEmailHtml({
    order: multiSellerOrder(),
    shipment: {
      ...multiSellerOrder().shipments[0],
      sellerName: `<script>x</script>`,
      carrier: `<usps>`,
      trackingNumber: `<track>`,
      items: [{ productName: `<img onerror=1>`, quantity: 1 }],
    },
    buyer: { fullName: `<bad>` },
    config,
  });
  assert.doesNotMatch(escapedHtml, /<script>/);
  assert.match(escapedHtml, /&lt;script&gt;/);

  {
    const store = createOrderStore([multiSellerOrder()]);
    let payload;
    const result = await deliverBuyerShipmentShippedEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({ "alex@example.com": { fullName: "Alex Buyer" } }),
      ...store,
      sendTransactionalEmail: async (p) => {
        payload = p;
        return { messageId: "ship_1" };
      },
      config,
    });
    assert.equal(result.sent, true);
    assert.equal(payload.idempotencyKey, shipmentShippedIdempotencyKey(orderId, "SHP-A"));
    assert.match(payload.subject, /TB-8F42C7/);
    assert.doesNotMatch(payload.html, /Desk Organizer/);
    const saved = store.getOrders()[0];
    assert.equal(saved.shipments[0].shippedEmail.status, "sent");
    assert.equal(saved.shipments[0].status, "shipped");
    assert.equal(saved.shipments[1].shippedEmail, undefined);
    assert.equal(saved.shipments[1].status, "preparing");
    assert.equal(saved.totalCents, 4597);
  }

  {
    const store = createOrderStore([
      multiSellerOrder({
        shipments: [
          {
            ...multiSellerOrder().shipments[0],
            shippedEmail: {
              status: "sent",
              sentAt: "2026-09-18T04:00:00.000Z",
              messageId: "existing",
              lastError: null,
              attemptCount: 1,
            },
          },
          multiSellerOrder().shipments[1],
        ],
      }),
    ]);
    let sendCount = 0;
    const result = await deliverBuyerShipmentShippedEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({}),
      ...store,
      sendTransactionalEmail: async () => {
        sendCount += 1;
        return { messageId: "new" };
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "already_sent", shipmentId: "SHP-A" });
    assert.equal(sendCount, 0);
    assert.equal(store.getOrders()[0].shipments[0].shippedEmail.messageId, "existing");
  }

  {
    const store = createOrderStore([multiSellerOrder()]);
    const originalError = console.error;
    console.error = () => {};
    const result = await deliverBuyerShipmentShippedEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({}),
      ...store,
      sendTransactionalEmail: async () => {
        throw new Error("Resend unavailable");
      },
    });
    console.error = originalError;
    assert.equal(result.sent, false);
    const saved = store.getOrders()[0];
    assert.equal(saved.shipments[0].shippedEmail.status, "failed");
    assert.equal(saved.shipments[0].status, "shipped");
    assert.equal(saved.shipments[0].carrier, "USPS");
    assert.equal(saved.shipments[0].trackingNumber, "9400111899562537869483");
    assert.equal(saved.shipments[1].status, "preparing");
    assert.equal(saved.totalCents, 4597);
  }

  console.log("✓ shipment update email verification checks passed");
}

run().catch((error) => {
  console.error("✗ shipment update email verification failed");
  console.error(error);
  process.exit(1);
});
