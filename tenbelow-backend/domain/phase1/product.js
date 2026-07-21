import crypto from "crypto";
import { DEFAULT_CATEGORY_SLUG } from "./constants.js";

function asFiniteNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalizeRightsReferenceFlags(value) {
  return Array.isArray(value)
    ? value.map((flag) => String(flag || "").trim()).filter(Boolean)
    : [];
}

export function normalizeCatalogProduct(product = {}) {
  const explicitApprovalStatus = String(product.approvalStatus || "").trim().toLowerCase();
  const resolvedApprovalStatus = explicitApprovalStatus || (
    product.isApproved === true && product.isActive !== false
      ? "approved"
      : product.reviewedAt || product.reviewNotes
        ? "rejected"
        : "submitted"
  );
  const isArchived = resolvedApprovalStatus === "archived";

  return {
    id: String(product.id || crypto.randomUUID()),
    sellerId: String(product.sellerId || "").trim(),
    name: String(product.name || "").trim(),
    priceCents: Math.max(0, asFiniteNumber(product.priceCents, 0)),
    previousPriceCents:
      product.previousPriceCents == null ? null : Math.max(0, asFiniteNumber(product.previousPriceCents, 0)),
    category: String(product.category || DEFAULT_CATEGORY_SLUG).trim().toLowerCase(),
    imageURLs: Array.isArray(product.imageURLs) ? product.imageURLs.filter(Boolean) : [],
    demoVideoURL: product.demoVideoURL || null,
    productionPreviewURL: product.productionPreviewURL || null,
    dropHeadline: String(product.dropHeadline || "").trim(),
    dropStory: String(product.dropStory || "").trim(),
    dropBestUseCase: String(product.dropBestUseCase || "").trim(),
    material: String(product.material || "PLA+").trim(),
    durabilityNote: String(product.durabilityNote || "Built for everyday use.").trim(),
    careWarnings: Array.isArray(product.careWarnings) ? product.careWarnings.filter(Boolean) : [],
    shipsInMinDays: Math.max(1, asFiniteNumber(product.shipsInMinDays, 2)),
    shipsInMaxDays: Math.max(1, asFiniteNumber(product.shipsInMaxDays, 4)),
    isDrop: product.isDrop === true,
    isActive: isArchived ? false : product.isActive !== false,
    isApproved: isArchived ? false : product.isApproved !== false,
    approvalStatus: resolvedApprovalStatus,
    submittedAt: product.submittedAt || new Date().toISOString(),
    reviewedAt: product.reviewedAt || null,
    reviewNotes: product.reviewNotes || "",
    archivedAt: isArchived ? product.archivedAt || product.reviewedAt || null : null,
    rightsOwnershipType: product.rightsOwnershipType ? String(product.rightsOwnershipType).trim() : null,
    rightsReferenceFlags: normalizeRightsReferenceFlags(product.rightsReferenceFlags),
    rightsCertificationAccepted: product.rightsCertificationAccepted === true,
    rightsCertificationAcceptedAt: product.rightsCertificationAcceptedAt || null,
    requiresManualReview: product.requiresManualReview === true,
    reviewReason: product.reviewReason ? String(product.reviewReason).trim() : null,
  };
}

export function normalizeCatalogDocument(raw = {}) {
  const products = Array.isArray(raw?.products) ? raw.products.map((p) => normalizeCatalogProduct(p)) : [];
  return {
    version: Math.max(1, asFiniteNumber(raw?.version, 1)),
    updatedAt: raw?.updatedAt || new Date().toISOString(),
    products,
  };
}

/** Compare persisted product fields (excludes review hydration). */
export function productComparable(product = {}) {
  return {
    id: product.id,
    sellerId: product.sellerId,
    name: product.name,
    category: product.category,
    priceCents: product.priceCents,
    previousPriceCents: product.previousPriceCents,
    material: product.material,
    durabilityNote: product.durabilityNote,
    careWarnings: product.careWarnings,
    shipsInMinDays: product.shipsInMinDays,
    shipsInMaxDays: product.shipsInMaxDays,
    isDrop: product.isDrop === true,
    isActive: product.isActive === true,
    isApproved: product.isApproved === true,
    approvalStatus: product.approvalStatus,
    reviewNotes: product.reviewNotes,
    dropHeadline: product.dropHeadline,
    dropStory: product.dropStory,
    dropBestUseCase: product.dropBestUseCase,
    requiresManualReview: product.requiresManualReview === true,
    reviewReason: product.reviewReason,
    rightsOwnershipType: product.rightsOwnershipType,
    rightsReferenceFlags: product.rightsReferenceFlags,
    rightsCertificationAccepted: product.rightsCertificationAccepted === true,
  };
}

export function productMediaComparable(product = {}) {
  return {
    imageURLs: product.imageURLs || [],
    demoVideoURL: product.demoVideoURL || null,
    productionPreviewURL: product.productionPreviewURL || null,
  };
}
