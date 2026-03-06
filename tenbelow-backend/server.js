import "dotenv/config";
import express from "express";
import cors from "cors";
import Stripe from "stripe";
import { Resend } from "resend";
import { readFileSync, writeFileSync } from "fs";
import crypto from "crypto";

const app = express();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const resend = new Resend(process.env.RESEND_API_KEY);

const EMAIL_FROM = process.env.EMAIL_FROM || "TenBelow <noreply@tenbelow.com>";
const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:3000";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch ${url} → ${res.status}`);
  return res.json();
}

async function fetchCatalog() {
  if (process.env.CATALOG_URL) {
    try { return await fetchJSON(process.env.CATALOG_URL); } catch (e) {
      console.warn("CATALOG_URL fetch failed:", e.message);
    }
  }
  try {
    return JSON.parse(readFileSync(new URL("../TenBelow/Data/Remote/products.json", import.meta.url), "utf-8"));
  } catch { return { version: 1, updatedAt: new Date().toISOString(), products: [] }; }
}

async function fetchConfig() {
  if (process.env.CONFIG_URL) {
    try { return await fetchJSON(process.env.CONFIG_URL); } catch (e) {
      console.warn("CONFIG_URL fetch failed:", e.message);
    }
  }
  try {
    return JSON.parse(readFileSync(new URL("../TenBelow/Data/Remote/config.json", import.meta.url), "utf-8"));
  } catch { return { version: 2, minimumOrderCents: 2000 }; }
}

async function fetchSellers() {
  if (process.env.SELLERS_URL) {
    try { return await fetchJSON(process.env.SELLERS_URL); } catch (e) {
      console.warn("SELLERS_URL fetch failed, falling back to local:", e.message);
    }
  }
  try {
    return JSON.parse(readFileSync(SELLERS_PATH, "utf-8"));
  } catch {
    console.warn("sellers.json not found, using empty map");
    return {};
  }
}

// ---------------------------------------------------------------------------
// Stripe webhook (MUST be before express.json())
// ---------------------------------------------------------------------------

app.post("/webhook", express.raw({ type: "application/json" }), async (req, res) => {
  const sig = req.headers["stripe-signature"];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error("Webhook signature verification failed:", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === "payment_intent.succeeded") {
    const pi = event.data.object;
    const meta = pi.metadata;
    const orderId = meta.orderId || crypto.randomUUID();

    try {
      const orderItems = JSON.parse(meta.orderItems || "[]");
      const sellerTotals = JSON.parse(meta.sellerTotals || "{}");
      const sellers = await fetchSellers();

      for (const [sellerId, amountCents] of Object.entries(sellerTotals)) {
        const seller = sellers[sellerId];
        if (!seller?.stripeAccountId) continue;
        const platformFee = Math.round(amountCents * 0.10);
        const transferAmount = amountCents - platformFee;
        if (transferAmount <= 0) continue;
        await stripe.transfers.create({
          amount: transferAmount,
          currency: "usd",
          destination: seller.stripeAccountId,
          transfer_group: orderId,
        });
      }

      if (meta.buyerEmail) {
        await resend.emails.send({
          from: EMAIL_FROM,
          to: meta.buyerEmail,
          subject: `TenBelow Order Confirmed — ${orderId}`,
          html: `<h2>Thanks for your order!</h2><p>Order <strong>${orderId}</strong></p><p>We'll email tracking when items ship.</p>`,
        });
      }
    } catch (err) {
      console.error("Webhook processing error:", err);
    }
  }

  res.json({ received: true });
});

// ---------------------------------------------------------------------------
// JSON body parser (after webhook)
// ---------------------------------------------------------------------------

app.use(express.json());
app.use(cors());

// ---------------------------------------------------------------------------
// Create Payment Intent
// ---------------------------------------------------------------------------

