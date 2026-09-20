import crypto from "crypto";

export const CUSTOMER_ORDER_NUMBER_PATTERN = /^TB-[0-9A-F]{6}$/;

export function normalizeCustomerOrderNumber(value = "") {
  const raw = String(value || "").trim().toUpperCase();
  return CUSTOMER_ORDER_NUMBER_PATTERN.test(raw) ? raw : "";
}

export function generateCustomerOrderNumber() {
  return `TB-${crypto.randomBytes(3).toString("hex").toUpperCase()}`;
}

export function allocateCustomerOrderNumber(
  existingNumbers = [],
  { generate = generateCustomerOrderNumber, maxAttempts = 32 } = {}
) {
  const taken = new Set(
    [...existingNumbers].map((value) => normalizeCustomerOrderNumber(value)).filter(Boolean)
  );

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const candidate = normalizeCustomerOrderNumber(generate());
    if (candidate && !taken.has(candidate)) {
      return candidate;
    }
  }

  throw new Error("Unable to allocate a unique TenBelow order number");
}

export function resolvePersistedCustomerOrderNumber({
  existingOrderNumber = "",
  existingNumbers = [],
  generate = generateCustomerOrderNumber,
  maxAttempts = 32,
} = {}) {
  const preserved = normalizeCustomerOrderNumber(existingOrderNumber);
  if (preserved) return preserved;

  try {
    return allocateCustomerOrderNumber(existingNumbers, { generate, maxAttempts });
  } catch {
    return "";
  }
}

export function customerFacingOrderNumber(order = {}) {
  return normalizeCustomerOrderNumber(order.orderNumber);
}
