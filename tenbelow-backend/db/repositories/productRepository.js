import { productComparable, productMediaComparable } from "../../domain/phase1/product.js";
import { getPrisma } from "../prisma/client.js";
import { loadCatalogFromJson, loadSellersFromJson } from "./jsonStore.js";
import { compareRecordSets } from "./compareUtils.js";

function toDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function mapApprovalStatus(status) {
  const normalized = String(status || "submitted").toLowerCase();
  if (["submitted", "approved", "rejected", "archived"].includes(normalized)) return normalized;
  return "submitted";
}

const PRODUCT_FIELDS = [
  "sellerId",
  "name",
  "category",
  "priceCents",
  "previousPriceCents",
  "availableColors",
  "material",
  "durabilityNote",
  "careWarnings",
  "shipsInMinDays",
  "shipsInMaxDays",
  "isDrop",
  "isActive",
  "isApproved",
  "approvalStatus",
  "reviewNotes",
  "dropHeadline",
  "dropStory",
  "dropBestUseCase",
  "requiresManualReview",
  "reviewReason",
  "rightsOwnershipType",
  "rightsReferenceFlags",
  "rightsCertificationAccepted",
];

export function readProductsFromJson(catalog = loadCatalogFromJson()) {
  return Object.fromEntries(catalog.products.map((product) => [product.id, product]));
}

export async function syncProductsToPrisma(catalog = loadCatalogFromJson()) {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  let synced = 0;
  for (const product of catalog.products) {
    await prisma.product.upsert({
      where: { id: product.id },
      create: {
        id: product.id,
        sellerId: product.sellerId,
        name: product.name,
        category: product.category,
        priceCents: product.priceCents,
        previousPriceCents: product.previousPriceCents,
        availableColors: product.availableColors || [],
        material: product.material,
        durabilityNote: product.durabilityNote,
        careWarnings: product.careWarnings,
        shipsInMinDays: product.shipsInMinDays,
        shipsInMaxDays: product.shipsInMaxDays,
        isDrop: product.isDrop === true,
        isActive: product.isActive === true,
        isApproved: product.isApproved === true,
        approvalStatus: mapApprovalStatus(product.approvalStatus),
        submittedAt: toDate(product.submittedAt) || new Date(),
        reviewedAt: toDate(product.reviewedAt),
        archivedAt: toDate(product.archivedAt),
        reviewNotes: product.reviewNotes || "",
        dropHeadline: product.dropHeadline || "",
        dropStory: product.dropStory || "",
        dropBestUseCase: product.dropBestUseCase || "",
        requiresManualReview: product.requiresManualReview === true,
        reviewReason: product.reviewReason,
      },
      update: {
        sellerId: product.sellerId,
        name: product.name,
        category: product.category,
        priceCents: product.priceCents,
        previousPriceCents: product.previousPriceCents,
        availableColors: product.availableColors || [],
        material: product.material,
        durabilityNote: product.durabilityNote,
        careWarnings: product.careWarnings,
        shipsInMinDays: product.shipsInMinDays,
        shipsInMaxDays: product.shipsInMaxDays,
        isDrop: product.isDrop === true,
        isActive: product.isActive === true,
        isApproved: product.isApproved === true,
        approvalStatus: mapApprovalStatus(product.approvalStatus),
        submittedAt: toDate(product.submittedAt) || new Date(),
        reviewedAt: toDate(product.reviewedAt),
        archivedAt: toDate(product.archivedAt),
        reviewNotes: product.reviewNotes || "",
        dropHeadline: product.dropHeadline || "",
        dropStory: product.dropStory || "",
        dropBestUseCase: product.dropBestUseCase || "",
        requiresManualReview: product.requiresManualReview === true,
        reviewReason: product.reviewReason,
      },
    });

    await prisma.productMedia.deleteMany({ where: { productId: product.id } });
    const mediaRows = [];
    (product.imageURLs || []).forEach((url, index) => {
      if (!url) return;
      mediaRows.push({ productId: product.id, kind: "image", url, sortOrder: index });
    });
    if (product.demoVideoURL) {
      mediaRows.push({ productId: product.id, kind: "demo_video", url: product.demoVideoURL, sortOrder: 0 });
    }
    if (product.productionPreviewURL) {
      mediaRows.push({
        productId: product.id,
        kind: "production_preview",
        url: product.productionPreviewURL,
        sortOrder: 0,
      });
    }
    if (mediaRows.length) {
      await prisma.productMedia.createMany({ data: mediaRows });
    }

    if (
      product.rightsOwnershipType ||
      product.rightsCertificationAccepted ||
      (product.rightsReferenceFlags || []).length
    ) {
      await prisma.productRights.upsert({
        where: { productId: product.id },
        create: {
          productId: product.id,
          ownershipType: product.rightsOwnershipType,
          referenceFlags: product.rightsReferenceFlags || [],
          certificationAccepted: product.rightsCertificationAccepted === true,
          certificationAcceptedAt: toDate(product.rightsCertificationAcceptedAt),
        },
        update: {
          ownershipType: product.rightsOwnershipType,
          referenceFlags: product.rightsReferenceFlags || [],
          certificationAccepted: product.rightsCertificationAccepted === true,
          certificationAcceptedAt: toDate(product.rightsCertificationAcceptedAt),
        },
      });
    }

    synced += 1;
  }
  return { synced };
}

