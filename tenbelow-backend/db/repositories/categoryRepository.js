import { categoryComparable, extractCategoriesFromProducts } from "../../domain/phase1/category.js";
import { getPrisma } from "../prisma/client.js";
import { loadCatalogFromJson } from "./jsonStore.js";
import { readProductsFromJson } from "./productRepository.js";
import { compareRecordSets } from "./compareUtils.js";

export function readCategoriesFromJson(catalog = loadCatalogFromJson()) {
  const categories = extractCategoriesFromProducts(catalog.products);
  return Object.fromEntries(categories.map((category) => [category.slug, categoryComparable(category)]));
}

export async function syncCategoriesToPrisma(catalog = loadCatalogFromJson()) {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  const categories = extractCategoriesFromProducts(catalog.products);
  let synced = 0;
  for (const category of categories) {
    await prisma.category.upsert({
      where: { slug: category.slug },
      create: {
        slug: category.slug,
        displayName: category.displayName,
        sortOrder: category.sortOrder,
        isActive: category.isActive !== false,
      },
      update: {
        displayName: category.displayName,
        sortOrder: category.sortOrder,
        isActive: category.isActive !== false,
      },
    });
    synced += 1;
  }
  return { synced };
}

export async function readCategoriesFromPrisma() {
  const prisma = getPrisma();
  if (!prisma) return {};
  const rows = await prisma.category.findMany();
  return Object.fromEntries(rows.map((row) => [row.slug, categoryComparable(row)]));
}

export async function compareCategories() {
  const jsonRecordsById = readCategoriesFromJson();
  const prismaRecordsById = await readCategoriesFromPrisma();
  const products = readProductsFromJson();
  const relationshipMismatches = [];
  const categorySlugs = new Set(Object.keys(jsonRecordsById));
  for (const product of Object.values(products)) {
    if (product.category && !categorySlugs.has(product.category)) {
      relationshipMismatches.push(`Product ${product.id} uses category '${product.category}' not present in category set`);
    }
  }
  return compareRecordSets({
    repository: "categories",
    jsonRecordsById,
    prismaRecordsById,
    comparableFields: ["slug", "displayName", "sortOrder", "isActive"],
    relationshipMismatches,
  });
}
