#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  buildProductSubmittedEmailHtml,
  deliverProductSubmittedEmail,
  productSubmittedEmailSubject,
  productSubmittedIdempotencyKey,
  shouldSendProductSubmittedEmail,
} from "../services/email/productSubmittedEmail.js";
import {
  buildProductApprovedEmailHtml,
  buildProductNeedsChangesEmailHtml,
  deliverProductDecisionEmail,
  productApprovedEmailSubject,
  productDecisionIdempotencyKey,
  productNeedsChangesEmailSubject,
  shouldSendProductDecisionEmail,
} from "../services/email/productReviewEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

const productId = "prod_phone_stand";
const sellerId = "seller-a";

function baseProduct(overrides = {}) {
  return {
    id: productId,
    sellerId,
    name: "Modular Phone Stand",
    priceCents: 899,
    category: "desk",
    approvalStatus: "submitted",
    submittedAt: "2026-09-18T12:00:00.000Z",
    reviewedAt: null,
    reviewNotes: "",
    reviewEmails: {
      submitted: { status: "pending", sentAt: null, messageId: null, lastError: null, attemptCount: 0, cycleId: null },
      decision: { status: "pending", sentAt: null, messageId: null, lastError: null, attemptCount: 0, cycleId: null },
    },
    ...overrides,
  };
}

function createCatalogStore(initialProducts) {
  let catalog = { products: structuredClone(initialProducts) };
  return {
    loadCatalog: async () => structuredClone(catalog),
    saveCatalog: async (next) => {
      catalog = structuredClone(next);
    },
    getProducts: () => catalog.products,
  };
}

const sellers = {
  [sellerId]: { email: "jordan@example.com", businessName: "Jordan Makes", legalName: "Jordan Maker" },
};