app.post("/create-payment-intent", async (req, res) => {
  try {
    const { email, shipping, items } = req.body;
    if (!email || !items?.length) return res.status(400).json({ error: "Missing email or items" });

    const catalog = await fetchCatalog();
    const config = await fetchConfig();
    const productMap = Object.fromEntries(catalog.products.map((p) => [p.id, p]));

    let subtotalCents = 0;
    const sellerTotals = {};
    const orderItems = [];

    for (const item of items) {
      const product = productMap[item.productId];
      if (!product) continue;
      const lineCents = product.priceCents * (item.quantity || 1);
      subtotalCents += lineCents;
      sellerTotals[product.sellerId] = (sellerTotals[product.sellerId] || 0) + lineCents;
      orderItems.push({ id: product.id, name: product.name, sellerId: product.sellerId, priceCents: product.priceCents, quantity: item.quantity || 1 });
    }

    const minimumOrderCents = config.minimumOrderCents || 2000;
    if (subtotalCents < minimumOrderCents) {
      return res.status(400).json({ error: `Minimum order is $${(minimumOrderCents / 100).toFixed(2)}` });
    }

    const totalCents = subtotalCents;
    const orderId = crypto.randomUUID();

    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalCents,
      currency: "usd",
      metadata: {
        orderId,
        buyerEmail: email,
        orderItems: JSON.stringify(orderItems),
        sellerTotals: JSON.stringify(sellerTotals),
      },
    });

    res.json({ clientSecret: paymentIntent.client_secret, orderId, totalCents });
  } catch (err) {
    console.error("create-payment-intent error:", err);
    res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Seller Onboarding (Stripe Connect Express)
// ---------------------------------------------------------------------------

const SELLERS_PATH = new URL("./sellers.json", import.meta.url);

function loadSellersFile() {
  try { return JSON.parse(readFileSync(SELLERS_PATH, "utf-8")); } catch { return {}; }
}

function saveSellersFile(sellers) {
  writeFileSync(SELLERS_PATH, JSON.stringify(sellers, null, 2));
}

app.post("/create-seller-account", async (req, res) => {
  try {
    const { sellerId, email, businessName } = req.body;
    if (!sellerId || !email) return res.status(400).json({ error: "sellerId and email required" });

    const sellers = loadSellersFile();
    if (sellers[sellerId]) return res.status(409).json({ error: "Seller already exists" });

    const account = await stripe.accounts.create({
      type: "express",
      email,
      business_profile: { name: businessName || sellerId },
      capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
    });

    sellers[sellerId] = { stripeAccountId: account.id, email, businessName: businessName || "" };
    saveSellersFile(sellers);

    const link = await stripe.accountLinks.create({
      account: account.id,
      refresh_url: `${BACKEND_URL}/seller-onboarding-refresh?sellerId=${sellerId}`,
      return_url: `${BACKEND_URL}/seller-onboarding-complete?sellerId=${sellerId}`,
      type: "account_onboarding",
    });

    res.json({ sellerId, stripeAccountId: account.id, onboardingUrl: link.url });
  } catch (err) {
    console.error("create-seller-account error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-link/:sellerId", async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const seller = sellers[req.params.sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const link = await stripe.accountLinks.create({
      account: seller.stripeAccountId,
      refresh_url: `${BACKEND_URL}/seller-onboarding-refresh?sellerId=${req.params.sellerId}`,
      return_url: `${BACKEND_URL}/seller-onboarding-complete?sellerId=${req.params.sellerId}`,
      type: "account_onboarding",
    });
    res.json({ sellerId: req.params.sellerId, onboardingUrl: link.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-status/:sellerId", async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const seller = sellers[req.params.sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const account = await stripe.accounts.retrieve(seller.stripeAccountId);
    res.json({
      sellerId: req.params.sellerId,
      stripeAccountId: seller.stripeAccountId,
      chargesEnabled: account.charges_enabled,
      payoutsEnabled: account.payouts_enabled,
      detailsSubmitted: account.details_submitted,
      onboardingComplete: account.charges_enabled && account.payouts_enabled && account.details_submitted,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-dashboard-link/:sellerId", async (req, res) => {
  try {
    const sellers = loadSellersFile();
    const seller = sellers[req.params.sellerId];
    if (!seller) return res.status(404).json({ error: "Seller not found" });
    const link = await stripe.accounts.createLoginLink(seller.stripeAccountId);
    res.json({ sellerId: req.params.sellerId, dashboardUrl: link.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/seller-onboarding-complete", (req, res) => {
  res.send("<html><body><h1>Onboarding complete!</h1><p>You can close this window and return to the app.</p></body></html>");
});

app.get("/seller-onboarding-refresh", (req, res) => {
  res.send("<html><body><h1>Session expired</h1><p>Please go back to the app and try again.</p></body></html>");
});

app.get("/sellers", (_, res) => res.json(loadSellersFile()));

// ---------------------------------------------------------------------------
// Weekly Drop System
// ---------------------------------------------------------------------------

const DROPS_PATH = new URL("./drops.json", import.meta.url);
const DROP_MIN_PRICE_CENTS = 1001;
const DROP_MAX_SLOTS_PER_SELLER = 4;

function loadDropsFile() {
  try { return JSON.parse(readFileSync(DROPS_PATH, "utf-8")); } catch { return {}; }
}

function saveDropsFile(drops) {
  writeFileSync(DROPS_PATH, JSON.stringify(drops, null, 2));
}

function getCurrentDropWindow() {
  const now = new Date();
  const utcDay = now.getUTCDay();

  let fridayOffset;
  if (utcDay === 5) fridayOffset = 0;
  else if (utcDay === 6) fridayOffset = -1;
  else if (utcDay === 0) fridayOffset = -2;
  else fridayOffset = -(utcDay + 2);

  const friday = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + fridayOffset,
    0, 0, 0, 0
  ));

  const sunday = new Date(Date.UTC(
    friday.getUTCFullYear(), friday.getUTCMonth(), friday.getUTCDate() + 2,
    23, 59, 59, 999
  ));

  const isActive = utcDay === 5 || utcDay === 6 || utcDay === 0;

  const isoYear = friday.getUTCFullYear();
  const dayOfYear = Math.floor((friday - new Date(Date.UTC(isoYear, 0, 1))) / 86400000);
  const weekNum = Math.ceil((dayOfYear + 1) / 7);
  const weekId = `${isoYear}-W${String(weekNum).padStart(2, "0")}`;

  let nextDropAt = null;
  if (!isActive) {
    const daysUntilFriday = (5 - utcDay + 7) % 7 || 7;
    nextDropAt = new Date(Date.UTC(
      now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + daysUntilFriday,
      0, 0, 0, 0
    )).toISOString();
  }

  return {
    weekId,
    startsAt: friday.toISOString(),
    endsAt: sunday.toISOString(),
    isActive,
    nextDropAt,
  };
}

app.post("/drop/submit", async (req, res) => {
  try {
    const { sellerId, name, priceCents, category, material, durabilityNote, careWarnings, shipsInMinDays, shipsInMaxDays } = req.body;

    if (!sellerId || !name || !priceCents) {
      return res.status(400).json({ error: "sellerId, name, and priceCents are required" });
    }

    const sellers = loadSellersFile();
    if (!sellers[sellerId]) {
      return res.status(404).json({ error: "Seller not found. Create an account first." });
    }

    if (priceCents < DROP_MIN_PRICE_CENTS) {
      return res.status(400).json({ error: `Drop products must be over $10 (got $${(priceCents / 100).toFixed(2)})` });
    }

    const window = getCurrentDropWindow();
    if (!window.isActive) {
      return res.status(400).json({
        error: "Drop submissions are only open Friday through Sunday (UTC)",
        nextDropAt: window.nextDropAt,
      });
    }

    const drops = loadDropsFile();
    if (!drops[window.weekId]) {
      drops[window.weekId] = { startsAt: window.startsAt, endsAt: window.endsAt, products: [] };
    }

    const weekData = drops[window.weekId];
    const sellerProducts = weekData.products.filter((p) => p.sellerId === sellerId);
    if (sellerProducts.length >= DROP_MAX_SLOTS_PER_SELLER) {
      return res.status(400).json({ error: `You've reached the maximum of ${DROP_MAX_SLOTS_PER_SELLER} drop products this week` });
    }

    const product = {
      id: `drop-${crypto.randomUUID()}`,
      sellerId,
      name,
      priceCents,
      category: category || "home",
      imageURLs: [],
      material: material || "PLA+",
      durabilityNote: durabilityNote || "",
      careWarnings: careWarnings || [],
      shipsInMinDays: shipsInMinDays || 3,
      shipsInMaxDays: shipsInMaxDays || 7,
      submittedAt: new Date().toISOString(),
    };

    weekData.products.push(product);
    saveDropsFile(drops);

    res.json(product);
  } catch (err) {
    console.error("drop/submit error:", err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/drop/current", (req, res) => {
  const window = getCurrentDropWindow();
  const drops = loadDropsFile();
  const weekData = drops[window.weekId];

  if (!window.isActive || !weekData || !weekData.products.length) {
    return res.json({
      active: false,
      weekId: window.weekId,
      nextDropAt: window.nextDropAt,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      products: [],
    });
  }

  res.json({
    active: true,
    weekId: window.weekId,
    startsAt: weekData.startsAt,
    endsAt: weekData.endsAt,
    products: weekData.products,
  });
});

app.get("/drop/my-submissions/:sellerId", (req, res) => {
  const { sellerId } = req.params;
  const window = getCurrentDropWindow();
  const drops = loadDropsFile();
  const weekData = drops[window.weekId];

  const myProducts = weekData ? weekData.products.filter((p) => p.sellerId === sellerId) : [];

  res.json({
    sellerId,
    weekId: window.weekId,
    isActive: window.isActive,
    nextDropAt: window.nextDropAt,
    slotsUsed: myProducts.length,
    slotsMax: DROP_MAX_SLOTS_PER_SELLER,
    products: myProducts,
  });
});

app.delete("/drop/submission/:productId", (req, res) => {
  const { productId } = req.params;
  const window = getCurrentDropWindow();

  if (!window.isActive) {
    return res.status(400).json({ error: "Cannot delete submissions outside the drop window" });
  }

  const drops = loadDropsFile();
  const weekData = drops[window.weekId];
  if (!weekData) return res.status(404).json({ error: "No drop data for this week" });

  const idx = weekData.products.findIndex((p) => p.id === productId);
  if (idx === -1) return res.status(404).json({ error: "Product not found in this week's drop" });

  const removed = weekData.products.splice(idx, 1)[0];
  saveDropsFile(drops);

  res.json({ deleted: true, product: removed });
});

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

app.get("/health", (_, res) => res.json({ ok: true }));

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`TenBelow backend → http://localhost:${PORT}`));
