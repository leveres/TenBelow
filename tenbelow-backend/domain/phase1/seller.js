import { DEFAULT_SELLER_SUBSCRIPTION_PRODUCT_ID } from "./constants.js";
import { normalizeAccountModeration } from "./accountModeration.js";

function asFiniteNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function asISODateOrNull(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return null;
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

export function normalizeMembership(membership = {}) {
  return {
    productId: membership.productId || DEFAULT_SELLER_SUBSCRIPTION_PRODUCT_ID,
    hasActiveSubscription: membership.hasActiveSubscription === true,
    expiresAt: asISODateOrNull(membership.expiresAt),
    lastSyncedAt: asISODateOrNull(membership.lastSyncedAt),
    source: membership.source === "stripe" ? "stripe" : "app_store",
    originalTransactionId: membership.originalTransactionId || null,
    transactionId: membership.transactionId || null,
    stripeSubscriptionId: membership.stripeSubscriptionId || null,
    stripeCustomerId: membership.stripeCustomerId || null,
  };
}

export function normalizeFoundingCreatorFields(record = {}) {
  const creatorBadge = String(record.creatorBadge || "Founding Creator").trim() || "Founding Creator";
  return {
    isFoundingCreator: record.isFoundingCreator === true,
    foundingCreatorAccessStartsAt: asISODateOrNull(record.foundingCreatorAccessStartsAt),
    foundingCreatorAccessEndsAt: asISODateOrNull(record.foundingCreatorAccessEndsAt),
    creatorBadge,
  };
}

export function foundingCreatorStatus(record = {}, now = new Date()) {
  const founding = normalizeFoundingCreatorFields(record);
  const nowTs = now.getTime();
  const startsAtTs = founding.foundingCreatorAccessStartsAt
    ? new Date(founding.foundingCreatorAccessStartsAt).getTime()
    : null;
  const endsAtTs = founding.foundingCreatorAccessEndsAt
    ? new Date(founding.foundingCreatorAccessEndsAt).getTime()
    : null;
  const hasStarted = startsAtTs == null || nowTs >= startsAtTs;
  const hasNotEnded = endsAtTs != null && nowTs <= endsAtTs;
  const hasComplimentaryAccess = founding.isFoundingCreator && hasStarted && hasNotEnded;
  return { ...founding, hasComplimentaryAccess };
}

export function effectiveSellerMembershipStatus(record = {}, now = new Date()) {
  const membership = normalizeMembership(record.membership);
  const founding = foundingCreatorStatus(record, now);
  const membershipStatus = founding.hasComplimentaryAccess
    ? "complimentary"
    : membership.hasActiveSubscription
      ? "active"
      : "expired";
  return { membership, founding, membershipStatus };
}

export function normalizeSellerPublicProfile(profile = {}, sellerId = "", businessName = "") {
  const trimmedSellerId = String(sellerId || "").trim();
  const normalizedHandleBase = String(profile.handle || trimmedSellerId).trim().replace(/^@+/, "");
  const customInfoRaw =
    profile.customOrderInfoURL != null && profile.customOrderInfoURL !== ""
      ? String(profile.customOrderInfoURL).trim()
      : "";

  return {
    displayName: String(profile.displayName || businessName || trimmedSellerId || "TenBelow Seller").trim(),
    handle: `@${normalizedHandleBase || "tenbelowseller"}`,
    bio: String(profile.bio || "Independent TenBelow seller creating 3D-printed products.").trim(),
    avatarURL: profile.avatarURL || null,
    bannerURL: profile.bannerURL || null,
    websiteURL: profile.websiteURL || null,
    location: String(profile.location || "TenBelow").trim(),
    materials: Array.isArray(profile.materials) ? profile.materials.filter(Boolean) : [],
    processingTime: String(profile.processingTime || "Printed fresh to order").trim(),
    productCount: Math.max(0, asFiniteNumber(profile.productCount, 0)),
    orderCount: Math.max(0, asFiniteNumber(profile.orderCount, 0)),
    totalReviewCount: Math.max(0, asFiniteNumber(profile.totalReviewCount, 0)),
    positiveReviewCount: Math.max(0, asFiniteNumber(profile.positiveReviewCount, 0)),
    rating: Math.max(0, asFiniteNumber(profile.rating, 0)),
    likeCount: Math.max(0, asFiniteNumber(profile.likeCount, 0)),
    pageViewCount: Math.max(0, asFiniteNumber(profile.pageViewCount, 0)),
    designLicense: String(profile.designLicense || "Original Designs").trim(),
    isVerified: profile.isVerified === true,
    joinedAt: profile.joinedAt || new Date().toISOString(),
    shipsInMinDays: Math.max(1, asFiniteNumber(profile.shipsInMinDays, 2)),
    shipsInMaxDays: Math.max(1, asFiniteNumber(profile.shipsInMaxDays, 5)),
    acceptsCustomOrders: profile.acceptsCustomOrders === true,
    customOrderInfoURL: customInfoRaw || null,
  };
}

export function normalizeSellerRecord(record = {}, sellerId = "") {
  const founding = normalizeFoundingCreatorFields(record);
  const effectiveMembership = effectiveSellerMembershipStatus(record);
  return {
    stripeAccountId: record.stripeAccountId || "",
    email: record.email || "",
    passwordHash: String(record.passwordHash || "").trim(),
    businessName: record.businessName || "",
    legalName: String(record.legalName || "").trim(),
    shippingOrigin: {
      country: String(record.shippingOrigin?.country || "").trim(),
      state: String(record.shippingOrigin?.state || "").trim(),
    },
    sellerAgreement: {
      accepted: record.sellerAgreement?.accepted === true,
      acceptedAt: record.sellerAgreement?.acceptedAt || null,
      version: record.sellerAgreement?.version || record.sellerAgreement?.documentId || "seller-agreement-2026-04-24",
      agreementType: record.sellerAgreement?.agreementType || "seller_agreement",
      documentId: record.sellerAgreement?.documentId || record.sellerAgreement?.version || "seller-agreement-2026-04-24",
      documentHash: record.sellerAgreement?.documentHash || null,
      versionLabel: record.sellerAgreement?.versionLabel || null,
      legalNameAtAcceptance: record.sellerAgreement?.legalNameAtAcceptance || null,
      emailAtAcceptance: record.sellerAgreement?.emailAtAcceptance || null,
      acceptanceId: record.sellerAgreement?.acceptanceId || null,
    },
    welcomeEmail: {
      status: record.welcomeEmail?.status || (record.welcomeEmail?.sentAt ? "sent" : "pending"),
      sentAt: record.welcomeEmail?.sentAt || null,
      messageId: record.welcomeEmail?.messageId || null,
      lastError: record.welcomeEmail?.lastError || null,
      attemptCount: Math.max(0, Number(record.welcomeEmail?.attemptCount) || 0),
    },
    sellerPoliciesAcknowledged: record.sellerPoliciesAcknowledged === true,
    membership: effectiveMembership.membership,
    isFoundingCreator: founding.isFoundingCreator,
    foundingCreatorAccessStartsAt: founding.foundingCreatorAccessStartsAt,
    foundingCreatorAccessEndsAt: founding.foundingCreatorAccessEndsAt,
    creatorBadge: founding.creatorBadge,
    membershipStatus: effectiveMembership.membershipStatus,
    profile: normalizeSellerPublicProfile(record.profile, sellerId, record.businessName),
    accountModeration: normalizeAccountModeration(record.accountModeration),
  };
}

export function normalizeSellerMap(raw = {}) {
  return Object.fromEntries(
    Object.entries(raw || {}).map(([sellerId, record]) => [sellerId, normalizeSellerRecord(record, sellerId)])
  );
}

export function sellerAccountComparable(record = {}, sellerId = "") {
  return {
    id: sellerId,
    email: record.email || "",
    passwordHash: record.passwordHash || "",
    businessName: record.businessName || "",
    legalName: record.legalName || "",
    shippingOriginCountry: record.shippingOrigin?.country || "",
    shippingOriginState: record.shippingOrigin?.state || "",
    sellerAgreementAccepted: record.sellerAgreement?.accepted === true,
    sellerPoliciesAcknowledged: record.sellerPoliciesAcknowledged === true,
    stripeAccountId: record.stripeAccountId || "",
  };
}
