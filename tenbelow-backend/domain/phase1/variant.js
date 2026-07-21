import { defaultVariantId, defaultVariantSku } from "./constants.js";

export function defaultVariantForProduct(product = {}) {
  const productId = String(product.id || "").trim();
  return {
    id: defaultVariantId(productId),
    productId,
    sku: defaultVariantSku(productId),
    name: "Default",
    priceCents: Math.max(0, Number(product.priceCents) || 0),
    isDefault: true,
  };
}

export function variantComparable(variant = {}) {
  return {
    id: variant.id,
    productId: variant.productId,
    sku: variant.sku,
    name: variant.name,
    priceCents: variant.priceCents,
    isDefault: variant.isDefault === true,
  };
}

export function buildVariantsFromProducts(products = []) {
  return products.map((product) => defaultVariantForProduct(product));
}
