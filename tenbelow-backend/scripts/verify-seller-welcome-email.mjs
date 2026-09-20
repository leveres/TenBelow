#!/usr/bin/env node
/**
 * Seller welcome Phase 2 verification. No network or real email is sent.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  SELLER_WELCOME_EMAIL_PREVIEW,
  SELLER_WELCOME_EMAIL_SUBJECT,
  buildSellerWelcomeEmailAttachments,
  buildSellerWelcomeEmailHtml,
  sendSellerWelcomeEmail,
} from "../services/sellerWelcomeEmail.js";
import {
  deliverSellerWelcomeEmailIfNeeded,
  queueSellerWelcomeEmail,
} from "../services/sellerOnboardingEmail.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";
import { getActiveSellerAgreementDocument } from "../legal/sellerAgreementDocuments.js";

const agreementDocument = getActiveSellerAgreementDocument();
const acceptedAt = "2026-09-18T02:15:00.000Z";

function sellerRecord(overrides = {}) {
  return {
    email: "creator@example.com",
    legalName: "Jordan Example",
    businessName: "Jordan Makes",
    appOnboardingCompletedAt: "2026-09-18T02:20:00.000Z",
    sellerAgreement: {
      accepted: true,
      acceptedAt,
      documentId: agreementDocument.id,
      version: agreementDocument.versionSlug,
      versionLabel: agreementDocument.versionLabel,
      legalNameAtAcceptance: "Jordan Example",
    },
    welcomeEmail: {
      status: "pending",
      sentAt: null,
      messageId: null,
      lastError: null,
      attemptCount: 0,
    },
    ...overrides,
  };
}

function acceptance(overrides = {}) {
  return {
    documentId: agreementDocument.id,
    version: agreementDocument.versionSlug,
    versionLabel: agreementDocument.versionLabel,
    acceptedAt,
    sellerLegalName: "Jordan Example",
    ...overrides,
  };
}

function testConfig(overrides = {}) {
  return getTransactionalEmailConfig({
    logoUrl: "",
    websiteUrl: "https://tenbelow.example",
    sellerDashboardUrl: "https://seller.tenbelow.example/dashboard",
    sellerResourcesUrl: "",
    termsUrl: "https://tenbelow.example/terms",
    privacyUrl: "https://tenbelow.example/privacy",
    supportEmail: "support@tenbelow.example",
    sellerSupportEmail: "sellers@tenbelow.example",
    backendBaseUrl: "https://api.tenbelow.example",
    ...overrides,
  });
}

function createSellerStore(initial) {
  let sellers = structuredClone(initial);
  return {
    loadSellersFile: () => structuredClone(sellers),
    saveSellersFile: (next) => {
      sellers = structuredClone(next);
    },
    getSellers: () => sellers,
  };
}

async function run() {
  const html = buildSellerWelcomeEmailHtml({
    seller: sellerRecord(),
    agreementAcceptance: acceptance(),
    agreementDocument,
    config: testConfig(),
  });

  assert.equal(
    SELLER_WELCOME_EMAIL_SUBJECT,
    "Welcome to TenBelow — Your Creator Store Starts Here ❄️"
  );
  assert.equal(
    SELLER_WELCOME_EMAIL_PREVIEW,
    "Your seller account is ready. Let's get your storefront ready for TenBelow."
  );
  assert.match(html, /Welcome to TenBelow, Jordan ❄️/);
  assert.match(html, /Jordan Makes/);
  assert.match(html, /Your TenBelow Store/);
  assert.match(html, /Open Seller Dashboard/);
  assert.match(html, /https:\/\/seller\.tenbelow\.example\/dashboard/);
  assert.match(html, new RegExp(`Agreement version:<\\/strong> ${agreementDocument.versionLabel}`));
  assert.match(html, /Accepted:<\/strong> [^<]*2026/);
  assert.match(
    html,
    new RegExp(`https:\\/\\/api\\.tenbelow\\.example${agreementDocument.publicPath}`)
  );
  assert.match(html, /Seller Agreement/);
  assert.match(html, /sellers@tenbelow\.example/);
  assert.match(html, /Watch for creator feature and content submission opportunities/);
  assert.doesNotMatch(html, /<img /); // text fallback when logo URL is absent

  const escaped = buildSellerWelcomeEmailHtml({
    seller: sellerRecord({
      legalName: `<script>alert("name")</script>`,
      businessName: `<img src=x onerror="alert(1)">`,
    }),
    agreementAcceptance: acceptance({
      sellerLegalName: `<script>alert("name")</script>`,
      versionLabel: `<b>unsafe</b>`,
    }),
    agreementDocument,
    config: testConfig(),
  });
  assert.doesNotMatch(escaped, /<script>/);
  assert.doesNotMatch(escaped, /<img src=x/);
  assert.doesNotMatch(escaped, /<b>unsafe<\/b>/);
  assert.match(escaped, /&lt;script&gt;/);
  assert.match(escaped, /&lt;img src=x/);
  assert.match(escaped, /&lt;b&gt;unsafe&lt;\/b&gt;/);

  const logoHtml = buildSellerWelcomeEmailHtml({
    seller: sellerRecord(),
    agreementAcceptance: acceptance(),
    agreementDocument,
    config: testConfig({ logoUrl: "https://cdn.example/tenbelow.png" }),
  });
  assert.match(logoHtml, /<img /);
  assert.match(logoHtml, /https:\/\/cdn\.example\/tenbelow\.png/);

  const attachments = buildSellerWelcomeEmailAttachments(agreementDocument);
  assert.equal(agreementDocument.pdfAvailable, true);
  assert.equal(attachments.length, 1);
  assert.equal(attachments[0].filename, `${agreementDocument.id}.pdf`);
  assert.ok(attachments[0].content.length > 0);
  assert.match(html, /PDF copy of the exact agreement you accepted is attached/);

  const noPdfDocument = {
    ...agreementDocument,
    pdfAvailable: false,
    pdfPath: null,
  };
  const fallbackHtml = buildSellerWelcomeEmailHtml({
    seller: sellerRecord(),
    agreementAcceptance: acceptance(),
    agreementDocument: noPdfDocument,
    config: testConfig(),
  });
  assert.equal(buildSellerWelcomeEmailAttachments(noPdfDocument).length, 0);
  assert.match(fallbackHtml, /view or download your accepted agreement/);
  assert.doesNotMatch(fallbackHtml, /PDF copy of the exact agreement/);

  let sentPayload;
  const sendResult = await sendSellerWelcomeEmail({
    seller: sellerRecord(),
    sellerId: "seller-123",
    agreementAcceptance: acceptance(),
    sendTransactionalEmail: async (payload) => {
      sentPayload = payload;
      return { messageId: "resend_123" };
    },
  });
  assert.equal(sendResult.messageId, "resend_123");
  assert.equal(sentPayload.subject, SELLER_WELCOME_EMAIL_SUBJECT);
  assert.equal(
    sentPayload.idempotencyKey,
    `seller-welcome:seller-123:${agreementDocument.id}`
  );
  assert.equal(sentPayload.attachments.length, 1);

  // Onboarding gate remains enforced before delivery.
  {
    const store = createSellerStore({
      "seller-123": sellerRecord({ appOnboardingCompletedAt: null }),
    });
    let sendCount = 0;
    const result = await deliverSellerWelcomeEmailIfNeeded({
      sellerId: "seller-123",
      requireAppOnboardingComplete: true,
      ...store,
      sendTransactionalEmail: async () => {
        sendCount += 1;
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "app_onboarding_incomplete" });
    assert.equal(sendCount, 0);
  }

  // Successful delivery persists the existing welcomeEmail state shape.
  {
    const store = createSellerStore({ "seller-123": sellerRecord() });
    let prismaSyncCount = 0;
    const result = await deliverSellerWelcomeEmailIfNeeded({
      sellerId: "seller-123",
      requireAppOnboardingComplete: true,
      ...store,
      sendTransactionalEmail: async () => ({ messageId: "resend_saved" }),
      upsertSellerAgreementAcceptanceToPrisma: async () => {
        prismaSyncCount += 1;
      },
    });
    assert.equal(result.sent, true);
    const saved = store.getSellers()["seller-123"].welcomeEmail;
    assert.equal(saved.status, "sent");
    assert.equal(saved.messageId, "resend_saved");
    assert.ok(saved.sentAt);
    assert.equal(saved.lastError, null);
    assert.equal(saved.attemptCount, 1);
    assert.equal(prismaSyncCount, 1);
  }

  // Duplicate protection powers both automatic delivery and admin resend.
  {
    const store = createSellerStore({
      "seller-123": sellerRecord({
        welcomeEmail: {
          status: "sent",
          sentAt: acceptedAt,
          messageId: "existing",
          lastError: null,
          attemptCount: 1,
        },
      }),
    });
    let sendCount = 0;
    const result = await deliverSellerWelcomeEmailIfNeeded({
      sellerId: "seller-123",
      ...store,
      sendTransactionalEmail: async () => {
        sendCount += 1;
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "already_sent" });
    assert.equal(sendCount, 0);
  }

  // Provider failure is captured and returned; it does not throw into onboarding.
  {
    const store = createSellerStore({ "seller-123": sellerRecord() });
    const originalError = console.error;
    console.error = () => {};
    const result = await deliverSellerWelcomeEmailIfNeeded({
      sellerId: "seller-123",
      requireAppOnboardingComplete: true,
      ...store,
      sendTransactionalEmail: async () => {
        throw new Error("Resend unavailable");
      },
      upsertSellerAgreementAcceptanceToPrisma: async () => {},
    });
    console.error = originalError;
    assert.equal(result.sent, false);
    assert.match(result.error, /Resend unavailable/);
    const saved = store.getSellers()["seller-123"].welcomeEmail;
    assert.equal(saved.status, "failed");
    assert.match(saved.lastError, /Resend unavailable/);
    assert.equal(saved.attemptCount, 1);
  }

  // Queue stays asynchronous and invokes the same guarded delivery service.
  {
    const store = createSellerStore({ "seller-123": sellerRecord() });
    let sent = false;
    queueSellerWelcomeEmail({
      sellerId: "seller-123",
      requireAppOnboardingComplete: true,
      ...store,
      sendTransactionalEmail: async () => {
        sent = true;
        return { messageId: "queued" };
      },
    });
    assert.equal(sent, false);
    await new Promise((resolve) => setTimeout(resolve, 25));
    assert.equal(sent, true);
  }

  // The production route still records completion, queues, and responds independently.
  const serverSource = readFileSync(new URL("../server.js", import.meta.url), "utf8");
  const routeStart = serverSource.indexOf('app.post("/seller/app-onboarding-complete"');
  const routeEnd = serverSource.indexOf('app.get("/seller-onboarding-link/', routeStart);
  const routeSource = serverSource.slice(routeStart, routeEnd);
  assert.ok(routeStart >= 0 && routeEnd > routeStart);
  assert.match(routeSource, /appOnboardingCompletedAt/);
  assert.match(routeSource, /queueSellerWelcomeEmail/);
  assert.match(routeSource, /requireAppOnboardingComplete:\s*true/);
  assert.match(routeSource, /res\.json/);

  console.log("✓ seller welcome email verification checks passed");
}

run().catch((error) => {
  console.error("✗ seller welcome email verification failed");
  console.error(error);
  process.exit(1);
});