async function run() {
  const config = getTransactionalEmailConfig({
    websiteUrl: "https://tenbelow.com",
    sellerProductsUrl: "https://tenbelow.com",
    sellerSupportEmail: "sellers@tenbelow.com",
    backendBaseUrl: "https://tenbelow.onrender.com",
  });

  assert.equal(
    shouldSendProductSubmittedEmail({ previousApprovalStatus: "", submittedEmail: { status: "pending" } }),
    true
  );
  assert.equal(
    shouldSendProductSubmittedEmail({
      previousApprovalStatus: "submitted",
      submittedEmail: { status: "sent", cycleId: "2026-09-18T12:00:00.000Z" },
    }),
    false
  );
  assert.equal(
    shouldSendProductSubmittedEmail({
      previousApprovalStatus: "rejected",
      submittedEmail: { status: "sent", cycleId: "old" },
    }),
    true
  );

  const submittedHtml = buildProductSubmittedEmailHtml({
    product: baseProduct(),
    seller: sellers[sellerId],
    config,
  });
  assert.match(submittedHtml, /Product submitted ❄️/);
  assert.match(submittedHtml, /Modular Phone Stand/);
  assert.match(submittedHtml, /\$8\.99/);
  assert.match(submittedHtml, /Desk/);
  assert.match(submittedHtml, /In review/);
  assert.match(submittedHtml, /View My Products/);
  assert.doesNotMatch(submittedHtml, /requiresManualReview/);
  assert.doesNotMatch(submittedHtml, /confidence/);

  const approvedHtml = buildProductApprovedEmailHtml({
    product: baseProduct({ approvalStatus: "approved", imageURLs: ["https://cdn.example/stand.png"] }),
    seller: sellers[sellerId],
    config,
  });
  assert.match(approvedHtml, /You&#39;re approved! 🎉/);
  assert.match(approvedHtml, /ready for customers to discover/);
  assert.match(approvedHtml, /Creator Clips/);
  assert.match(approvedHtml, /<img src="https:\/\/cdn\.example\/stand\.png"/);

  const needsHtml = buildProductNeedsChangesEmailHtml({
    product: baseProduct({ approvalStatus: "rejected" }),
    seller: sellers[sellerId],
    notes: "Add a size photo.\nConfirm filament type.",
    config,
  });
  assert.match(needsHtml, /A few changes are needed/);
  assert.match(needsHtml, /Add a size photo/);
  assert.match(needsHtml, /<br \/>/);
  assert.match(needsHtml, /resubmit the product for review/);
  assert.doesNotMatch(needsHtml, /permanently rejected/);

  const escapedHtml = buildProductNeedsChangesEmailHtml({
    product: baseProduct({ name: `<img>` }),
    seller: { businessName: `<script>x</script>` },
    notes: `<script>alert(1)</script>`,
    config,
  });
  assert.doesNotMatch(escapedHtml, /<script>/);
  assert.match(escapedHtml, /&lt;script&gt;/);

  const noImageHtml = buildProductSubmittedEmailHtml({
    product: baseProduct({ imageURLs: ["/media/private.jpg"] }),
    seller: sellers[sellerId],
    config,
  });
  assert.doesNotMatch(noImageHtml, /<img /);

  assert.equal(
    productSubmittedIdempotencyKey(productId, "2026-09-18T12:00:00.000Z"),
    `product-submitted:${productId}:2026-09-18T12:00:00.000Z`
  );
  assert.doesNotMatch(productDecisionIdempotencyKey(productId, "approve", "T1"), /Date\.now/);
  assert.match(productApprovedEmailSubject("Stand"), /approved/);
  assert.match(productNeedsChangesEmailSubject("Stand"), /Changes needed/);
  assert.match(productSubmittedEmailSubject("Stand"), /reviewing Stand/);

  // Drafts never hit PUT /seller-products, so no submission email is sent.
  {
    const store = createCatalogStore([]);
    const result = await deliverProductSubmittedEmail({
      product: { name: "Local draft only" },
      previousApprovalStatus: "",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async () => ({ messageId: "nope" }),
    });
    assert.equal(result.skipped, true);
    assert.equal(store.getProducts().length, 0);
  }

  // Initial submission sends once; duplicate while still submitted does not.
  {
    const product = baseProduct();
    const store = createCatalogStore([product]);
    const payloads = [];
    const first = await deliverProductSubmittedEmail({
      product,
      previousApprovalStatus: "",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async (p) => {
        payloads.push(p);
        return { messageId: "sub_1" };
      },
      config,
    });
    assert.equal(first.sent, true);
    assert.equal(payloads[0].idempotencyKey, productSubmittedIdempotencyKey(productId, product.submittedAt));
    assert.equal(store.getProducts()[0].reviewEmails.submitted.status, "sent");
    assert.equal(store.getProducts()[0].approvalStatus, "submitted");

    const duplicate = await deliverProductSubmittedEmail({
      product: store.getProducts()[0],
      previousApprovalStatus: "submitted",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async (p) => {
        payloads.push(p);
        return { messageId: "sub_2" };
      },
    });
    assert.deepEqual(duplicate, { skipped: true, reason: "already_sent_this_cycle", productId });
    assert.equal(payloads.length, 1);
  }

  // Needs-changes then approval send once each; email failure does not change product status.
  {
    const product = baseProduct({
      reviewEmails: {
        submitted: { status: "sent", cycleId: "2026-09-18T12:00:00.000Z", attemptCount: 1 },
        decision: { status: "pending", attemptCount: 0 },
      },
    });
    const store = createCatalogStore([{ ...product, approvalStatus: "rejected", reviewedAt: "2026-09-19T12:00:00.000Z", reviewNotes: "Add a size photo." }]);
    const originalError = console.error;
    console.error = () => {};
    const failed = await deliverProductDecisionEmail({
      product: store.getProducts()[0],
      previousApprovalStatus: "submitted",
      decision: "reject",
      notes: "Add a size photo.",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async () => {
        throw new Error("Resend unavailable");
      },
    });
    console.error = originalError;
    assert.equal(failed.sent, false);
    assert.equal(store.getProducts()[0].approvalStatus, "rejected");
    assert.equal(store.getProducts()[0].reviewEmails.decision.status, "failed");

    const retry = await deliverProductDecisionEmail({
      product: store.getProducts()[0],
      previousApprovalStatus: "rejected",
      decision: "reject",
      notes: "Add a size photo.",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async () => ({ messageId: "rej_1" }),
    });
    assert.equal(retry.sent, true);
    const duplicateReject = await deliverProductDecisionEmail({
      product: store.getProducts()[0],
      previousApprovalStatus: "rejected",
      decision: "reject",
      notes: "Add a size photo.",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async () => ({ messageId: "rej_2" }),
    });
    assert.equal(duplicateReject.skipped, true);
  }

  // New cycle after needs-changes: new submitted email, then new approval email.
  {
    const cycle1SubmittedAt = "2026-09-18T12:00:00.000Z";
    const cycle2SubmittedAt = "2026-09-20T12:00:00.000Z";
    const product = baseProduct({
      submittedAt: cycle2SubmittedAt,
      approvalStatus: "submitted",
      reviewedAt: "2026-09-19T12:00:00.000Z",
      reviewNotes: "Add a size photo.",
      reviewEmails: {
        submitted: { status: "sent", cycleId: cycle1SubmittedAt, attemptCount: 1, messageId: "old_sub" },
        decision: { status: "sent", cycleId: "2026-09-19T12:00:00.000Z", decision: "reject", attemptCount: 1, messageId: "old_rej" },
      },
    });
    const store = createCatalogStore([product]);
    const payloads = [];
    const resubmit = await deliverProductSubmittedEmail({
      product,
      previousApprovalStatus: "rejected",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async (p) => {
        payloads.push(p);
        return { messageId: "sub_cycle2" };
      },
    });
    assert.equal(resubmit.sent, true);
    assert.equal(payloads[0].idempotencyKey, productSubmittedIdempotencyKey(productId, cycle2SubmittedAt));
    assert.equal(store.getProducts()[0].reviewEmails.submitted.cycleId, cycle2SubmittedAt);
    assert.equal(store.getProducts()[0].reviewEmails.decision.messageId, "old_rej");

    const approvedProduct = {
      ...store.getProducts()[0],
      approvalStatus: "approved",
      isApproved: true,
      isActive: true,
      reviewedAt: "2026-09-21T12:00:00.000Z",
    };
    store.saveCatalog({ products: [approvedProduct] });
    const approve = await deliverProductDecisionEmail({
      product: approvedProduct,
      previousApprovalStatus: "submitted",
      decision: "approve",
      notes: "",
      loadSellersFile: () => sellers,
      ...store,
      sendTransactionalEmail: async (p) => {
        payloads.push(p);
        return { messageId: "appr_cycle2" };
      },
    });
    assert.equal(approve.sent, true);
    assert.match(payloads[1].subject, /approved/);
    assert.equal(store.getProducts()[0].reviewEmails.decision.cycleId, "2026-09-21T12:00:00.000Z");
    assert.equal(store.getProducts()[0].reviewEmails.decision.decision, "approve");
    assert.doesNotMatch(JSON.stringify(payloads), /Date\.now/);
  }

  assert.equal(
    shouldSendProductDecisionEmail({
      previousApprovalStatus: "approved",
      decision: "approve",
      decisionEmail: { status: "sent", decision: "approve", cycleId: "T1" },
      cycleId: "T2",
    }),
    false
  );

  console.log("✓ product lifecycle email verification checks passed");
}

run().catch((error) => {
  console.error("✗ product lifecycle email verification failed");
  console.error(error);
  process.exit(1);
});
