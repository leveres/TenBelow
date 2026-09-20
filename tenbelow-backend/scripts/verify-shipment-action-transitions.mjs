#!/usr/bin/env node
import assert from "node:assert/strict";
import { resolveShipmentAction } from "../domain/phase1/shipmentActions.js";
import { deliverBuyerDeliveryConfirmationEmail } from "../services/email/deliveryConfirmationEmail.js";
import { deliverBuyerShipmentShippedEmail } from "../services/email/shipmentUpdateEmail.js";

const orderId = "11111111-2222-4333-8444-555555555555";
const timestamp = "2026-09-24T15:30:00.000Z";

function baseShipment(overrides = {}) {
  return {
    id: "SHP-A",
    sellerId: "seller-a",
    sellerName: "Jordan Makes",
    status: "preparing",
    carrier: null,
    trackingNumber: null,
    shippedAt: null,
    deliveredAt: null,
    items: [{ productName: "Phone Stand", quantity: 1, productId: "p1" }],
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

function applyResolved(order, shipmentIndex, resolved) {
  const next = structuredClone(order);
  next.shipments[shipmentIndex] = resolved.nextShipment;
  return next;
}

async function run() {
  {
    const rejected = resolveShipmentAction({
      action: "markDelivered",
      shipment: baseShipment({ status: "preparing" }),
      timestamp,
    });
    assert.equal(rejected.ok, false);
    assert.match(rejected.error, /must be marked shipped/i);
  }

  {
    const allowed = resolveShipmentAction({
      action: "markDelivered",
      shipment: baseShipment({
        status: "shipped",
        carrier: "USPS",
        trackingNumber: "9400",
        shippedAt: "2026-09-22T12:00:00.000Z",
      }),
      timestamp,
    });
    assert.equal(allowed.ok, true);
    assert.equal(allowed.mutated, true);
    assert.equal(allowed.nextShipment.status, "delivered");
    assert.equal(allowed.nextShipment.deliveredAt, timestamp);
    assert.equal(allowed.sendDeliveredEmail, true);
    assert.equal(allowed.sendPush, true);
    assert.equal(allowed.pushAction, "markDelivered");
  }

  {
    const originalDeliveredAt = "2026-09-23T10:00:00.000Z";
    const already = resolveShipmentAction({
      action: "markDelivered",
      shipment: baseShipment({
        status: "delivered",
        deliveredAt: originalDeliveredAt,
        carrier: "USPS",
        trackingNumber: "9400",
      }),
      timestamp: "2026-09-25T12:00:00.000Z",
    });
    assert.equal(already.ok, true);
    assert.equal(already.mutated, false);
    assert.equal(already.nextShipment.deliveredAt, originalDeliveredAt);
    assert.equal(already.sendDeliveredEmail, true);
    assert.equal(already.sendPush, false);
  }

  {
    const cancelled = resolveShipmentAction({
      action: "markDelivered",
      shipment: baseShipment({ status: "cancelled" }),
      timestamp,
    });
    assert.equal(cancelled.ok, false);
    assert.match(cancelled.error, /cancelled/i);
  }

  {
    const cancelledShip = resolveShipmentAction({
      action: "markShipped",
      shipment: baseShipment({ status: "cancelled" }),
      carrier: "USPS",
      trackingNumber: "9400",
      timestamp,
    });
    assert.equal(cancelledShip.ok, false);
  }

  {
    const deliveredShip = resolveShipmentAction({
      action: "markShipped",
      shipment: baseShipment({ status: "delivered", deliveredAt: timestamp }),
      carrier: "USPS",
      trackingNumber: "9400",
      timestamp,
    });
    assert.equal(deliveredShip.ok, false);
    assert.match(deliveredShip.error, /delivered/i);
  }

  {
    const validShip = resolveShipmentAction({
      action: "markShipped",
      shipment: baseShipment({ status: "preparing" }),
      carrier: "USPS",
      trackingNumber: "9400111899562537869483",
      timestamp,
    });
    assert.equal(validShip.ok, true);
    assert.equal(validShip.mutated, true);
    assert.equal(validShip.nextShipment.status, "shipped");
    assert.equal(validShip.nextShipment.carrier, "USPS");
    assert.equal(validShip.sendShippedEmail, true);
    assert.equal(validShip.sendPush, true);
  }

  {
    const alreadyShipped = resolveShipmentAction({
      action: "markShipped",
      shipment: baseShipment({
        status: "shipped",
        shippedAt: "2026-09-22T12:00:00.000Z",
        carrier: "USPS",
        trackingNumber: "9400",
      }),
      carrier: "UPS",
      trackingNumber: "1Z999",
      timestamp: "2026-09-25T12:00:00.000Z",
    });
    assert.equal(alreadyShipped.ok, true);
    assert.equal(alreadyShipped.mutated, false);
    assert.equal(alreadyShipped.nextShipment.carrier, "USPS");
    assert.equal(alreadyShipped.nextShipment.shippedAt, "2026-09-22T12:00:00.000Z");
    assert.equal(alreadyShipped.sendShippedEmail, true);
    assert.equal(alreadyShipped.sendPush, false);
  }

  // Multi-seller independence: resolving seller A does not touch seller B fields.
  {
    const order = {
      id: orderId,
      buyerEmail: "alex@example.com",
      shipments: [
        baseShipment({
          id: "SHP-A",
          sellerId: "seller-a",
          status: "shipped",
          carrier: "USPS",
          trackingNumber: "9400",
        }),
        baseShipment({
          id: "SHP-B",
          sellerId: "seller-b",
          sellerName: "Print Lab Co.",
          status: "preparing",
        }),
      ],
    };
    const resolved = resolveShipmentAction({
      action: "markDelivered",
      shipment: order.shipments[0],
      timestamp,
    });
    const next = applyResolved(order, 0, resolved);
    assert.equal(next.shipments[0].status, "delivered");
    assert.equal(next.shipments[1].status, "preparing");
    assert.equal(next.shipments[1].sellerName, "Print Lab Co.");
  }

  // Valid markDelivered sends delivery email once; repeat does not duplicate.
  {
    const store = createOrderStore([
      {
        id: orderId,
        orderNumber: "TB-8F42C7",
        buyerEmail: "alex@example.com",
        shipments: [
          baseShipment({
            status: "shipped",
            carrier: "USPS",
            trackingNumber: "9400",
            shippedAt: "2026-09-22T12:00:00.000Z",
          }),
          baseShipment({
            id: "SHP-B",
            sellerId: "seller-b",
            sellerName: "Print Lab Co.",
            status: "preparing",
          }),
        ],
      },
    ]);

    const first = resolveShipmentAction({
      action: "markDelivered",
      shipment: store.getOrders()[0].shipments[0],
      timestamp,
    });
    assert.equal(first.ok, true);
    const afterFirst = applyResolved(store.getOrders()[0], 0, first);
    store.saveOrdersFile([afterFirst]);

    let sendCount = 0;
    const emailResult = await deliverBuyerDeliveryConfirmationEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({ "alex@example.com": { fullName: "Alex Buyer" } }),
      ...store,
      sendTransactionalEmail: async () => {
        sendCount += 1;
        return { messageId: "del_1" };
      },
    });
    assert.equal(emailResult.sent, true);
    assert.equal(sendCount, 1);
    assert.equal(store.getOrders()[0].shipments[0].deliveredEmail.status, "sent");
    assert.equal(store.getOrders()[0].shipments[1].deliveredEmail, undefined);

    const repeat = resolveShipmentAction({
      action: "markDelivered",
      shipment: store.getOrders()[0].shipments[0],
      timestamp: "2026-09-26T12:00:00.000Z",
    });
    assert.equal(repeat.ok, true);
    assert.equal(repeat.mutated, false);
    assert.equal(repeat.nextShipment.deliveredAt, timestamp);
    assert.equal(repeat.sendPush, false);

    const repeatEmail = await deliverBuyerDeliveryConfirmationEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({}),
      ...store,
      sendTransactionalEmail: async () => {
        sendCount += 1;
        return { messageId: "del_2" };
      },
    });
    assert.deepEqual(repeatEmail, { skipped: true, reason: "already_sent", shipmentId: "SHP-A" });
    assert.equal(sendCount, 1);
    assert.equal(store.getOrders()[0].shipments[0].deliveredEmail.messageId, "del_1");
  }

  // Failed delivery email can be retried via markDelivered without rewriting deliveredAt.
  {
    const deliveredAt = "2026-09-24T15:30:00.000Z";
    const store = createOrderStore([
      {
        id: orderId,
        orderNumber: "TB-8F42C7",
        buyerEmail: "alex@example.com",
        shipments: [
          baseShipment({
            status: "delivered",
            deliveredAt,
            carrier: "USPS",
            trackingNumber: "9400",
            deliveredEmail: {
              status: "failed",
              sentAt: null,
              messageId: null,
              lastError: "Resend unavailable",
              attemptCount: 1,
            },
          }),
        ],
      },
    ]);

    const retryAction = resolveShipmentAction({
      action: "markDelivered",
      shipment: store.getOrders()[0].shipments[0],
      timestamp: "2026-09-26T12:00:00.000Z",
    });
    assert.equal(retryAction.ok, true);
    assert.equal(retryAction.mutated, false);
    assert.equal(retryAction.nextShipment.deliveredAt, deliveredAt);
    assert.equal(retryAction.sendDeliveredEmail, true);
    assert.equal(retryAction.sendPush, false);

    const retryEmail = await deliverBuyerDeliveryConfirmationEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({ "alex@example.com": { fullName: "Alex" } }),
      ...store,
      sendTransactionalEmail: async () => ({ messageId: "del_retry" }),
    });
    assert.equal(retryEmail.sent, true);
    assert.equal(store.getOrders()[0].shipments[0].status, "delivered");
    assert.equal(store.getOrders()[0].shipments[0].deliveredAt, deliveredAt);
    assert.equal(store.getOrders()[0].shipments[0].deliveredEmail.status, "sent");
    assert.equal(store.getOrders()[0].shipments[0].deliveredEmail.messageId, "del_retry");
  }

  // Valid markShipped still sends shipped email; push flags remain correct.
  {
    const store = createOrderStore([
      {
        id: orderId,
        orderNumber: "TB-8F42C7",
        buyerEmail: "alex@example.com",
        shipments: [baseShipment({ status: "preparing" })],
      },
    ]);
    const shipped = resolveShipmentAction({
      action: "markShipped",
      shipment: store.getOrders()[0].shipments[0],
      carrier: "USPS",
      trackingNumber: "9400111899562537869483",
      timestamp,
    });
    assert.equal(shipped.sendPush, true);
    assert.equal(shipped.pushAction, "markShipped");
    store.saveOrdersFile([applyResolved(store.getOrders()[0], 0, shipped)]);
    const emailResult = await deliverBuyerShipmentShippedEmail({
      orderId,
      shipmentId: "SHP-A",
      loadBuyersFile: () => ({ "alex@example.com": { fullName: "Alex" } }),
      ...store,
      sendTransactionalEmail: async () => ({ messageId: "ship_1" }),
    });
    assert.equal(emailResult.sent, true);
    assert.equal(store.getOrders()[0].shipments[0].status, "shipped");
    assert.equal(store.getOrders()[0].shipments[0].shippedEmail.status, "sent");
  }

  console.log("✓ shipment action transition verification checks passed");
}

run().catch((error) => {
  console.error("✗ shipment action transition verification failed");
  console.error(error);
  process.exit(1);
});
