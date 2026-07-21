export const DEFAULT_SELLER_SUBSCRIPTION_PRODUCT_ID =
  process.env.SELLER_SUBSCRIPTION_PRODUCT_ID || "com.innovativecodeworks.com.TenBelow.seller.monthly";

export const DEFAULT_CATEGORY_SLUG = "desk";

export const DEFAULT_VARIANT_SUFFIX = "::default";

export function defaultVariantId(productId) {
  return `${String(productId || "").trim()}${DEFAULT_VARIANT_SUFFIX}`;
}

export function defaultVariantSku(productId) {
  return String(productId || "").trim() || "default";
}
