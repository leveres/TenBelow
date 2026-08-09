import { buyerComparable } from "../../domain/phase1/buyer.js";
import { sellerAccountComparable } from "../../domain/phase1/seller.js";
import { getPrisma } from "../prisma/client.js";
import { loadBuyersFromJson, loadSellersFromJson } from "./jsonStore.js";
import { compareRecordSets } from "./compareUtils.js";
import { upsertSellerAgreementAcceptanceToPrisma } from "./legalAgreementRepository.js";

function toDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function readBuyersFromJson() {
  return loadBuyersFromJson();
}

export function readSellersFromJson() {
  return loadSellersFromJson();
}

export async function syncBuyersToPrisma(buyers = loadBuyersFromJson()) {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  let synced = 0;
  for (const [email, buyer] of Object.entries(buyers)) {
    await prisma.buyer.upsert({
      where: { email },
      create: {
        email,
        fullName: buyer.fullName,
        passwordHash: buyer.passwordHash,
        emailVerified: buyer.emailVerified === true,
        emailVerifiedAt: toDate(buyer.emailVerifiedAt),
        createdAt: toDate(buyer.createdAt) || new Date(),
        updatedAt: toDate(buyer.updatedAt) || new Date(),
      },
      update: {
        fullName: buyer.fullName,
        passwordHash: buyer.passwordHash,
        emailVerified: buyer.emailVerified === true,
        emailVerifiedAt: toDate(buyer.emailVerifiedAt),
        updatedAt: toDate(buyer.updatedAt) || new Date(),
      },
    });
    synced += 1;
  }
  return { synced };
}

export async function syncSellersToPrisma(sellers = loadSellersFromJson()) {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  let synced = 0;
  for (const [sellerId, seller] of Object.entries(sellers)) {
    await prisma.seller.upsert({
      where: { id: sellerId },
      create: {
        id: sellerId,
        email: seller.email || "",
        passwordHash: seller.passwordHash || "",
        stripeAccountId: seller.stripeAccountId || "",
        businessName: seller.businessName || "",
        legalName: seller.legalName || "",
        shippingOriginCountry: seller.shippingOrigin?.country || "",
        shippingOriginState: seller.shippingOrigin?.state || "",
        sellerPoliciesAcknowledged: seller.sellerPoliciesAcknowledged === true,
      },
      update: {
        email: seller.email || "",
        passwordHash: seller.passwordHash || "",
        stripeAccountId: seller.stripeAccountId || "",
        businessName: seller.businessName || "",
        legalName: seller.legalName || "",
        shippingOriginCountry: seller.shippingOrigin?.country || "",
        shippingOriginState: seller.shippingOrigin?.state || "",
        sellerPoliciesAcknowledged: seller.sellerPoliciesAcknowledged === true,
      },
    });

    await prisma.sellerAgreement.upsert({
      where: { sellerId },
      create: {
        sellerId,
        accepted: seller.sellerAgreement?.accepted === true,
        acceptedAt: toDate(seller.sellerAgreement?.acceptedAt),
        version: seller.sellerAgreement?.version || seller.sellerAgreement?.documentId || "seller-agreement-2026-04-24",
      },
      update: {
        accepted: seller.sellerAgreement?.accepted === true,
        acceptedAt: toDate(seller.sellerAgreement?.acceptedAt),
        version: seller.sellerAgreement?.version || seller.sellerAgreement?.documentId || "seller-agreement-2026-04-24",
      },
    });

    await upsertSellerAgreementAcceptanceToPrisma(sellerId, seller);

    const membership = seller.membership || {};
    await prisma.sellerMembership.upsert({
      where: { sellerId },
      create: {
        sellerId,
        productId: membership.productId,
        hasActiveSubscription: membership.hasActiveSubscription === true,
        expiresAt: toDate(membership.expiresAt),
        lastSyncedAt: toDate(membership.lastSyncedAt),
        source: membership.source === "stripe" ? "stripe" : "app_store",
        originalTransactionId: membership.originalTransactionId,
        transactionId: membership.transactionId,
        stripeSubscriptionId: membership.stripeSubscriptionId,
        stripeCustomerId: membership.stripeCustomerId,
        membershipStatus: seller.membershipStatus || "expired",
      },
      update: {
        productId: membership.productId,
        hasActiveSubscription: membership.hasActiveSubscription === true,
        expiresAt: toDate(membership.expiresAt),
        lastSyncedAt: toDate(membership.lastSyncedAt),
        source: membership.source === "stripe" ? "stripe" : "app_store",
        originalTransactionId: membership.originalTransactionId,
        transactionId: membership.transactionId,
        stripeSubscriptionId: membership.stripeSubscriptionId,
        stripeCustomerId: membership.stripeCustomerId,
        membershipStatus: seller.membershipStatus || "expired",
      },
    });

    await prisma.foundingCreatorAccess.upsert({
      where: { sellerId },
      create: {
        sellerId,
        isActive: seller.isFoundingCreator === true,
        startsAt: toDate(seller.foundingCreatorAccessStartsAt),
        endsAt: toDate(seller.foundingCreatorAccessEndsAt),
        creatorBadge: seller.creatorBadge || "Founding Creator",
      },
      update: {
        isActive: seller.isFoundingCreator === true,
        startsAt: toDate(seller.foundingCreatorAccessStartsAt),
        endsAt: toDate(seller.foundingCreatorAccessEndsAt),
        creatorBadge: seller.creatorBadge || "Founding Creator",
      },
    });

    synced += 1;
  }
  return { synced };
}

