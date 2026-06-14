/** Per-seller shipping tiers (item count) with free shipping at $35+ subtotal from that seller. */

export const FREE_SHIPPING_THRESHOLD_CENTS = 3500;

export function shippingCentsForSellerGroup({ itemCount, subtotalCents } = {}) {
  const count = Math.max(0, Math.floor(Number(itemCount) || 0));
  const subtotal = Math.max(0, Math.floor(Number(subtotalCents) || 0));
  if (count === 0 || subtotal === 0) return 0;
  if (subtotal >= FREE_SHIPPING_THRESHOLD_CENTS) return 0;
  if (count === 1) return 599;
  if (count === 2) return 549;
  if (count === 3) return 499;
  return 449;
}

export function computeShippingTotalsBySeller(orderItems = []) {
  const groups = {};

  for (const item of Array.isArray(orderItems) ? orderItems : []) {
    const sellerId = String(item?.sellerId || "").trim();
    if (!sellerId) continue;

    const quantity = Math.max(0, Math.floor(Number(item?.quantity) || 0));
    const priceCents = Math.max(0, Math.floor(Number(item?.priceCents) || 0));
    if (quantity <= 0) continue;

    if (!groups[sellerId]) {
      groups[sellerId] = { itemCount: 0, subtotalCents: 0 };
    }
    groups[sellerId].itemCount += quantity;
    groups[sellerId].subtotalCents += priceCents * quantity;
  }

  const shippingTotals = {};
  let totalShippingCents = 0;

  for (const [sellerId, group] of Object.entries(groups)) {
    const cents = shippingCentsForSellerGroup(group);
    shippingTotals[sellerId] = cents;
    totalShippingCents += cents;
  }

  return { shippingTotals, totalShippingCents };
}
