import { getPrisma } from "../prisma/client.js";
import {
  SELLER_AGREEMENT_REGISTRY,
  getSellerAgreementDocument,
} from "../../legal/sellerAgreementDocuments.js";

function toDate(value) {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export async function syncLegalAgreementDocumentsToPrisma() {
  const prisma = getPrisma();
  if (!prisma) return { synced: 0, skipped: true };

  let synced = 0;
  for (const entry of SELLER_AGREEMENT_REGISTRY) {
    const document = getSellerAgreementDocument(entry.id);
    await prisma.legalAgreementDocument.upsert({
      where: { id: document.id },
      create: {
        id: document.id,
        agreementType: document.agreementType,
        versionLabel: document.versionLabel,
        effectiveDate: new Date(`${document.effectiveDate}T00:00:00.000Z`),
        documentHash: document.documentHash,
        storagePath: document.contentPath,
        publicPath: document.publicPath,
        isActiveForNewSellers: document.isActiveForNewSellers === true,
        publishedAt: toDate(document.publishedAt),
        supersededAt: toDate(document.supersededAt),
      },
      update: {
        agreementType: document.agreementType,
        versionLabel: document.versionLabel,
        effectiveDate: new Date(`${document.effectiveDate}T00:00:00.000Z`),
        documentHash: document.documentHash,
        storagePath: document.contentPath,
        publicPath: document.publicPath,
        isActiveForNewSellers: document.isActiveForNewSellers === true,
        publishedAt: toDate(document.publishedAt),
        supersededAt: toDate(document.supersededAt),
      },
    });
    synced += 1;
  }

  return { synced };
}

export async function upsertSellerAgreementAcceptanceToPrisma(sellerId, sellerRecord = {}) {
  const prisma = getPrisma();
  if (!prisma) return { synced: false, skipped: true };

  const agreement = sellerRecord.sellerAgreement || {};
  if (agreement.accepted !== true || !agreement.documentId) {
    return { synced: false, skipped: true };
  }

  const acceptanceId = agreement.acceptanceId || `${sellerId}:${agreement.documentId}`;
  const welcome = sellerRecord.welcomeEmail || {};

  await prisma.sellerAgreementAcceptance.upsert({
    where: {
      sellerId_documentId: {
        sellerId,
        documentId: agreement.documentId,
      },
    },
    create: {
      id: acceptanceId,
      sellerId,
      agreementType: agreement.agreementType || "seller_agreement",
      documentId: agreement.documentId,
      version: agreement.version || agreement.documentId,
      documentHash: agreement.documentHash || "",
      acceptedAt: toDate(agreement.acceptedAt) || new Date(),
      sellerEmail: agreement.emailAtAcceptance || sellerRecord.email || "",
      sellerLegalName: agreement.legalNameAtAcceptance || sellerRecord.legalName || "",
      source: "seller_registration",
      welcomeEmailStatus: welcome.status || "pending",
      welcomeEmailSentAt: toDate(welcome.sentAt),
      welcomeEmailMessageId: welcome.messageId || null,
      welcomeEmailLastError: welcome.lastError || null,
      welcomeEmailAttemptCount: Math.max(0, Number(welcome.attemptCount) || 0),
    },
    update: {
      welcomeEmailStatus: welcome.status || "pending",
      welcomeEmailSentAt: toDate(welcome.sentAt),
      welcomeEmailMessageId: welcome.messageId || null,
      welcomeEmailLastError: welcome.lastError || null,
      welcomeEmailAttemptCount: Math.max(0, Number(welcome.attemptCount) || 0),
    },
  });

  return { synced: true };
}
