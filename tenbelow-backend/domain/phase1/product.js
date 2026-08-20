import crypto from "crypto";
import { DEFAULT_CATEGORY_SLUG } from "./constants.js";

export const MAX_PRODUCT_COLORS = 12;

export class AvailableColorsValidationError extends TypeError {
  constructor(message) {
    super(message);
    this.name = "AvailableColorsValidationError";
    this.code = "invalid_available_colors";
  }
}

function asFiniteNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function colorSlug(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

function colorNameSlug(name) {
  const slug = colorSlug(name);
  if (slug) return slug;
  const digest = crypto.createHash("sha256").update(String(name)).digest("hex").slice(0, 12);
  return `color-${digest}`;
}

function normalizeColorHex(value, { strict }) {
  if (value == null || String(value).trim() === "") return undefined;
  const compact = String(value).trim().replace(/^#/, "").toUpperCase();
  if (!/^[0-9A-F]{6}$/.test(compact)) {
    if (strict) throw new AvailableColorsValidationError("Color hex values must use 6 hexadecimal digits");
    return undefined;
  }
  return `#${compact}`;
}

export function normalizeAvailableColors(value, { strict = false, existingColors = [] } = {}) {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    if (strict) throw new AvailableColorsValidationError("availableColors must be an array");
    return [];
  }
  if (strict && value.length > MAX_PRODUCT_COLORS) {
    throw new AvailableColorsValidationError(`availableColors cannot contain more than ${MAX_PRODUCT_COLORS} colors`);
  }

  const existingIdByName = new Map(
    (Array.isArray(existingColors) ? existingColors : [])
      .map((color) => {
        const name = String(color?.name || "").trim();
        const id = colorSlug(color?.id);
        return name && id ? [name.toLocaleLowerCase("en-US"), id] : null;
      })
      .filter(Boolean)
  );
  const seenNames = new Set();
  const usedIds = new Set();
  const normalized = [];

  for (const rawColor of value.slice(0, MAX_PRODUCT_COLORS)) {
    if (!rawColor || typeof rawColor !== "object" || Array.isArray(rawColor)) {
      if (strict) throw new AvailableColorsValidationError("Each available color must be an object");
      continue;
    }

    const name = String(rawColor.name || "").trim();
    if (!name) {
      if (strict) throw new AvailableColorsValidationError("Each available color requires a name");
      continue;
    }

    const nameKey = name.toLocaleLowerCase("en-US");
    if (seenNames.has(nameKey)) {
      if (strict) throw new AvailableColorsValidationError("Color names must be unique (case-insensitive)");
      continue;
    }

    const requestedId = colorSlug(rawColor.id);
    const stableExistingId = colorSlug(existingIdByName.get(nameKey));
    const baseId = requestedId || stableExistingId || colorNameSlug(name);

    let id = baseId;
    let suffix = 2;
    while (usedIds.has(id)) {
      id = `${baseId.slice(0, Math.max(1, 48 - String(suffix).length - 1))}-${suffix}`;
      suffix += 1;
    }

    const hex = normalizeColorHex(rawColor.hex, { strict });
    normalized.push(hex ? { id, name, hex } : { id, name });
    seenNames.add(nameKey);
    usedIds.add(id);
  }

  return normalized;
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
    availableColors: normalizeAvailableColors(product.availableColors),
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
    availableColors: normalizeAvailableColors(product.availableColors),
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
