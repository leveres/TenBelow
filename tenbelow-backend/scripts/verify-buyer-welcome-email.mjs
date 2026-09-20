#!/usr/bin/env node
/**
 * Buyer welcome email Phase 1 verification (no network / no real Resend).
 * Run: node scripts/verify-buyer-welcome-email.mjs
 */
import assert from "node:assert/strict";
import {
  BUYER_WELCOME_EMAIL_PREVIEW,
  BUYER_WELCOME_EMAIL_SUBJECT,
  buildBuyerWelcomeEmailHtml,
  buyerFirstName,
  deliverBuyerWelcomeEmailIfNeeded,
  normalizeBuyerWelcomeEmailFields,
  scheduleBuyerWelcomeAfterVerification,
} from "../services/email/buyerWelcomeEmail.js";
import { escapeHtml, emailButton } from "../services/email/emailHtml.js";
import { getTransactionalEmailConfig } from "../services/email/emailConfig.js";

function createBuyerStore(initial = {}) {
  let buyers = structuredClone(initial);
  return {
    loadBuyersFile: () => structuredClone(buyers),
    saveBuyersFile: (next) => {
      buyers = structuredClone(next);
    },
    getBuyers: () => buyers,
  };
}

async function run() {
  // HTML generation + personalization
  const namedHtml = buildBuyerWelcomeEmailHtml({
    buyer: { fullName: "Mike Hames", email: "mike@example.com" },
    config: getTransactionalEmailConfig({
      logoUrl: "",
      shopUrl: "https://tenbelow.com",
      websiteUrl: "https://tenbelow.com",
      termsUrl: "https://tenbelow.onrender.com/terms.html",
      privacyUrl: "https://tenbelow.onrender.com/privacy.html",
      supportEmail: "support@tenbelow.com",
    }),
  });
  assert.match(namedHtml, /Welcome to TenBelow, Mike ❄️/);
  assert.match(namedHtml, /officially in/);
  assert.match(namedHtml, /Find something different/);
  assert.match(namedHtml, /Shopping on TenBelow/);
  assert.match(namedHtml, /Start Shopping/);
  assert.match(namedHtml, /https:\/\/tenbelow\.com/);
  assert.match(namedHtml, /Terms/);
  assert.match(namedHtml, /Privacy Policy/);
  assert.match(namedHtml, /Support/);
  assert.match(namedHtml, /Creator Clips/);
  assert.match(namedHtml, /Weekly Drops/);
  assert.match(namedHtml, /independent/);
  assert.match(namedHtml, /view status or tracking/);
  assert.doesNotMatch(namedHtml, /<img /); // no logo URL → text fallback, no broken image
  assert.match(namedHtml, /TenBelow/);
  assert.equal(BUYER_WELCOME_EMAIL_SUBJECT.includes("Welcome to TenBelow"), true);
  assert.equal(BUYER_WELCOME_EMAIL_PREVIEW.includes("3D-printed"), true);

  // Missing first name fallback
  const fallbackHtml = buildBuyerWelcomeEmailHtml({
    buyer: { fullName: "", email: "guest@example.com" },
    config: getTransactionalEmailConfig({ logoUrl: "", shopUrl: "https://tenbelow.com" }),
  });
  assert.match(fallbackHtml, /Welcome to TenBelow ❄️/);
  assert.doesNotMatch(fallbackHtml, /Welcome to TenBelow, there/);
  assert.equal(buyerFirstName(""), "");
  assert.equal(buyerFirstName("  Ada Lovelace "), "Ada");

  // Safe HTML escaping
  const unsafe = buildBuyerWelcomeEmailHtml({
    buyer: { fullName: `<script>alert("x")</script>`, email: "x@example.com" },
    config: getTransactionalEmailConfig({ logoUrl: "", shopUrl: "https://tenbelow.com" }),
  });
  assert.doesNotMatch(unsafe, /<script>/);
  assert.match(unsafe, /&lt;script&gt;/);
  assert.equal(escapeHtml(`<"&>`), `&lt;&quot;&amp;&gt;`);

  // CTA / footer helpers
  const cta = emailButton("Start Shopping", "https://tenbelow.com");
  assert.match(cta, /Start Shopping/);
  assert.match(cta, /https:\/\/tenbelow\.com/);

  // Logo configured → img present
  const withLogo = buildBuyerWelcomeEmailHtml({
    buyer: { fullName: "Sam", email: "sam@example.com" },
    config: getTransactionalEmailConfig({
      logoUrl: "https://cdn.example.com/tenbelow-logo.png",
      shopUrl: "https://tenbelow.com",
    }),
  });
  assert.match(withLogo, /cdn\.example\.com\/tenbelow-logo\.png/);

  // Scheduling rules
  const bypassSchedule = scheduleBuyerWelcomeAfterVerification({
    email: "a@example.com",
    bypassEnabled: true,
    deliveryArgs: {},
  });
  assert.deepEqual(bypassSchedule, { queued: false, reason: "bypass_email" });

  // Delivery: not verified
  {
    const store = createBuyerStore({
      "buyer@example.com": {
        email: "buyer@example.com",
        fullName: "Buyer",
        emailVerified: false,
        welcomeEmail: normalizeBuyerWelcomeEmailFields({}),
      },
    });
    const result = await deliverBuyerWelcomeEmailIfNeeded({
      email: "buyer@example.com",
      ...store,
      sendTransactionalEmail: async () => {
        throw new Error("should not send");
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "not_verified" });
  }

  // Delivery: BYPASS_EMAIL
  {
    const store = createBuyerStore({
      "buyer@example.com": {
        email: "buyer@example.com",
        fullName: "Buyer",
        emailVerified: true,
        welcomeEmail: normalizeBuyerWelcomeEmailFields({}),
      },
    });
    const result = await deliverBuyerWelcomeEmailIfNeeded({
      email: "buyer@example.com",
      ...store,
      isEmailBypassed: () => true,
      sendTransactionalEmail: async () => {
        throw new Error("should not send");
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "bypass_email" });
  }

  // Delivery: success + persistence
  {
    const store = createBuyerStore({
      "buyer@example.com": {
        email: "buyer@example.com",
        fullName: "Buyer One",
        emailVerified: true,
        welcomeEmail: normalizeBuyerWelcomeEmailFields({}),
      },
    });
    let sentPayload = null;
    const result = await deliverBuyerWelcomeEmailIfNeeded({
      email: "buyer@example.com",
      ...store,
      sendTransactionalEmail: async (payload) => {
        sentPayload = payload;
        return { messageId: "msg_123", recipients: ["buyer@example.com"] };
      },
    });
    assert.equal(result.sent, true);
    assert.equal(result.messageId, "msg_123");
    assert.equal(sentPayload.subject, BUYER_WELCOME_EMAIL_SUBJECT);
    assert.equal(sentPayload.idempotencyKey, "buyer-welcome:buyer@example.com");
    assert.match(sentPayload.html, /Welcome to TenBelow, Buyer ❄️/);
    const saved = store.getBuyers()["buyer@example.com"].welcomeEmail;
    assert.equal(saved.status, "sent");
    assert.equal(saved.messageId, "msg_123");
    assert.ok(saved.sentAt);
    assert.equal(saved.lastError, null);
    assert.equal(saved.attemptCount, 1);
  }

  // Duplicate prevention
  {
    const store = createBuyerStore({
      "buyer@example.com": {
        email: "buyer@example.com",
        fullName: "Buyer",
        emailVerified: true,
        welcomeEmail: {
          status: "sent",
          sentAt: "2026-01-01T00:00:00.000Z",
          messageId: "msg_existing",
          lastError: null,
          attemptCount: 1,
        },
      },
    });
    let sendCalls = 0;
    const result = await deliverBuyerWelcomeEmailIfNeeded({
      email: "buyer@example.com",
      ...store,
      sendTransactionalEmail: async () => {
        sendCalls += 1;
        return { messageId: "msg_new" };
      },
    });
    assert.deepEqual(result, { skipped: true, reason: "already_sent" });
    assert.equal(sendCalls, 0);
  }

  // Email failure does not throw; persists failed state
  {
    const store = createBuyerStore({
      "buyer@example.com": {
        email: "buyer@example.com",
        fullName: "Buyer",
        emailVerified: true,
        welcomeEmail: normalizeBuyerWelcomeEmailFields({}),
      },
    });
    const previousError = console.error;
    console.error = () => {};
    const result = await deliverBuyerWelcomeEmailIfNeeded({
      email: "buyer@example.com",
      ...store,
      sendTransactionalEmail: async () => {
        throw new Error("Resend unavailable");
      },
    });
    console.error = previousError;
    assert.equal(result.sent, false);
    assert.match(result.error, /Resend unavailable/);
    const saved = store.getBuyers()["buyer@example.com"].welcomeEmail;
    assert.equal(saved.status, "failed");
    assert.match(saved.lastError, /Resend unavailable/);
    assert.equal(saved.attemptCount, 1);
  }

  // Successful verification scheduling (non-bypass) queues without throwing
  {
    let queued = false;
    // scheduleBuyerWelcomeAfterVerification always queues via setImmediate when not bypassed.
    // We verify it returns queued:true and that a subsequent deliver after verify works —
    // the verify route itself remains responsible for calling schedule only after OTP success.
    const scheduleResult = scheduleBuyerWelcomeAfterVerification({
      email: "buyer@example.com",
      bypassEnabled: false,
      deliveryArgs: {
        loadBuyersFile: () => ({
          "buyer@example.com": {
            email: "buyer@example.com",
            fullName: "Buyer",
            emailVerified: true,
            welcomeEmail: normalizeBuyerWelcomeEmailFields({}),
          },
        }),
        saveBuyersFile: () => {},
        sendTransactionalEmail: async () => {
          queued = true;
          return { messageId: "queued_msg" };
        },
        isEmailBypassed: () => false,
      },
    });
    assert.deepEqual(scheduleResult, { queued: true });
    await new Promise((resolve) => setTimeout(resolve, 25));
    assert.equal(queued, true);
  }

  console.log("✓ buyer welcome email verification checks passed");
}

run().catch((error) => {
  console.error("✗ buyer welcome email verification failed");
  console.error(error);
  process.exit(1);
});
