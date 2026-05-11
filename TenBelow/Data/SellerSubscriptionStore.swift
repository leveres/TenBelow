import Combine
import Foundation
import StoreKit

@MainActor
final class SellerSubscriptionStore: ObservableObject {
    struct EntitlementSnapshot: Codable, Equatable {
        let productId: String
        let hasActiveSubscription: Bool
        let expiresAt: Date?
        let transactionId: String?
        let originalTransactionId: String?
        let checkedAt: Date

        /// No default for `productId` in the signature avoids evaluating `AppConstants` in a nonisolated default-argument context.
        static func inactive(checkedAt: Date = .now) -> EntitlementSnapshot {
            inactive(productId: AppConstants.sellerSubscriptionProductID, checkedAt: checkedAt)
        }

        static func inactive(productId: String, checkedAt: Date = .now) -> EntitlementSnapshot {
            EntitlementSnapshot(
                productId: productId,
                hasActiveSubscription: false,
                expiresAt: nil,
                transactionId: nil,
                originalTransactionId: nil,
                checkedAt: checkedAt
            )
        }
    }

    @Published private(set) var product: StoreKit.Product?
    @Published private(set) var entitlement: EntitlementSnapshot
    @Published private(set) var remoteStatus: SellerMembershipStatusResponse?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private let isPreview: Bool
    private var transactionUpdatesTask: Task<Void, Never>?
    private let iso8601Formatter = ISO8601DateFormatter()

