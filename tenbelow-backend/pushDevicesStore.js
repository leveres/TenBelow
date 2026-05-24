import { readFileSync, writeFileSync, existsSync } from "fs";
import { fileURLToPath } from "url";
import { dataFileURL, ensureDirectory } from "./storagePaths.js";

const PATH = dataFileURL("push_devices.json");

/**
 * @param {unknown} parsed
 * @returns {{ version: 2, byUser: Record<string, string[]>, tokenToUser: Record<string, string> }}
 */
function normalizeStore(parsed) {
  if (parsed && parsed.version === 2 && parsed.byUser && parsed.tokenToUser) {
    return {
      version: 2,
      byUser: { ...parsed.byUser },
      tokenToUser: { ...parsed.tokenToUser },
    };
  }

  const byUser = {};
  const tokenToUser = {};
  for (const [userKey, tokens] of Object.entries(parsed || {})) {
    if (userKey === "version" || userKey === "byUser" || userKey === "tokenToUser") continue;
    if (!Array.isArray(tokens)) continue;

    const cleaned = [
      ...new Set(
        tokens
          .map((t) => String(t || "")
            .trim()
            .toLowerCase()
            .replace(/\s/g, ""))
          .filter(Boolean)
      ),
    ];

    byUser[userKey] = cleaned;
    for (const t of cleaned) {
      tokenToUser[t] = userKey;
    }
  }

  return { version: 2, byUser, tokenToUser };
}

function loadStore() {
  if (!existsSync(fileURLToPath(PATH))) {
    return { version: 2, byUser: {}, tokenToUser: {} };
  }
  try {
    return normalizeStore(JSON.parse(readFileSync(PATH, "utf-8")));
  } catch {
    return { version: 2, byUser: {}, tokenToUser: {} };
  }
}

function saveStore(store) {
  ensureDirectory(new URL("./", PATH));
  writeFileSync(PATH, JSON.stringify(store, null, 2));
}

/**
 * @returns {Record<string, string[]>} map of userKey -> device tokens (compat with pushOrderNotifications)
 */
export function loadPushDevices() {
  const { byUser } = loadStore();
  return byUser;
}

/**
 * Registers a device token; each token maps to at most one userKey (last registration wins).
 * @param {string} userKey e.g. seller:SELL-01, buyer:email@x.com, guest:<uuid>
 * @param {string} deviceTokenHex
 */
export function registerPushDevice(userKey, deviceTokenHex) {
  const normalizedKey = String(userKey || "guest").trim() || "guest";
  const token = String(deviceTokenHex || "")
    .trim()
    .toLowerCase()
    .replace(/\s/g, "");
  if (!/^[0-9a-f]{64}$/.test(token)) {
    throw new Error("Invalid device token (expected 64 hex chars)");
  }

  const store = loadStore();

  for (const [uk, arr] of Object.entries(store.byUser)) {
    const next = arr.filter((t) => t !== token);
    if (next.length !== arr.length) {
      if (next.length) store.byUser[uk] = next;
      else delete store.byUser[uk];
    }
  }

  delete store.tokenToUser[token];
  store.tokenToUser[token] = normalizedKey;

  if (!store.byUser[normalizedKey]) store.byUser[normalizedKey] = [];
  if (!store.byUser[normalizedKey].includes(token)) {
    store.byUser[normalizedKey].push(token);
  }

  if (store.byUser[normalizedKey].length > 8) {
    const dropped = store.byUser[normalizedKey].slice(0, -8);
    store.byUser[normalizedKey] = store.byUser[normalizedKey].slice(-8);
    for (const t of dropped) {
      if (store.tokenToUser[t] === normalizedKey) {
        delete store.tokenToUser[t];
      }
    }
  }

  saveStore(store);
}

export function unregisterPushDevice(userKey, deviceTokenHex) {
  const normalizedKey = String(userKey || "").trim();
  const token = String(deviceTokenHex || "")
    .trim()
    .toLowerCase()
    .replace(/\s/g, "");
  if (!normalizedKey || !token) return false;

  const store = loadStore();
  const existing = Array.isArray(store.byUser[normalizedKey]) ? store.byUser[normalizedKey] : [];
  const next = existing.filter((t) => t !== token);
  if (next.length) {
    store.byUser[normalizedKey] = next;
  } else {
    delete store.byUser[normalizedKey];
  }
  if (store.tokenToUser[token] === normalizedKey) {
    delete store.tokenToUser[token];
  }
  saveStore(store);
  return next.length !== existing.length;
}
