#!/usr/bin/env node
/**
 * Seed fake seller fulfillment orders into local backend data.
 *
 * Usage:
 *   CONFIRM_SEED=1 SELLER_ID=my_shop node scripts/seed-seller-test-orders.mjs
 *
 * Optional:
 *   SELLER_NAME="My Shop"
 *   BUYER_EMAIL=buyer@example.com
 *   REPLACE_EXISTING=1          # remove prior seeded orders for this seller first
 *   GRANT_FOUNDING_CREATOR=1    # also grant complimentary Weekly Drop access in sellers.json
 */
import "dotenv/config";
import {
  grantFoundingCreatorMembership,
  seedSellerTestOrders,
} from "./seller-test-order-fixtures.mjs";

const sellerId = String(process.env.SELLER_ID || "").trim();
const sellerName = String(process.env.SELLER_NAME || "").trim();
const buyerEmail = String(process.env.BUYER_EMAIL || "seller-test-buyer@example.com").trim();
const confirm = String(process.env.CONFIRM_SEED || "").trim() === "1";
const replaceExisting = String(process.env.REPLACE_EXISTING || "").trim() === "1";
const grantFoundingCreator = String(process.env.GRANT_FOUNDING_CREATOR || "").trim() === "1";

if (!sellerId) {
  console.error("SELLER_ID is required");
  process.exit(1);
}

if (!confirm) {
  console.error("Refusing to write without CONFIRM_SEED=1");
  process.exit(1);
}

try {
  const result = seedSellerTestOrders({
    sellerId,
    sellerName: sellerName || sellerId,
    buyerEmail,
    replaceExistingForSeller: replaceExisting,
  });

  console.log(`Seeded ${result.inserted} orders for seller ${sellerId}`);
  console.log(`Data directory: ${result.dataDirectory}`);
  console.log(`Order IDs: ${result.orderIds.join(", ")}`);

  if (grantFoundingCreator) {
    const membership = grantFoundingCreatorMembership({ sellerId });
    console.log(
      `Granted founding creator access until ${membership.foundingCreatorAccessEndsAt}`
    );
  }
} catch (err) {
  console.error("seed-seller-test-orders failed:", err.message || err);
  process.exit(1);
}
