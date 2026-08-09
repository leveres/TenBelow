import { sendSellerWelcomeEmail } from "./sellerWelcomeEmail.js";

export async function deliverSellerWelcomeEmailIfNeeded({
  sellerId,
  loadSellersFile,
  saveSellersFile,
  sendTransactionalEmail,
  upsertSellerAgreementAcceptanceToPrisma,
}) {
  const sellers = loadSellersFile();
  const seller = sellers[sellerId];
  if (!seller?.sellerAgreement?.accepted) {
    return { skipped: true, reason: "agreement_not_accepted" };
  }

  seller.welcomeEmail = seller.welcomeEmail || {
    status: "pending",
    sentAt: null,
    messageId: null,
    lastError: null,
    attemptCount: 0,
  };

  if (seller.welcomeEmail.status === "sent") {
    return { skipped: true, reason: "already_sent" };
  }

  seller.welcomeEmail.attemptCount = Math.max(0, Number(seller.welcomeEmail.attemptCount) || 0) + 1;
  saveSellersFile(sellers);

  try {
    const result = await sendSellerWelcomeEmail({
      seller,
      sellerId,
      sendTransactionalEmail,
      agreementAcceptance: {
        documentId: seller.sellerAgreement.documentId,
        version: seller.sellerAgreement.version,
        versionLabel: seller.sellerAgreement.versionLabel,
        acceptedAt: seller.sellerAgreement.acceptedAt,
        sellerLegalName: seller.sellerAgreement.legalNameAtAcceptance || seller.legalName,
      },
    });

    const refreshed = loadSellersFile();
    const updated = refreshed[sellerId];
    if (updated) {
      updated.welcomeEmail = {
        status: "sent",
        sentAt: new Date().toISOString(),
        messageId: result.messageId || null,
        lastError: null,
        attemptCount: updated.welcomeEmail?.attemptCount || seller.welcomeEmail.attemptCount,
      };
      saveSellersFile(refreshed);
      if (typeof upsertSellerAgreementAcceptanceToPrisma === "function") {
        await upsertSellerAgreementAcceptanceToPrisma(sellerId, updated);
      }
    }

    return { sent: true, messageId: result.messageId || null };
  } catch (error) {
    const refreshed = loadSellersFile();
    const updated = refreshed[sellerId];
    if (updated) {
      updated.welcomeEmail = {
        status: "failed",
        sentAt: updated.welcomeEmail?.sentAt || null,
        messageId: updated.welcomeEmail?.messageId || null,
        lastError: String(error?.message || error || "Welcome email failed"),
        attemptCount: updated.welcomeEmail?.attemptCount || seller.welcomeEmail.attemptCount,
      };
      saveSellersFile(refreshed);
      if (typeof upsertSellerAgreementAcceptanceToPrisma === "function") {
        await upsertSellerAgreementAcceptanceToPrisma(sellerId, updated);
      }
    }

    console.error(`seller welcome email failed sellerId=${sellerId}:`, error?.message || error);
    return { sent: false, error: String(error?.message || error || "Welcome email failed") };
  }
}

export function queueSellerWelcomeEmail(deliveryArgs) {
  setImmediate(() => {
    deliverSellerWelcomeEmailIfNeeded(deliveryArgs).catch((error) => {
      console.error("seller welcome email queue error:", error?.message || error);
    });
  });
}
