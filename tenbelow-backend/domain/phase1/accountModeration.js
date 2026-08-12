const VALID_ACTIONS = new Set(["flag", "unflag", "freeze", "unfreeze"]);

function asISODateOrNull(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return null;
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

export const ACCOUNT_MODERATION_ACTIONS = ["flag", "unflag", "freeze", "unfreeze"];

export function normalizeAccountModeration(raw = {}) {
  const lastAction = String(raw.lastAction || "").trim().toLowerCase();
  const lastEmailStatus = String(raw.lastEmailStatus || "").trim().toLowerCase();

  return {
    isFlagged: raw.isFlagged === true,
    isFrozen: raw.isFrozen === true,
    flagReason: String(raw.flagReason || "").trim() || null,
    freezeReason: String(raw.freezeReason || "").trim() || null,
    flaggedAt: asISODateOrNull(raw.flaggedAt),
    frozenAt: asISODateOrNull(raw.frozenAt),
    lastAction: VALID_ACTIONS.has(lastAction) ? lastAction : null,
    lastActionAt: asISODateOrNull(raw.lastActionAt),
    lastEmailStatus: ["sent", "failed", "skipped"].includes(lastEmailStatus) ? lastEmailStatus : null,
    lastEmailSentAt: asISODateOrNull(raw.lastEmailSentAt),
    lastEmailError: String(raw.lastEmailError || "").trim() || null,
  };
}

export function accountModerationSummary(raw = {}) {
  return normalizeAccountModeration(raw);
}

export function applyAccountModerationAction(current = {}, { action, reason = "" } = {}) {
  const normalizedAction = String(action || "").trim().toLowerCase();
  if (!VALID_ACTIONS.has(normalizedAction)) {
    throw new Error("action must be flag, unflag, freeze, or unfreeze");
  }

  const trimmedReason = String(reason || "").trim();
  const now = new Date().toISOString();
  const moderation = normalizeAccountModeration(current);

  switch (normalizedAction) {
    case "flag":
      if (!trimmedReason) {
        throw new Error("A reason is required to flag an account");
      }
      return normalizeAccountModeration({
        ...moderation,
        isFlagged: true,
        flagReason: trimmedReason,
        flaggedAt: now,
        lastAction: "flag",
        lastActionAt: now,
      });
    case "unflag":
      return normalizeAccountModeration({
        ...moderation,
        isFlagged: false,
        flagReason: null,
        flaggedAt: null,
        lastAction: "unflag",
        lastActionAt: now,
      });
    case "freeze":
      if (!trimmedReason) {
        throw new Error("A reason is required to freeze an account");
      }
      return normalizeAccountModeration({
        ...moderation,
        isFrozen: true,
        freezeReason: trimmedReason,
        frozenAt: now,
        lastAction: "freeze",
        lastActionAt: now,
      });
    case "unfreeze":
      return normalizeAccountModeration({
        ...moderation,
        isFrozen: false,
        freezeReason: null,
        frozenAt: null,
        lastAction: "unfreeze",
        lastActionAt: now,
      });
    default:
      throw new Error("Unsupported moderation action");
  }
}

export function accountModerationRequiresEmail(action = "") {
  return ["flag", "freeze"].includes(String(action || "").trim().toLowerCase());
}

export function accountModerationBlockPayload(kind = "seller", moderation = {}) {
  const normalized = normalizeAccountModeration(moderation);
  if (!normalized.isFrozen) return null;

  const accountLabel = kind === "buyer" ? "buyer" : "seller";
  return {
    status: 403,
    body: {
      error: `Your ${accountLabel} account is temporarily frozen. Check your email for details or contact support@tenbelow.com.`,
      code: `${accountLabel}_account_frozen`,
      accountModeration: {
        isFrozen: true,
        freezeReason: normalized.freezeReason,
        frozenAt: normalized.frozenAt,
      },
    },
  };
}

export function recordAccountModerationEmailResult(moderation = {}, { sent = false, skipped = false, error = "" } = {}) {
  const normalized = normalizeAccountModeration(moderation);
  if (skipped) {
    return normalizeAccountModeration({
      ...normalized,
      lastEmailStatus: "skipped",
      lastEmailSentAt: null,
      lastEmailError: null,
    });
  }
  if (sent) {
    return normalizeAccountModeration({
      ...normalized,
      lastEmailStatus: "sent",
      lastEmailSentAt: new Date().toISOString(),
      lastEmailError: null,
    });
  }
  return normalizeAccountModeration({
    ...normalized,
    lastEmailStatus: "failed",
    lastEmailError: String(error || "Email delivery failed").trim() || "Email delivery failed",
  });
}
