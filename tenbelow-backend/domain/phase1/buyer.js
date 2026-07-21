export function normalizeBuyerRecord(record = {}, email = "") {
  const normalizedEmail = String(email || record.email || "").trim().toLowerCase();
  return {
    email: normalizedEmail,
    fullName: String(record.fullName || "").trim(),
    passwordHash: String(record.passwordHash || "").trim(),
    emailVerified: record.emailVerified === true,
    emailVerifiedAt: record.emailVerifiedAt || null,
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || new Date().toISOString(),
  };
}

export function normalizeBuyerMap(raw = {}) {
  const src = raw && typeof raw === "object" ? raw : {};
  return Object.fromEntries(
    Object.entries(src).map(([email, record]) => [email, normalizeBuyerRecord(record, email)])
  );
}

export function buyerComparable(record = {}) {
  return {
    email: record.email,
    fullName: record.fullName,
    passwordHash: record.passwordHash,
    emailVerified: record.emailVerified === true,
    emailVerifiedAt: record.emailVerifiedAt || null,
  };
}
