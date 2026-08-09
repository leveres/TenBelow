#!/usr/bin/env node
import "dotenv/config";
import { syncLegalAgreementDocumentsToPrisma } from "../db/repositories/legalAgreementRepository.js";
import { getActiveSellerAgreementDocument } from "../legal/sellerAgreementDocuments.js";

async function main() {
  const document = getActiveSellerAgreementDocument();
  console.log(`Active seller agreement: ${document.id} (hash ${document.documentHash.slice(0, 12)}…)`);
  const result = await syncLegalAgreementDocumentsToPrisma();
  console.log("Prisma legal document sync:", result);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