    init(
        previewSnapshot: EntitlementSnapshot? = nil,
        previewStatus: SellerMembershipStatusResponse? = nil
    ) {
        if let previewSnapshot {
            entitlement = previewSnapshot
            remoteStatus = previewStatus
            isPreview = true
            return
        }

        entitlement = .inactive()
        remoteStatus = nil
        isPreview = false
        transactionUpdatesTask = observeTransactionUpdates()

        Task {
            await refresh()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    /// StoreKit (App Store) **or** server-backed Stripe subscription from `GET /seller-membership-status`.
    var hasActiveSubscription: Bool {
        entitlement.hasActiveSubscription || (remoteStatus?.hasActiveSubscription == true)
    }

    var productName: String {
        product?.displayName ?? "Seller Membership"
    }

    var displayPrice: String {
        product?.displayPrice ?? AppConstants.sellerSubscriptionFallbackPrice
    }

    var renewalDescription: String {
        guard let expiresAt = entitlement.expiresAt else {
            return hasActiveSubscription
                ? "Your membership is active and ready for uploads."
                : "Start your membership to unlock seller uploads and weekly drop submissions."
        }

        let formattedDate = expiresAt.formatted(date: .abbreviated, time: .omitted)
        return hasActiveSubscription
            ? "Active through \(formattedDate)"
            : "Your last recorded expiration was \(formattedDate)"
    }

    var syncDescription: String {
        guard let remoteStatus else {
            return sellerId.isEmpty
                ? "Finish your seller account first so the app can sync your membership."
                : "Membership sync will update after the next refresh."
        }

        if remoteStatus.hasActiveSubscription {
            if let expiresAt = remoteStatus.expiresAt {
                return "Synced to your seller account until \(formattedServerDate(expiresAt))."
            }
            return "Synced to your seller account."
        }

        return "Your seller account is waiting for an active membership."
    }

    func refresh() async {
        guard !isPreview else { return }

        errorMessage = nil
        isRefreshing = true
        await loadProduct()

        let snapshot = await currentEntitlementSnapshot()
        entitlement = snapshot
        await syncMembership(snapshot)
        isRefreshing = false
        clearDeferredMembershipReminderIfNeeded()
    }

    private func clearDeferredMembershipReminderIfNeeded() {
        guard hasActiveSubscription else { return }
        UserDefaults.standard.set(false, forKey: "sellerSkippedMembershipAtOnboarding")
    }

    /// Presents the **system** App Store subscription sheet via StoreKit (`Product.purchase()`). In-app membership is sold through Apple only.
    func purchaseMembership() async {
        guard !isPreview else { return }

        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        await loadProduct()
        await purchaseMembershipViaStoreKit()
    }

    private func purchaseMembershipViaStoreKit() async {
        guard let product else {
            errorMessage = "We couldn't load the seller membership from the App Store yet."
            await refresh()
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                await transaction.finish()
                await refresh()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Your purchase is pending approval. We'll refresh as soon as Apple confirms it."
                await refresh()
            @unknown default:
                errorMessage = "We couldn't complete the membership purchase."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard !isPreview else { return }

        errorMessage = nil
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var sellerId: String {
        UserDefaults.standard.string(forKey: "sellerSellerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await StoreKit.Product.products(for: [AppConstants.sellerSubscriptionProductID])
            product = products.first

            if product == nil {
                errorMessage = "The seller membership product isn't available yet. Confirm the App Store Connect product ID matches the app."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currentEntitlementSnapshot() async -> EntitlementSnapshot {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verifiedTransaction(from: result)
                guard transaction.productID == AppConstants.sellerSubscriptionProductID else { continue }
                guard transaction.revocationDate == nil else { continue }

                if let expirationDate = transaction.expirationDate, expirationDate < .now {
                    continue
                }

                return EntitlementSnapshot(
                    productId: transaction.productID,
                    hasActiveSubscription: true,
                    expiresAt: transaction.expirationDate,
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    checkedAt: .now
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        return .inactive(checkedAt: .now)
    }

    private func syncMembership(_ snapshot: EntitlementSnapshot) async {
        guard !sellerId.isEmpty else {
            remoteStatus = nil
            return
        }

        do {
            remoteStatus = try await SellerAPI.syncMembership(
                SellerMembershipSyncRequest(
                    sellerId: sellerId,
                    productId: snapshot.productId,
                    isActive: snapshot.hasActiveSubscription,
                    expiresAt: snapshot.expiresAt.map { iso8601Formatter.string(from: $0) },
                    transactionId: snapshot.transactionId,
                    originalTransactionId: snapshot.originalTransactionId
                )
            )
        } catch {
            errorMessage = error.localizedDescription

            do {
                remoteStatus = try await SellerAPI.membershipStatus(sellerId: sellerId)
            } catch {
                remoteStatus = nil
            }
        }
    }

    private func formattedServerDate(_ value: String) -> String {
        guard let date = iso8601Formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            let transaction = try verifiedTransaction(from: result)
            await transaction.finish()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw NSError(
                domain: "SellerSubscriptionStore",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Apple couldn't verify this subscription transaction."]
            )
        }
    }
}

#if DEBUG
extension SellerSubscriptionStore {
    static var previewActive: SellerSubscriptionStore {
        SellerSubscriptionStore(
            previewSnapshot: EntitlementSnapshot(
                productId: AppConstants.sellerSubscriptionProductID,
                hasActiveSubscription: true,
                expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: .now),
                transactionId: "preview-transaction",
                originalTransactionId: "preview-original-transaction",
                checkedAt: .now
            ),
            previewStatus: SellerMembershipStatusResponse(
                sellerId: "seller_preview",
                requiresSubscription: true,
                hasActiveSubscription: true,
                productId: AppConstants.sellerSubscriptionProductID,
                source: "app_store",
                expiresAt: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now),
                lastSyncedAt: ISO8601DateFormatter().string(from: .now)
            )
        )
    }

    static var previewInactive: SellerSubscriptionStore {
        SellerSubscriptionStore(
            previewSnapshot: .inactive(),
            previewStatus: SellerMembershipStatusResponse(
                sellerId: "seller_preview",
                requiresSubscription: true,
                hasActiveSubscription: false,
                productId: AppConstants.sellerSubscriptionProductID,
                source: "app_store",
                expiresAt: nil,
                lastSyncedAt: ISO8601DateFormatter().string(from: .now)
            )
        )
    }
}
#endif
