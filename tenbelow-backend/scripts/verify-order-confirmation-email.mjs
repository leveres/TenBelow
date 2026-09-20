#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  ORDER_CONFIRMATION_PREVIEW,
  buildOrderConfirmationEmailHtml,
  deliverBuyerOrderConfirmationEmail,
  formatMoneyCents,
  orderConfirmationEmailSubject,
  orderConfirmationIdempotencyKey,
  resolveEmailAssetURL,
} from "../services/email/orderConfirmationEmail.js";
import {
  allocateCustomerOrderNumber,
  customerFacingOrderNumber,
  normalizeCustomerOrderNumber,
  resolvePersistedCustomerOrderNumber,
} from "../domain/phase1/orderNumber.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const orderId = "11111111-2222-4333-8444-555555555555";
const orderNumber = "TB-8F42C7";

function mockOrder(overrides = {}) {
  return {
    id: orderId,
    orderNumber,
    createdAt: "2026-09-18T04:00:00.000Z",
    currency: "USD",
    totalCents: 2598,
    confirmationEmail: { status: "pending", sentAt: null, messageId: null, lastError: null },
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
        ],
      },
    ],
    ...overrides,
  };
}

function multiSellerOrder() {
  return mockOrder({
    totalCents: 4597,
    shipments: [
      {
        sellerId: "seller-a",
        sellerName: "Jordan Makes",
        items: [{ productName: "Stand", quantity: 1, unitPriceCents: 899 }],
      },
      {
        sellerId: "seller-b",
        sellerName: "Print Lab Co.",
        items: [{ productName: "Organizer", quantity: 2, unitPriceCents: 499, selectedColorName: "Gray" }],
      },
    ],
  });
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
    backendBaseUrl: "https://api.tenbelow.com",
  });

  assert.equal(normalizeCustomerOrderNumber("tb-8f42c7"), "TB-8F42C7");
  assert.equal(normalizeCustomerOrderNumber(orderId), "");
  assert.equal(customerFacingOrderNumber({ orderNumber }), "TB-8F42C7");
  assert.equal(customerFacingOrderNumber({ id: orderId }), "");
  assert.equal(
    resolvePersistedCustomerOrderNumber({
      existingOrderNumber: "TB-8F42C7",
      existingNumbers: ["TB-111111"],
    }),
    "TB-8F42C7"
  );
  assert.equal(
    resolvePersistedCustomerOrderNumber({
      existingOrderNumber: "",
      existingNumbers: ["TB-AAAAAA"],
      generate: () => "TB-BBBBBB",
    }),
    "TB-BBBBBB"
  );
  assert.equal(
    allocateCustomerOrderNumber(["TB-AAAAAA"], {
      generate: (() => {
        let calls = 0;
        return () => {
          calls += 1;
          return calls === 1 ? "TB-AAAAAA" : "TB-CCCCCC";
        };
      })(),
    }),
    "TB-CCCCCC"
  );
  assert.throws(() =>
    allocateCustomerOrderNumber(["TB-AAAAAA"], {
      generate: () => "TB-AAAAAA",
      maxAttempts: 3,
    })
  );
  assert.equal(
    resolvePersistedCustomerOrderNumber({
      existingOrderNumber: "",
      existingNumbers: ["TB-AAAAAA"],
      generate: () => "TB-AAAAAA",
      maxAttempts: 2,
    }),
    ""
  );

  assert.equal(orderConfirmationEmailSubject(orderNumber), `Order confirmed ❄️ TenBelow #${orderNumber}`);
  assert.equal(orderConfirmationEmailSubject(""), "Order confirmed ❄️ TenBelow");
  assert.equal(ORDER_CONFIRMATION_PREVIEW.includes("TenBelow"), true);
  assert.equal(formatMoneyCents(2598), "$25.98");
  assert.equal(resolveEmailAssetURL("https://cdn.example/stand.png"), "https://cdn.example/stand.png");
  assert.equal(resolveEmailAssetURL("http://cdn.example/stand.png"), "http://cdn.example/stand.png");
  assert.equal(resolveEmailAssetURL("/media/x.jpg"), null);
  assert.equal(resolveEmailAssetURL("not-a-url"), null);
  assert.equal(resolveEmailAssetURL(""), null);
  assert.equal(resolveEmailAssetURL("javascript:alert(1)"), null);

  const singleHtml = buildOrderConfirmationEmailHtml({
    order: mockOrder(),
    buyer: { fullName: "Alex Buyer" },
    paymentSummary: { subtotalCents: 899, shippingCents: 599, totalCents: 1498, currency: "USD" },
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
  assert.match(singleHtml, /Thanks for your order, Alex/);
  assert.match(singleHtml, /Order confirmed ❄️/);
  assert.match(singleHtml, /TB-8F42C7/);
  assert.doesNotMatch(singleHtml, new RegExp(orderId));
  assert.match(singleHtml, /Jordan Makes/);
  assert.doesNotMatch(singleHtml, /Sold by Jordan Makes/);
  assert.match(singleHtml, /<img src="https:\/\/cdn\.example\/stand\.png"/);
  assert.match(singleHtml, /Option: Blue/);
  assert.match(singleHtml, /Subtotal/);
  assert.match(singleHtml, /\$8\.99/);
  assert.match(singleHtml, /Total paid/);
  assert.match(singleHtml, /Ship to/);
  assert.match(singleHtml, /123 Maker Lane/);
  assert.match(singleHtml, /Tracking information will appear when it becomes available/);
  assert.doesNotMatch(singleHtml, /We&#39;ll email tracking when items ship/);
  assert.match(singleHtml, /View Order/);
  assert.match(singleHtml, /Need help with your order/);
  assert.match(singleHtml, /support@tenbelow\.com/);

  const missingImageHtml = buildOrderConfirmationEmailHtml({
    order: mockOrder({
      shipments: [
        {
          sellerId: "seller-a",
          sellerName: "Jordan Makes",
          items: [{ productName: "Phone Stand", quantity: 1, unitPriceCents: 899, thumbnailURL: "" }],
        },
      ],
    }),
    buyer: { fullName: "Alex Buyer" },
    paymentSummary: { subtotalCents: 899, shippingCents: 0, totalCents: 899, currency: "USD" },
    shippingAddress: { line1: "123 Maker Lane" },
    config,
  });
  assert.doesNotMatch(missingImageHtml, /<img /);

  const invalidImageHtml = buildOrderConfirmationEmailHtml({
    order: mockOrder({
      shipments: [
        {
          sellerId: "seller-a",
          sellerName: "Jordan Makes",
          items: [{ productName: "Phone Stand", quantity: 1, unitPriceCents: 899, thumbnailURL: "/media/demo.jpg" }],
        },
      ],
    }),
    buyer: { fullName: "Alex Buyer" },
    paymentSummary: { subtotalCents: 899, shippingCents: 0, totalCents: 899, currency: "USD" },
    shippingAddress: { line1: "123 Maker Lane" },
    config,
  });
  assert.doesNotMatch(invalidImageHtml, /<img /);

  const multiHtml = buildOrderConfirmationEmailHtml({
    order: multiSellerOrder(),
    buyer: { fullName: "Alex Buyer" },
    paymentSummary: { subtotalCents: 1897, shippingCents: 700, totalCents: 2597, currency: "USD" },
    shippingAddress: { line1: "123 Maker Lane", city: "Columbus", state: "OH" },
    config,
  });
  assert.match(multiHtml, /Jordan Makes/);
  assert.match(multiHtml, /Print Lab Co\./);
  assert.doesNotMatch(multiHtml, /Sold by /);

  const historicalHtml = buildOrderConfirmationEmailHtml({
    order: mockOrder({ orderNumber: undefined }),
    buyer: { fullName: "Alex Buyer" },
    paymentSummary: { subtotalCents: 899, shippingCents: 0, totalCents: 899, currency: "USD" },
    shippingAddress: {},
    config,
  });
  assert.match(historicalHtml, /Your TenBelow order/);
  assert.doesNotMatch(historicalHtml, new RegExp(orderId));
  assert.doesNotMatch(historicalHtml, /TB-8F42C7/);

  const fallbackHtml = buildOrderConfirmationEmailHtml({
    order: mockOrder(),
    buyer: { fullName: "" },
    paymentSummary: { subtotalCents: 899, shippingCents: 0, totalCents: 899, currency: "USD" },
    shippingAddress: {},
    config,
  });
  assert.match(fallbackHtml, /Thanks for your order, there/);

  const escapedHtml = buildOrderConfirmationEmailHtml({
    order: mockOrder({
      shipments: [
        {
          sellerName: `<script>alert("x")</script>`,
          items: [{ productName: `<img onerror=1>`, quantity: 1, unitPriceCents: 100 }],
        },
      ],
    }),
    buyer: { fullName: `<bad>` },
    paymentSummary: { subtotalCents: 100, shippingCents: 0, totalCents: 100, currency: "USD" },
    shippingAddress: { line1: `<street>` },
    config,
  });
  assert.doesNotMatch(escapedHtml, /<script>/);
  assert.match(escapedHtml, /&lt;script&gt;/);

  assert.equal(orderConfirmationIdempotencyKey(orderId), `order-confirmation:${orderId}`);

  {
    const store = createOrderStore([mockOrder()]);
    let payload;
    const result = await deliverBuyerOrderConfirmationEmail({
      orderId,
      buyerEmail: "alex@example.com",
      paymentSummary: { subtotalCents: 899, shippingCents: 599, totalCents: 1498, currency: "USD" },
      shippingAddress: { line1: "123 Maker Lane" },
      paymentIntentId: "pi_123",
      loadBuyersFile: () => ({ "alex@example.com": { fullName: "Alex Buyer" } }),
      ...store,
      sendTransactionalEmail: async (p) => {
        payload = p;
        return { messageId: "email_123" };
      },
      config,
    });
    assert.equal(result.sent, true);
    assert.equal(payload.idempotencyKey, orderConfirmationIdempotencyKey(orderId));
    assert.match(payload.subject, /TB-8F42C7/);
    assert.doesNotMatch(payload.subject, new RegExp(orderId));
    assert.equal(store.getOrders()[0].confirmationEmail.status, "sent");
    assert.equal(store.getOrders()[0].confirmationEmail.messageId, "email_123");
    assert.equal(store.getOrders()[0].orderNumber, orderNumber);
    assert.equal(store.getOrders()[0].id, orderId);
  }

  {
    const store = createOrderStore([
      mockOrder({
        confirmationEmail: {
          status: "sent",
          sentAt: "2026-09-18T04:00:00.000Z",
          messageId: "existing",
          lastError: null,
        },
      }),
    ]);
    let sendCount = 0;
    const result = await deliverBuyerOrderConfirmationEmail({
      orderId,
      buyerEmail: "alex@example.com",
      paymentSummary: { subtotalCents: 899, shippingCents: 599, totalCents: 1498, currency: "USD" },
      shippingAddress: {},
      loadBuyersFile: () => ({}),
      ...store,
      sendTransactionalEmail: async () => {
        sendCount += 1;
        return { messageId: "new" };
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "already_sent" });
    assert.equal(sendCount, 0);
    assert.equal(store.getOrders()[0].orderNumber, orderNumber);
  }

  {
    const store = createOrderStore([mockOrder()]);
    const originalError = console.error;
    console.error = () => {};
    const result = await deliverBuyerOrderConfirmationEmail({
      orderId,
      buyerEmail: "alex@example.com",
      paymentSummary: { subtotalCents: 899, shippingCents: 599, totalCents: 1498, currency: "USD" },
      shippingAddress: {},
      loadBuyersFile: () => ({}),
      ...store,
      sendTransactionalEmail: async () => {
        throw new Error("Resend unavailable");
      },
    });
    console.error = originalError;
    assert.equal(result.sent, false);
    assert.match(result.error, /Resend unavailable/);
    assert.equal(store.getOrders()[0].confirmationEmail.status, "failed");
    assert.equal(store.getOrders()[0].totalCents, 2598);
    assert.equal(store.getOrders()[0].id, orderId);
    assert.equal(store.getOrders()[0].orderNumber, orderNumber);
  }

  console.log("✓ order confirmation email verification checks passed");
}

run().catch((error) => {
  console.error("✗ order confirmation email verification failed");
  console.error(error);
  process.exit(1);
});
