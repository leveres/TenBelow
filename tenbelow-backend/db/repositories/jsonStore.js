import { existsSync, readFileSync } from "fs";
import path from "path";
import { DATA_DIRECTORY_PATH } from "../../storagePaths.js";
import { normalizeBuyerMap } from "../../domain/phase1/buyer.js";
import { normalizeSellerMap } from "../../domain/phase1/seller.js";
import { normalizeCatalogDocument } from "../../domain/phase1/product.js";

function readJsonFile(filename, fallback) {
  const fullPath = path.join(DATA_DIRECTORY_PATH, filename);
  if (!existsSync(fullPath)) return fallback;
  try {
    return JSON.parse(readFileSync(fullPath, "utf8"));
  } catch {
    return fallback;
  }
}

export function loadBuyersFromJson() {
  return normalizeBuyerMap(readJsonFile("buyers.json", {}));
}

export function loadSellersFromJson() {
  return normalizeSellerMap(readJsonFile("sellers.json", {}));
}

export function loadCatalogFromJson() {
  return normalizeCatalogDocument(readJsonFile("products.json", { version: 1, products: [] }));
}

export function loadUsersFromJson() {
  return {
    buyers: loadBuyersFromJson(),
    sellers: loadSellersFromJson(),
  };
}
