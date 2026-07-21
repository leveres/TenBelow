import { buildVariantsFromProducts, defaultVariantForProduct, variantComparable } from "../../domain/phase1/variant.js";
import { getPrisma } from "../prisma/client.js";
import { loadCatalogFromJson } from "./jsonStore.js";
import { readProductsFromJson } from "./productRepository.js";
import { compareRecordSets } from "./compareUtils.js";

export function readVariantsFromJson(catalog = loadCatalogFromJson()) {
  const variants = buildVariantsFromProducts(catalog.products);
  return Object.fromEntries(variants.map((variant) => [variant.id, variant]));
}

export async function syncVariantsToPrisma(catalog = loadCatalogFromJson()) {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  let synced = 0;
  for (const product of catalog.products) {
    const variant = defaultVariantForProduct(product);
    await prisma.productVariant.upsert({
      where: { id: variant.id },
      create: {
        id: variant.id,
        productId: variant.productId,
        sku: variant.sku,
        name: variant.name,
        priceCents: variant.priceCents,
        isDefault: true,
      },
      update: {
        productId: variant.productId,
        sku: variant.sku,
        name: variant.name,
        priceCents: variant.priceCents,
        isDefault: true,
      },
    });

    await prisma.inventoryItem.upsert({
      where: { variantId: variant.id },
      create: {
        variantId: variant.id,
        trackInventory: false,
        quantityOnHand: null,
      },
      update: {
        trackInventory: false,
        quantityOnHand: null,
      },
    });
    synced += 1;
  }
  return { synced };
}

export async function readVariantsFromPrisma() {
  const prisma = getPrisma();
  if (!prisma) return {};
  const rows = await prisma.productVariant.findMany();
  return Object.fromEntries(rows.map((row) => [row.id, variantComparable(row)]));
}

export async function compareVariants() {
  const jsonRecordsById = Object.fromEntries(
    Object.entries(readVariantsFromJson()).map(([id, variant]) => [id, variantComparable(variant)])
  );
  const prismaRecordsById = await readVariantsFromPrisma();
  const products = readProductsFromJson();
  const relationshipMismatches = [];
  for (const variant of Object.values(jsonRecordsById)) {
    if (variant.productId && !products[variant.productId]) {
      relationshipMismatches.push(`Variant ${variant.id} references missing product ${variant.productId}`);
    }
  }
  for (const variant of Object.values(prismaRecordsById)) {
    if (variant.productId && !products[variant.productId]) {
      relationshipMismatches.push(`Prisma variant ${variant.id} references product not in JSON catalog`);
    }
  }
  return compareRecordSets({
    repository: "productVariants",
    jsonRecordsById,
    prismaRecordsById,
    comparableFields: ["productId", "sku", "name", "priceCents", "isDefault"],
    relationshipMismatches,
  });
}
