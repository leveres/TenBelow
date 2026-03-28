import { readFileSync, writeFileSync, existsSync } from "fs";
import { fileURLToPath } from "url";
import { dataFileURL, ensureDirectory } from "./storagePaths.js";

const PATH = dataFileURL("push_devices.json");

export function loadPushDevices() {
  if (!existsSync(fileURLToPath(PATH))) return {};
  try {
    return JSON.parse(readFileSync(PATH, "utf-8"));
  } catch {
    return {};
  }
}

function savePushDevices(map) {
  ensureDirectory(new URL("./", PATH));
  writeFileSync(PATH, JSON.stringify(map, null, 2));
}

/**
 * @param {string} userKey e.g. seller:SELL-01, buyer:email@x.com, guest
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

  const map = loadPushDevices();
  if (!map[normalizedKey]) map[normalizedKey] = [];
  if (!map[normalizedKey].includes(token)) {
    map[normalizedKey].push(token);
  }
  if (map[normalizedKey].length > 8) {
    map[normalizedKey] = map[normalizedKey].slice(-8);
  }
  savePushDevices(map);
}
