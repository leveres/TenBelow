import { creatorProfileFromSellerRecord, creatorProfileComparable } from "../../domain/phase1/creatorProfile.js";
import { getPrisma } from "../prisma/client.js";
import { loadSellersFromJson } from "./jsonStore.js";
import { compareRecordSets } from "./compareUtils.js";

function toDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

const PROFILE_FIELDS = [
  "displayName",
  "handle",
  "bio",
  "avatarURL",
  "bannerURL",
  "websiteURL",
  "customOrderInfoURL",
  "location",
  "materials",
  "processingTime",
  "designLicense",
  "isVerified",
  "shipsInMinDays",
  "shipsInMaxDays",
  "acceptsCustomOrders",
];

export function readCreatorProfilesFromJson(sellers = loadSellersFromJson()) {
  return Object.fromEntries(
    Object.entries(sellers).map(([sellerId, seller]) => [
      sellerId,
      creatorProfileFromSellerRecord(sellerId, seller),
    ])
  );
}

export async function syncCreatorProfilesToPrisma(sellers = loadSellersFromJson()) {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  let synced = 0;
  for (const [sellerId, seller] of Object.entries(sellers)) {
    const profile = seller.profile || {};
    await prisma.sellerProfile.upsert({
      where: { sellerId },
      create: {
        sellerId,
        displayName: profile.displayName || seller.businessName || sellerId,
        handle: profile.handle || `@${sellerId}`,
        bio: profile.bio || "",
        avatarUrl: profile.avatarURL || null,
        bannerUrl: profile.bannerURL || null,
        websiteUrl: profile.websiteURL || null,
        customOrderInfoUrl: profile.customOrderInfoURL || null,
        location: profile.location || "TenBelow",
        materials: Array.isArray(profile.materials) ? profile.materials : [],
        processingTime: profile.processingTime || "Printed fresh to order",
        designLicense: profile.designLicense || "Original Designs",
        productCount: profile.productCount || 0,
        orderCount: profile.orderCount || 0,
        totalReviewCount: profile.totalReviewCount || 0,
        positiveReviewCount: profile.positiveReviewCount || 0,
        rating: profile.rating || 0,
        likeCount: profile.likeCount || 0,
        pageViewCount: profile.pageViewCount || 0,
        isVerified: profile.isVerified === true,
        joinedAt: toDate(profile.joinedAt) || new Date(),
        shipsInMinDays: profile.shipsInMinDays || 2,
        shipsInMaxDays: profile.shipsInMaxDays || 5,
        acceptsCustomOrders: profile.acceptsCustomOrders === true,
      },
      update: {
        displayName: profile.displayName || seller.businessName || sellerId,
        handle: profile.handle || `@${sellerId}`,
        bio: profile.bio || "",
        avatarUrl: profile.avatarURL || null,
        bannerUrl: profile.bannerURL || null,
        websiteUrl: profile.websiteURL || null,
        customOrderInfoUrl: profile.customOrderInfoURL || null,
        location: profile.location || "TenBelow",
        materials: Array.isArray(profile.materials) ? profile.materials : [],
        processingTime: profile.processingTime || "Printed fresh to order",
        designLicense: profile.designLicense || "Original Designs",
        productCount: profile.productCount || 0,
        orderCount: profile.orderCount || 0,
        totalReviewCount: profile.totalReviewCount || 0,
        positiveReviewCount: profile.positiveReviewCount || 0,
        rating: profile.rating || 0,
        likeCount: profile.likeCount || 0,
        pageViewCount: profile.pageViewCount || 0,
        isVerified: profile.isVerified === true,
        joinedAt: toDate(profile.joinedAt) || new Date(),
        shipsInMinDays: profile.shipsInMinDays || 2,
        shipsInMaxDays: profile.shipsInMaxDays || 5,
        acceptsCustomOrders: profile.acceptsCustomOrders === true,
      },
    });
    synced += 1;
  }
  return { synced };
}

export async function readCreatorProfilesFromPrisma() {
  const prisma = getPrisma();
  if (!prisma) return {};
  const rows = await prisma.sellerProfile.findMany();
  return Object.fromEntries(
    rows.map((row) => [
      row.sellerId,
      creatorProfileComparable(
        {
          displayName: row.displayName,
          handle: row.handle,
          bio: row.bio,
          avatarURL: row.avatarUrl,
          bannerURL: row.bannerUrl,
          websiteURL: row.websiteUrl,
          customOrderInfoURL: row.customOrderInfoUrl,
          location: row.location,
          materials: row.materials,
          processingTime: row.processingTime,
          designLicense: row.designLicense,
          isVerified: row.isVerified,
          joinedAt: row.joinedAt?.toISOString?.(),
          shipsInMinDays: row.shipsInMinDays,
          shipsInMaxDays: row.shipsInMaxDays,
          acceptsCustomOrders: row.acceptsCustomOrders,
        },
        row.sellerId
      ),
    ])
  );
}

export async function compareCreatorProfiles() {
  const jsonRecordsById = readCreatorProfilesFromJson();
  const prismaRecordsById = await readCreatorProfilesFromPrisma();
  const sellerIds = new Set(Object.keys(loadSellersFromJson()));
  const relationshipMismatches = [];
  for (const sellerId of Object.keys(prismaRecordsById)) {
    if (!sellerIds.has(sellerId)) {
      relationshipMismatches.push(`SellerProfile ${sellerId} has no parent Seller in JSON`);
    }
  }
  return compareRecordSets({
    repository: "creatorProfiles",
    jsonRecordsById,
    prismaRecordsById,
    comparableFields: PROFILE_FIELDS,
    relationshipMismatches,
  });
}
