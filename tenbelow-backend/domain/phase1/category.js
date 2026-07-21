import { DEFAULT_CATEGORY_SLUG } from "./constants.js";

function titleCaseSlug(slug = "") {
  return String(slug || "")
    .split(/[-_]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

export function categoryFromSlug(slug, sortOrder = 0) {
  const normalized = String(slug || DEFAULT_CATEGORY_SLUG).trim().toLowerCase() || DEFAULT_CATEGORY_SLUG;
  return {
    slug: normalized,
    displayName: titleCaseSlug(normalized),
    sortOrder,
    isActive: true,
  };
}

export function extractCategoriesFromProducts(products = []) {
  const slugs = new Set();
  for (const product of products) {
    const slug = String(product?.category || DEFAULT_CATEGORY_SLUG).trim().toLowerCase() || DEFAULT_CATEGORY_SLUG;
    slugs.add(slug);
  }
  if (slugs.size === 0) slugs.add(DEFAULT_CATEGORY_SLUG);
  return Array.from(slugs)
    .sort((a, b) => a.localeCompare(b))
    .map((slug, index) => categoryFromSlug(slug, index));
}

export function categoryComparable(category = {}) {
  return {
    slug: category.slug,
    displayName: category.displayName,
    sortOrder: category.sortOrder,
    isActive: category.isActive !== false,
  };
}
