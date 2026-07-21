import { normalizeSellerPublicProfile } from "./seller.js";

/** Fields persisted in SellerProfile table (excludes computed aggregates used in API). */
export function creatorProfileComparable(profile = {}, sellerId = "", businessName = "") {
  const normalized = normalizeSellerPublicProfile(profile, sellerId, businessName);
  return {
    displayName: normalized.displayName,
    handle: normalized.handle,
    bio: normalized.bio,
    avatarURL: normalized.avatarURL,
    bannerURL: normalized.bannerURL,
    websiteURL: normalized.websiteURL,
    customOrderInfoURL: normalized.customOrderInfoURL,
    location: normalized.location,
    materials: normalized.materials,
    processingTime: normalized.processingTime,
    designLicense: normalized.designLicense,
    isVerified: normalized.isVerified,
    joinedAt: normalized.joinedAt,
    shipsInMinDays: normalized.shipsInMinDays,
    shipsInMaxDays: normalized.shipsInMaxDays,
    acceptsCustomOrders: normalized.acceptsCustomOrders,
  };
}

export function creatorProfileFromSellerRecord(sellerId, sellerRecord = {}) {
  return creatorProfileComparable(sellerRecord.profile, sellerId, sellerRecord.businessName);
}