export async function syncUsersToPrisma() {
  const buyers = await syncBuyersToPrisma();
  const sellers = await syncSellersToPrisma();
  return { buyers, sellers };
}

export async function readBuyersFromPrisma() {
  const prisma = getPrisma();
  if (!prisma) return {};
  const rows = await prisma.buyer.findMany();
  return Object.fromEntries(
    rows.map((row) => [
      row.email,
      buyerComparable({
        email: row.email,
        fullName: row.fullName,
        passwordHash: row.passwordHash,
        emailVerified: row.emailVerified,
        emailVerifiedAt: row.emailVerifiedAt?.toISOString?.() || null,
      }),
    ])
  );
}

export async function readSellersFromPrisma() {
  const prisma = getPrisma();
  if (!prisma) return {};
  const rows = await prisma.seller.findMany();
  return Object.fromEntries(
    rows.map((row) => [
      row.id,
      sellerAccountComparable(
        {
          email: row.email,
          passwordHash: row.passwordHash,
          businessName: row.businessName,
          legalName: row.legalName,
          shippingOrigin: { country: row.shippingOriginCountry, state: row.shippingOriginState },
          sellerAgreement: { accepted: true },
          sellerPoliciesAcknowledged: row.sellerPoliciesAcknowledged,
          stripeAccountId: row.stripeAccountId,
        },
        row.id
      ),
    ])
  );
}

export async function compareBuyers() {
  const jsonRecordsById = await readBuyersFromJson();
  const prismaRecordsById = await readBuyersFromPrisma();
  return compareRecordSets({
    repository: "users.buyers",
    jsonRecordsById: Object.fromEntries(
      Object.entries(jsonRecordsById).map(([email, buyer]) => [email, buyerComparable(buyer)])
    ),
    prismaRecordsById,
    comparableFields: ["email", "fullName", "passwordHash", "emailVerified", "emailVerifiedAt"],
  });
}

export async function compareSellers() {
  const jsonSellers = readSellersFromJson();
  const jsonRecordsById = Object.fromEntries(
    Object.entries(jsonSellers).map(([sellerId, seller]) => [
      sellerId,
      sellerAccountComparable(seller, sellerId),
    ])
  );
  const prismaRecordsById = await readSellersFromPrisma();
  return compareRecordSets({
    repository: "users.sellers",
    jsonRecordsById,
    prismaRecordsById,
    comparableFields: [
      "email",
      "passwordHash",
      "businessName",
      "legalName",
      "shippingOriginCountry",
      "shippingOriginState",
      "sellerPoliciesAcknowledged",
      "stripeAccountId",
    ],
  });
}

export async function compareUsers() {
  return {
    buyers: await compareBuyers(),
    sellers: await compareSellers(),
  };
}