export async function readProductsFromPrisma() {
  const prisma = getPrisma();
  if (!prisma) return {};
  const rows = await prisma.product.findMany({
    include: { media: true, rights: true },
  });
  return Object.fromEntries(
    rows.map((row) => {
      const imageURLs = row.media
        .filter((m) => m.kind === "image")
        .sort((a, b) => a.sortOrder - b.sortOrder)
        .map((m) => m.url);
      const demoVideoURL = row.media.find((m) => m.kind === "demo_video")?.url || null;
      const productionPreviewURL = row.media.find((m) => m.kind === "production_preview")?.url || null;
      return [
        row.id,
        {
          ...productComparable({
            id: row.id,
            sellerId: row.sellerId,
            name: row.name,
            category: row.category,
            priceCents: row.priceCents,
            previousPriceCents: row.previousPriceCents,
            availableColors: row.availableColors,
            material: row.material,
            durabilityNote: row.durabilityNote,
            careWarnings: row.careWarnings,
            shipsInMinDays: row.shipsInMinDays,
            shipsInMaxDays: row.shipsInMaxDays,
            isDrop: row.isDrop,
            isActive: row.isActive,
            isApproved: row.isApproved,
            approvalStatus: row.approvalStatus,
            reviewNotes: row.reviewNotes,
            dropHeadline: row.dropHeadline,
            dropStory: row.dropStory,
            dropBestUseCase: row.dropBestUseCase,
            requiresManualReview: row.requiresManualReview,
            reviewReason: row.reviewReason,
            rightsOwnershipType: row.rights?.ownershipType || null,
            rightsReferenceFlags: row.rights?.referenceFlags || [],
            rightsCertificationAccepted: row.rights?.certificationAccepted === true,
          }),
          media: productMediaComparable({ imageURLs, demoVideoURL, productionPreviewURL }),
        },
      ];
    })
  );
}

export async function compareProducts() {
  const jsonProducts = readProductsFromJson();
  const jsonRecordsById = Object.fromEntries(
    Object.entries(jsonProducts).map(([id, product]) => [id, productComparable(product)])
  );
  const prismaRows = await readProductsFromPrisma();
  const prismaRecordsById = Object.fromEntries(
    Object.entries(prismaRows).map(([id, row]) => {
      const { media: _media, ...productFields } = row;
      return [id, productFields];
    })
  );

  const sellers = loadSellersFromJson();
  const relationshipMismatches = [];
  for (const product of Object.values(jsonProducts)) {
    if (product.sellerId && !sellers[product.sellerId]) {
      relationshipMismatches.push(`Product ${product.id} references missing seller ${product.sellerId} in JSON`);
    }
  }
  for (const [id, row] of Object.entries(prismaRows)) {
    const jsonProduct = jsonProducts[id];
    if (!jsonProduct) continue;
    const jsonMedia = productMediaComparable(jsonProduct);
    if (JSON.stringify(jsonMedia) !== JSON.stringify(row.media)) {
      relationshipMismatches.push(`Product ${id} media mismatch between JSON and Prisma`);
    }
  }

  const baseReport = compareRecordSets({
    repository: "products",
    jsonRecordsById,
    prismaRecordsById,
    comparableFields: PRODUCT_FIELDS,
    relationshipMismatches,
  });

  return baseReport;
}
