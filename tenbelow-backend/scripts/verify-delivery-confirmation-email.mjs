#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  buildDeliveryConfirmationEmailHtml,
  deliverBuyerDeliveryConfirmationEmail,
  deliveryConfirmationEmailPreviewText,
  deliveryConfirmationEmailSubject,
  deliveryConfirmationIdempotencyKey,
  isEntireOrderDelivered,
  remainingOrderStatusCopy,
} from "../services/email/deliveryConfirmationEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderId = "11111111-2222-4333-8444-555555555555";
const orderNumber = "TB-8F42C7";

function multiSellerOrder(overrides = {}) {
  return {
    id: orderId,
    orderNumber,
    buyerEmail: "alex@example.com",
    totalCents: 4597,
    shipments: [
      {
        id: "SHP-A",
        sellerId: "seller-a",
        sellerName: "Jordan Makes",
        status: "delivered",
        deliveredAt: "2026-09-24T15:30:00.000Z",
        carrier: "USPS",
        trackingNumber: "9400111899562537869483",
        shippedEmail: { status: "sent", messageId: "ship_a", attemptCount: 1 },
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
        status: "shipped",
        carrier: "UPS",
        trackingNumber: "1Z999AA10123456784",
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

  assert.equal(
    deliveryConfirmationEmailSubject({ isEntireOrderDelivered: true }),
    "Delivered ❄️ Your TenBelow order has arrived"
  );
  assert.equal(
    deliveryConfirmationEmailSubject({ isEntireOrderDelivered: false }),
    "Delivered ❄️ Part of your TenBelow order has arrived"
  );
  assert.equal(
    deliveryConfirmationEmailPreviewText({ isEntireOrderDelivered: true }),
    "Your TenBelow order has been marked delivered."
  );
  assert.equal(
    deliveryConfirmationEmailPreviewText({ isEntireOrderDelivered: false }),
    "A shipment from your TenBelow order has been marked delivered."
  );
  assert.equal(deliveryConfirmationIdempotencyKey(orderId, "SHP-A"), `shipment-delivered:${orderId}:SHP-A`);
  assert.equal(isEntireOrderDelivered(multiSellerOrder()), false);
  assert.match(remainingOrderStatusCopy(multiSellerOrder(), "SHP-A"), /still on the way/);

  const partialHtml = buildDeliveryConfirmationEmailHtml({
    order: multiSellerOrder(),
    shipment: multiSellerOrder().shipments[0],
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.match(partialHtml, /Delivered! 📦/);
  assert.match(partialHtml, /Good news, Alex/);
  assert.match(partialHtml, /your shipment from Jordan Makes has been marked delivered/);
  assert.match(partialHtml, /TB-8F42C7/);
  assert.doesNotMatch(partialHtml, new RegExp(orderId));
  assert.match(partialHtml, /Phone Stand/);
  assert.match(partialHtml, /Cable Clip Set/);
  assert.match(partialHtml, /Option: Blue/);
  assert.match(partialHtml, /Qty 2/);
  assert.match(partialHtml, /<img src="https:\/\/cdn\.example\/stand\.png"/);
  assert.match(partialHtml, /September 24, 2026/);
  assert.match(partialHtml, /USPS/);
  assert.match(partialHtml, /still on the way/);
  assert.match(partialHtml, /View Order/);
  assert.match(partialHtml, /Something not right/);
  assert.match(partialHtml, /share your experience in TenBelow/);
  assert.match(partialHtml, /support@tenbelow\.com/);
  assert.doesNotMatch(partialHtml, /Desk Organizer/);
  assert.doesNotMatch(partialHtml, /Print Lab Co/);
  assert.doesNotMatch(partialHtml, /1Z999AA10123456784/);
  assert.doesNotMatch(partialHtml, /Leave a Review/);

  const completeHtml = buildDeliveryConfirmationEmailHtml({
    order: multiSellerOrder({
      shipments: [
        multiSellerOrder().shipments[0],
        { ...multiSellerOrder().shipments[1], status: "delivered", deliveredAt: "2026-09-25T12:00:00.000Z" },
      ],
    }),
    shipment: { ...multiSellerOrder().shipments[1], status: "delivered", deliveredAt: "2026-09-25T12:00:00.000Z" },
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.match(completeHtml, /your TenBelow order has been marked delivered/);
  assert.match(completeHtml, /Desk Organizer/);
  assert.doesNotMatch(completeHtml, /still on the way/);
  assert.doesNotMatch(completeHtml, /still being prepared/);
  assert.doesNotMatch(completeHtml, /Phone Stand/);
  assert.doesNotMatch(completeHtml, /9400111899562537869483/);

  const singleHtml = buildDeliveryConfirmationEmailHtml({
    order: multiSellerOrder({ shipments: [multiSellerOrder().shipments[0]] }),
    shipment: multiSellerOrder().shipments[0],
    buyer: { fullName: "Alex Buyer" },
    config,
  });
  assert.match(singleHtml, /your TenBelow order has been marked delivered/);
  assert.doesNotMatch(singleHtml, /The rest of your order/);

  const preparingCopy = remainingOrderStatusCopy(
    multiSellerOrder({
      shipments: [
        multiSellerOrder().shipments[0],
        { ...multiSellerOrder().shipments[1], status: "preparing" },
      ],
    }),
    "SHP-A"
  );
  assert.match(preparingCopy, /still being prepared/);
  assert.doesNotMatch(preparingCopy, /on the way/);

  const historicalHtml = buildDeliveryConfirmationEmailHtml({
    order: multiSellerOrder({ orderNumber: undefined }),
    shipment: { ...multiSellerOrder().shipments[0], deliveredAt: "", carrier: "", trackingNumber: "" },
    buyer: { fullName: "" },
    config,
  });
  assert.match(historicalHtml, /Your TenBelow order/);
  assert.doesNotMatch(historicalHtml, new RegExp(orderId));
  assert.match(historicalHtml, /Good news, there/);
  assert.match(historicalHtml, /marked delivered in TenBelow/);
  assert.doesNotMatch(historicalHtml, /USPS/);

  const escapedHtml = buildDeliveryConfirmationEmailHtml({
    order: multiSellerOrder(),
    shipment: {
      ...multiSellerOrder().shipments[0],
      sellerName: `<script>x</script>`,
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
    const result = await deliverBuyerDeliveryConfirmationEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({ "alex@example.com": { fullName: "Alex Buyer" } }),
      ...store,
      sendTransactionalEmail: async (p) => {
        payload = p;
        return { messageId: "del_1" };
      },
      config,
    });
    assert.equal(result.sent, true);
    assert.equal(payload.idempotencyKey, deliveryConfirmationIdempotencyKey(orderId, "SHP-A"));
    assert.match(payload.subject, /Part of your TenBelow order has arrived/);
    assert.doesNotMatch(payload.html, /Desk Organizer/);
    const saved = store.getOrders()[0];
    assert.equal(saved.shipments[0].deliveredEmail.status, "sent");
    assert.equal(saved.shipments[0].shippedEmail.status, "sent");
    assert.equal(saved.shipments[0].status, "delivered");
    assert.equal(saved.shipments[1].deliveredEmail, undefined);
    assert.equal(saved.shipments[1].status, "shipped");
    assert.equal(saved.totalCents, 4597);
  }

  {
    const store = createOrderStore([
      multiSellerOrder({
        shipments: [
          {
            ...multiSellerOrder().shipments[0],
            deliveredEmail: {
              status: "sent",
              sentAt: "2026-09-24T16:00:00.000Z",
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
    const result = await deliverBuyerDeliveryConfirmationEmail({
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
    assert.equal(store.getOrders()[0].shipments[0].deliveredEmail.messageId, "existing");
  }

  {
    const store = createOrderStore([multiSellerOrder()]);
    const originalError = console.error;
    console.error = () => {};
    const result = await deliverBuyerDeliveryConfirmationEmail({
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
    assert.equal(saved.shipments[0].deliveredEmail.status, "failed");
    assert.equal(saved.shipments[0].status, "delivered");
    assert.equal(saved.shipments[0].carrier, "USPS");
    assert.equal(saved.shipments[0].shippedEmail.status, "sent");
    assert.equal(saved.shipments[1].status, "shipped");
    assert.equal(saved.totalCents, 4597);
  }

  console.log("✓ delivery confirmation email verification checks passed");
}

run().catch((error) => {
  console.error("✗ delivery confirmation email verification failed");
  console.error(error);
  process.exit(1);
});
