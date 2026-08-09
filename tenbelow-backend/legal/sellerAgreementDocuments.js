import crypto from "crypto";
import { existsSync, readFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DOCUMENTS_ROOT = path.join(__dirname, "documents");

/** Immutable registry entries — append new versions; never mutate retired rows. */
export const SELLER_AGREEMENT_REGISTRY = Object.freeze([
  Object.freeze({
    id: "seller-agreement-2026-04-24",
    agreementType: "seller_agreement",
    versionLabel: "1.0",
    versionSlug: "seller-agreement-2026-04-24",
    effectiveDate: "2026-04-24",
    isActiveForNewSellers: true,
    publishedAt: "2026-04-24T00:00:00.000Z",
    supersededAt: null,
    contentFileName: "content.txt",
    pdfFileName: "seller-agreement-2026-04-24.pdf",
    publicPath: "/legal/seller-agreement/seller-agreement-2026-04-24",
  }),
]);

export function hashAgreementContent(content) {
  return crypto.createHash("sha256").update(String(content || ""), "utf8").digest("hex");
}

function documentDirectory(documentId) {
  return path.join(DOCUMENTS_ROOT, documentId);
}

export function getSellerAgreementDocument(documentId) {
  const entry = SELLER_AGREEMENT_REGISTRY.find((row) => row.id === documentId);
  if (!entry) return null;

  const contentPath = path.join(documentDirectory(entry.id), entry.contentFileName);
  if (!existsSync(contentPath)) {
    throw new Error(`Seller agreement content missing for ${entry.id}`);
  }

  const content = readFileSync(contentPath, "utf8");
  const documentHash = hashAgreementContent(content);
  const pdfPath = path.join(documentDirectory(entry.id), entry.pdfFileName);
  const pdfAvailable = existsSync(pdfPath);

  return {
    ...entry,
    content,
    contentPath,
    documentHash,
    pdfPath: pdfAvailable ? pdfPath : null,
    pdfAvailable,
  };
}

export function getActiveSellerAgreementDocument() {
  const active = SELLER_AGREEMENT_REGISTRY.find((row) => row.isActiveForNewSellers && !row.supersededAt);
  if (!active) {
    throw new Error("No active seller agreement document configured");
  }
  return getSellerAgreementDocument(active.id);
}

export function buildAgreementPublicURL(documentId, backendBaseUrl) {
  const entry = SELLER_AGREEMENT_REGISTRY.find((row) => row.id === documentId);
  if (!entry) return null;
  const base = String(backendBaseUrl || "").replace(/\/$/, "");
  return `${base}${entry.publicPath}`;
}

export function buildSellerAgreementAcceptanceRecord({
  sellerId,
  email,
  legalName,
  document,
  source = "seller_registration",
}) {
  const acceptedAt = new Date().toISOString();
  const acceptanceId = crypto.randomUUID();

  return {
    acceptanceId,
    sellerId,
    agreementType: document.agreementType,
    documentId: document.id,
    version: document.versionSlug,
    versionLabel: document.versionLabel,
    documentHash: document.documentHash,
    acceptedAt,
    sellerEmail: String(email || "").trim().toLowerCase(),
    sellerLegalName: String(legalName || "").trim(),
    source,
    sellerAgreement: {
      accepted: true,
      acceptedAt,
      version: document.versionSlug,
      agreementType: document.agreementType,
      documentId: document.id,
      documentHash: document.documentHash,
      versionLabel: document.versionLabel,
      legalNameAtAcceptance: String(legalName || "").trim(),
      emailAtAcceptance: String(email || "").trim().toLowerCase(),
      acceptanceId,
    },
    welcomeEmail: {
      status: "pending",
      sentAt: null,
      messageId: null,
      lastError: null,
      attemptCount: 0,
    },
  };
}

export function normalizeSellerAgreementFields(record = {}) {
  const agreement = record.sellerAgreement || {};
  return {
    accepted: agreement.accepted === true,
    acceptedAt: agreement.acceptedAt || null,
    version: agreement.version || agreement.documentId || "seller-agreement-2026-04-24",
    agreementType: agreement.agreementType || "seller_agreement",
    documentId: agreement.documentId || agreement.version || "seller-agreement-2026-04-24",
    documentHash: agreement.documentHash || null,
    versionLabel: agreement.versionLabel || null,
    legalNameAtAcceptance: agreement.legalNameAtAcceptance || null,
    emailAtAcceptance: agreement.emailAtAcceptance || null,
    acceptanceId: agreement.acceptanceId || null,
  };
}

export function normalizeSellerWelcomeEmailFields(record = {}) {
  const welcome = record.welcomeEmail || {};
  return {
    status: welcome.status || (welcome.sentAt ? "sent" : "pending"),
    sentAt: welcome.sentAt || null,
    messageId: welcome.messageId || null,
    lastError: welcome.lastError || null,
    attemptCount: Math.max(0, Number(welcome.attemptCount) || 0),
  };
}
