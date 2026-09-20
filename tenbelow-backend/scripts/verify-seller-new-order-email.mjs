#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  SELLER_NEW_ORDER_PREVIEW,
  buildSellerNewOrderEmailHtml,
  deliverSellerNewOrderEmail,
  deliverSellerNewOrderEmailsForPaidOrder,
  sellerGreetingName,
  sellerNewOrderEmailSubject,
  sellerNewOrderIdempotencyKey,
  sellerShipmentsForSeller,
  uniqueSellerIdsFromOrder,
} from "../services/email/sellerNewOrderEmail.js";
import { resolveEmailAssetURL } from "../services/email/orderConfirmationEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderId = "11111111-2222-4333-8444-555555555555";
const orderNumber = "TB-8F42C7";

function multiSellerOrder(overrides = {}) {
  return {
    id: orderId,
    orderNumber,
    createdAt: "2026-09-18T04:00:00.000Z",
    currency: "USD",
    totalCents: 4597,
    sellerNewOrderEmails: {},
    shipments: [
      {
        sellerId: "seller-a",
        sellerName: "Jordan Makes",
        shipByDate: "2026-09-22T04:00:00.000Z",
        items: [
          {
            productName: "Phone Stand",
            quantity: 1,
            unitPriceCents: 899,
            selectedColorName: "Blue",
            thumbnailURL: "https://cdn.example/stand.png",
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
            thumbnailURL: "/media/private.jpg",
          },
        ],
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

const sellers = {
  "seller-a": { email: "jordan@example.com", businessName: "Jordan Makes", legalName: "Jordan Maker" },
  "seller-b": { email: "printlab@example.com", businessName: "Print Lab Co.", legalName: "Pat Printer" },
};

async function run() {
  const config = getTransactionalEmailConfig({
    logoUrl: "",
    websiteUrl: "https://tenbelow.com",
    sellerDashboardUrl: "https://tenbelow.com",
    sellerOrdersUrl: "https://tenbelow.com/seller-orders",
    sellerSupportEmail: "sellers@tenbelow.com",
    supportEmail: "support@tenbelow.com",
    backendBaseUrl: "https://tenbelow.onrender.com",
  });

  assert.equal(sellerNewOrderEmailSubject(orderNumber), `You made a sale ❄️ Order ${orderNumber}`);
  assert.equal(sellerNewOrderEmailSubject(""), "You made a sale ❄️ TenBelow");
  assert.equal(SELLER_NEW_ORDER_PREVIEW.includes("TenBelow"), true);
  assert.equal(sellerGreetingName({ businessName: "Jordan Makes" }), "Jordan Makes");
  assert.equal(sellerGreetingName({ legalName: "Jordan Maker" }), "Jordan");
  assert.equal(
    sellerNewOrderIdempotencyKey(orderId, "seller-a"),
    `seller-new-order:${orderId}:seller-a`
  );
  assert.deepEqual(uniqueSellerIdsFromOrder(multiSellerOrder()), ["seller-a", "seller-b"]);
  assert.equal(sellerShipmentsForSeller(multiSellerOrder(), "seller-a").length, 1);
  assert.equal(resolveEmailAssetURL("/media/private.jpg"), null);

  const sellerAHtml = buildSellerNewOrderEmailHtml({
    order: multiSellerOrder(),
    sellerId: "seller-a",
    seller: sellers["seller-a"],
    shippingAddress: {
      name: "Alex Buyer",
      line1: "123 Maker Lane",
      city: "Columbus",
      state: "OH",
      postalCode: "43215",
      country: "US",
    },
    config,
  });
  assert.match(sellerAHtml, /You made a sale! ❄️/);
  assert.match(sellerAHtml, /Good news, Jordan Makes/);
  assert.match(sellerAHtml, /TB-8F42C7/);
  assert.doesNotMatch(sellerAHtml, new RegExp(orderId));
  assert.match(sellerAHtml, /Phone Stand/);
  assert.match(sellerAHtml, /Cable Clip Set/);
  assert.match(sellerAHtml, /Option: Blue/);
  assert.match(sellerAHtml, /Qty 2/);
  assert.match(sellerAHtml, /<img src="https:\/\/cdn\.example\/stand\.png"/);
  assert.match(sellerAHtml, /123 Maker Lane/);
  assert.match(sellerAHtml, /Prepare by/);
  assert.match(sellerAHtml, /View Order/);
  assert.match(sellerAHtml, /Seller Dashboard/);
  assert.match(sellerAHtml, /Need help with this order/);
  assert.match(sellerAHtml, /sellers@tenbelow\.com/);
  assert.match(sellerAHtml, /Seller Agreement/);
  assert.doesNotMatch(sellerAHtml, /Desk Organizer/);
  assert.doesNotMatch(sellerAHtml, /Print Lab Co/);
  assert.doesNotMatch(sellerAHtml, /printlab@example\.com/);
  assert.doesNotMatch(sellerAHtml, /alex@example\.com/);
  assert.doesNotMatch(sellerAHtml, /You earned/);
  assert.doesNotMatch(sellerAHtml, /Sold by /);

  const sellerBHtml = buildSellerNewOrderEmailHtml({
    order: multiSellerOrder(),
    sellerId: "seller-b",
    seller: sellers["seller-b"],
    shippingAddress: { line1: "123 Maker Lane", city: "Columbus", state: "OH" },
    config,
  });
  assert.match(sellerBHtml, /Desk Organizer/);
  assert.match(sellerBHtml, /Print Lab Co/);
  assert.doesNotMatch(sellerBHtml, /Phone Stand/);
  assert.doesNotMatch(sellerBHtml, /Cable Clip Set/);
  assert.doesNotMatch(sellerBHtml, /Jordan Makes/);
  assert.doesNotMatch(sellerBHtml, /<img /);

  const historicalHtml = buildSellerNewOrderEmailHtml({
    order: multiSellerOrder({ orderNumber: undefined, shipments: multiSellerOrder().shipments.map(({ shipByDate, ...rest }) => rest) }),
    sellerId: "seller-a",
    seller: { legalName: "" },
    shippingAddress: {},
    config,
  });
  assert.match(historicalHtml, /Your TenBelow order/);
  assert.doesNotMatch(historicalHtml, new RegExp(orderId));
  assert.match(historicalHtml, /Good news, Creator/);
  assert.match(historicalHtml, /prepared for shipment by the date above/);

  const escapedHtml = buildSellerNewOrderEmailHtml({
    order: multiSellerOrder({
      shipments: [
        {
          sellerId: "seller-a",
          items: [{ productName: `<img onerror=1>`, quantity: 1, unitPriceCents: 100 }],
        },
      ],
    }),
    sellerId: "seller-a",
    seller: { businessName: `<script>x</script>` },
    shippingAddress: { line1: `<street>` },
    config,
  });
  assert.doesNotMatch(escapedHtml, /<script>/);
  assert.match(escapedHtml, /&lt;script&gt;/);

  {
    const store = createOrderStore([multiSellerOrder()]);
    const payloads = [];
    const result = await deliverSellerNewOrderEmailsForPaidOrder({
      orderId,
      shippingAddress: { line1: "123 Maker Lane" },
      ...store,
      loadSellersFile: () => sellers,
      sendTransactionalEmail: async (p) => {
        payloads.push(p);
        return { messageId: `msg-${payloads.length}` };
      },
      config,
    });
    assert.equal(result.results.length, 2);
    assert.equal(result.results.every((entry) => entry.sent), true);
    assert.equal(payloads[0].idempotencyKey, sellerNewOrderIdempotencyKey(orderId, "seller-a"));
    assert.equal(payloads[1].idempotencyKey, sellerNewOrderIdempotencyKey(orderId, "seller-b"));
    assert.match(payloads[0].html, /Phone Stand/);
    assert.doesNotMatch(payloads[0].html, /Desk Organizer/);
    assert.match(payloads[1].html, /Desk Organizer/);
    assert.doesNotMatch(payloads[1].html, /Phone Stand/);
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-a"].status, "sent");
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-b"].status, "sent");
    assert.equal(store.getOrders()[0].totalCents, 4597);
    assert.equal(store.getOrders()[0].id, orderId);
  }

  {
    const store = createOrderStore([
      multiSellerOrder({
        sellerNewOrderEmails: {
          "seller-a": { status: "sent", sentAt: "2026-09-18T04:00:00.000Z", messageId: "existing", lastError: null, attemptCount: 1 },
        },
      }),
    ]);
    const payloads = [];
    await deliverSellerNewOrderEmailsForPaidOrder({
      orderId,
      shippingAddress: {},
      ...store,
      loadSellersFile: () => sellers,
      sendTransactionalEmail: async (p) => {
        payloads.push(p);
        return { messageId: "new" };
      },
    });
    assert.equal(payloads.length, 1);
    assert.equal(payloads[0].to, "printlab@example.com");
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-a"].messageId, "existing");
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-b"].status, "sent");
  }

  {
    const store = createOrderStore([multiSellerOrder()]);
    const originalError = console.error;
    console.error = () => {};
    const result = await deliverSellerNewOrderEmailsForPaidOrder({
      orderId,
      shippingAddress: {},
      ...store,
      loadSellersFile: () => sellers,
      sendTransactionalEmail: async ({ to }) => {
        if (to === "jordan@example.com") throw new Error("Resend unavailable");
        return { messageId: "b-ok" };
      },
    });
    console.error = originalError;
    assert.equal(result.results[0].sent, false);
    assert.equal(result.results[1].sent, true);
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-a"].status, "failed");
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-a"].attemptCount, 1);
    assert.equal(store.getOrders()[0].sellerNewOrderEmails["seller-b"].status, "sent");
    assert.equal(store.getOrders()[0].totalCents, 4597);
    assert.equal(store.getOrders()[0].id, orderId);
  }

  {
    const skipped = await deliverSellerNewOrderEmail({
      orderId,
      sellerId: "seller-a",
      shippingAddress: {},
      loadOrdersFile: () => [multiSellerOrder()],
      saveOrdersFile: () => {},
      loadSellersFile: () => ({ "seller-a": { businessName: "Jordan Makes" } }),
      sendTransactionalEmail: async () => ({ messageId: "nope" }),
    });
    assert.deepEqual(skipped, { skipped: true, reason: "missing_seller_email", sellerId: "seller-a" });
  }

  console.log("✓ seller new-order email verification checks passed");
}

run().catch((error) => {
  console.error("✗ seller new-order email verification failed");
  console.error(error);
  process.exit(1);
});
