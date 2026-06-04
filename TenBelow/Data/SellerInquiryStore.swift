import Foundation
import Combine

@MainActor
final class SellerInquiryStore: ObservableObject {
    @Published private(set) var buyerThreads: [SellerInquiryThread] = []
    @Published private(set) var sellerThreads: [SellerInquiryThread] = []
    @Published var inquiryError: String?

    func refreshBuyerThreads() async {
        inquiryError = nil
        do {
            buyerThreads = try await SellerInquiryAPI.fetchBuyerThreads()
        } catch {
            inquiryError = error.localizedDescription
        }
    }

    func refreshSellerThreads() async {
        inquiryError = nil
        do {
            sellerThreads = try await SellerInquiryAPI.fetchSellerThreads()
        } catch {
            inquiryError = error.localizedDescription
        }
    }

    func fetchThread(sellerId: String, buyerEmail: String? = nil) async -> [OrderSupportMessage] {
        inquiryError = nil

        guard MarketplaceAuthSession.hasAuthenticatedSession else {
            inquiryError = "Sign in to your account to send and receive messages."
            return cachedInquiryMessages(sellerId: sellerId, buyerEmail: buyerEmail)
        }

        await MarketplaceAuthSession.syncAfterIdentityChange()

        do {
            return try await SellerInquiryAPI.fetchThread(sellerId: sellerId, buyerEmail: buyerEmail)
        } catch {
            inquiryError = APIErrorMessage.userFacing(error)
            if let buyerEmail, !buyerEmail.isEmpty {
                return sellerThreads.first(where: {
                    $0.sellerId == sellerId && $0.buyerEmail.lowercased() == buyerEmail.lowercased()
                })?.messages ?? []
            }
            return cachedInquiryMessages(sellerId: sellerId, buyerEmail: buyerEmail)
        }
    }

    private func cachedInquiryMessages(sellerId: String, buyerEmail: String?) -> [OrderSupportMessage] {
        thread(for: sellerId, buyerEmail: buyerEmail)?.messages ?? []
    }

    func sendMessage(
        sellerId: String,
        text: String,
        senderName: String? = nil,
        buyerEmail: String? = nil
    ) async -> [OrderSupportMessage] {
        inquiryError = nil

        guard MarketplaceAuthSession.hasAuthenticatedSession else {
            inquiryError = "Sign in to your account to send and receive messages."
            return cachedInquiryMessages(sellerId: sellerId, buyerEmail: buyerEmail)
        }

        await MarketplaceAuthSession.syncAfterIdentityChange()

        do {
            let messages = try await SellerInquiryAPI.sendMessage(
                sellerId: sellerId,
                text: text,
                senderName: senderName,
                buyerEmail: buyerEmail
            )
            await refreshCachedThread(sellerId: sellerId, buyerEmail: buyerEmail, messages: messages)
            return messages
        } catch {
            inquiryError = APIErrorMessage.userFacing(error)
            return cachedInquiryMessages(sellerId: sellerId, buyerEmail: buyerEmail)
        }
    }

    func thread(for sellerId: String, buyerEmail: String? = nil) -> SellerInquiryThread? {
        let sid = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let buyerEmail, !buyerEmail.isEmpty {
            let email = buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return sellerThreads.first {
                $0.sellerId == sid && $0.buyerEmail.lowercased() == email
            }
        }
        return buyerThreads.first { $0.sellerId == sid }
    }

    private func refreshCachedThread(sellerId: String, buyerEmail: String?, messages: [OrderSupportMessage]) async {
        if let buyerEmail, !buyerEmail.isEmpty {
            await refreshSellerThreads()
            return
        }
        await refreshBuyerThreads()
        if buyerThreads.first(where: { $0.sellerId == sellerId }) == nil, !messages.isEmpty {
            await refreshBuyerThreads()
        }
    }
}
