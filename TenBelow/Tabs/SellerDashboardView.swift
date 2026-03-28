//
//  SellerDashboardView.swift
//  TenBelow
//

import SwiftUI

struct SellerDashboardView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    let products: [Product]
    @State private var seller: SellerProfile
    @State private var showSubscriptionCenter = false
    @State private var showAddProductFlow = false
    private var shippingSnapshot: SellerDashboardShippingSnapshot { .load() }
    private var policySnapshot: SellerDashboardPolicySnapshot { .load() }
    private var payoutSnapshot: SellerDashboardPayoutSnapshot { .load() }

    init(seller: SellerProfile, products: [Product]) {
        self.products = products
        _seller = State(initialValue: seller)
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProducts: [Product] {
        let currentSellerProducts = storefrontProducts.filter { $0.sellerId == seller.id }
        return currentSellerProducts.isEmpty ? products : currentSellerProducts
    }

    private var resolvedCurrentSeller: SellerProfile {
        resolvedSellerProfile(
            sellerId: seller.id,
            storefrontProducts: sellerProducts,
            remoteProfiles: catalog.sellerProfiles
        ) ?? seller
    }

    private var sellerProfileFingerprint: String {
        [
            resolvedCurrentSeller.displayName,
            resolvedCurrentSeller.handle,
            resolvedCurrentSeller.location,
            resolvedCurrentSeller.websiteURL?.absoluteString ?? "",
            "\(resolvedCurrentSeller.productCount)",
            "\(resolvedCurrentSeller.pageViewCount)",
            "\(resolvedCurrentSeller.likeCount)"
        ].joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    headerCard
                    primaryActions
                    secondaryActions
                    settingsSection
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, 10)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 8, 14))
            }
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showAddProductFlow) {
                SellerProductsView(
                    seller: seller,
                    products: sellerProducts,
                    startInAddMode: true
                )
            }
            .sheet(isPresented: $showSubscriptionCenter) {
                SellerSubscriptionView()
            }
            .task {
                seller = resolvedCurrentSeller
                await sellerSubscription.refresh()
            }
            .onChange(of: sellerProfileFingerprint) { _, _ in
                seller = resolvedCurrentSeller
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard(cornerRadius: 22, snowfallFlakeCount: 68) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(avatarInitials)
                            .font(.subheadline.weight(.bold))
                            .fontWeight(.bold)
                            .foregroundStyle(TBTheme.deepSky)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(seller.displayName)
                            .font(.tbSectionTitle)
                            .foregroundStyle(TBTheme.deepSky)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)

                        if seller.showsVerifiedBadge {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(TBTheme.accent)
                        }

                        Spacer()

                        NavigationLink {
                            EditSellerProfileView(seller: $seller)
                        } label: {
                            Text("Edit")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.icyBlue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.72))
                                .overlay(
                                    Capsule()
                                        .stroke(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(seller.handle)
                        .font(.tbBody)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            chip(icon: "shippingbox", text: "Ships in \(shippingSnapshot.minShipDays)–\(shippingSnapshot.maxShipDays) days")
                            chip(icon: "paperplane.fill", text: seller.location)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            chip(icon: "shippingbox", text: "Ships in \(shippingSnapshot.minShipDays)–\(shippingSnapshot.maxShipDays) days")
                            chip(icon: "paperplane.fill", text: seller.location)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .shadow(color: TBTheme.deepSky.opacity(0.04), radius: 10, y: 5)
    }

    private var avatarInitials: String {
        let words = seller.displayName.split(separator: " ")
        return words.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.82))
        .overlay(
            Capsule()
                .stroke(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
        .clipShape(Capsule())
        .foregroundStyle(TBTheme.deepSky)
    }

    // MARK: - Actions

    private var primaryActions: some View {
        Button {
            if sellerSubscription.hasActiveSubscription {
                showAddProductFlow = true
            } else {
                showSubscriptionCenter = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add product")
                    .font(.tbHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [TBTheme.accent, TBTheme.deepSky],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: TBTheme.accent.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var secondaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                NavigationLink {
                    SellerProductsView(
                        seller: seller,
                        products: sellerProducts
                    )
                } label: {
                    secondaryButton(icon: "cube.box", title: "Manage products")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SellerStorePreviewView(seller: seller, products: sellerProducts)
                } label: {
                    secondaryButton(icon: "eye", title: "View store")
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                NavigationLink {
                    SellerProductsView(
                        seller: seller,
                        products: sellerProducts
                    )
                } label: {
                    secondaryButton(icon: "cube.box", title: "Manage products")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SellerStorePreviewView(seller: seller, products: sellerProducts)
                } label: {
                    secondaryButton(icon: "eye", title: "View store")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func secondaryButton(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.tbBodyStrong)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(TBTheme.deepSky)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 6, y: 3)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            GlassCard(cornerRadius: 22, snowfallFlakeCount: 56) {
                VStack(spacing: 0) {
                    NavigationLink {
                        ShippingSettingsView()
                    } label: {
                        settingsRow(icon: "shippingbox", title: "Manage shipping", subtitle: shippingRowSubtitle)
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SellerPoliciesView()
                    } label: {
                        settingsRow(icon: "doc.text", title: "Manage policies", subtitle: policyRowSubtitle)
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SupportView()
                    } label: {
                        settingsRow(icon: "questionmark.circle", title: "View support", subtitle: "Help center and contact")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        PayoutSettingsView()
                    } label: {
                        settingsRow(icon: "dollarsign.circle", title: "Manage payouts", subtitle: payoutRowSubtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var shippingRowSubtitle: String {
        "\(shippingSnapshot.primaryRegion) • \(shippingSnapshot.processingTime)"
    }

    private var policyRowSubtitle: String {
        policySnapshot.dashboardSummary
    }

    private var payoutRowSubtitle: String {
        payoutSnapshot.dashboardSummary
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                Text(subtitle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    SellerDashboardView(seller: .sample, products: MockData.products)
        .environmentObject(CatalogStore())
        .environmentObject(LocalProductStore(eventStore: CommerceEventStore()))
        .environmentObject(SellerSubscriptionStore.previewActive)
}

private enum SellerDashboardSettingsStorageKey {
    static let shipping = "sellerShippingSettingsData"
    static let policies = "sellerPolicySettingsData"
    static let payout = "sellerPayoutSettingsData"
}

private struct SellerDashboardShippingSnapshot: Codable {
    let processingTime: String
    let minShipDays: Int
    let maxShipDays: Int
    let primaryRegion: String

    static func load() -> SellerDashboardShippingSnapshot {
        if let data = UserDefaults.standard.data(forKey: SellerDashboardSettingsStorageKey.shipping),
           let saved = try? JSONDecoder().decode(SellerDashboardShippingSnapshot.self, from: data) {
            return saved
        }

        return SellerDashboardShippingSnapshot(
            processingTime: "1-2 business days",
            minShipDays: 2,
            maxShipDays: 4,
            primaryRegion: "United States"
        )
    }
}

private struct SellerDashboardPolicySnapshot: Codable {
    let acceptsReturns: Bool
    let returnWindowDays: Int
    let allowsExchanges: Bool
    let allowsCancellations: Bool
    let cancellationWindowHours: Int

    static func load() -> SellerDashboardPolicySnapshot {
        if let data = UserDefaults.standard.data(forKey: SellerDashboardSettingsStorageKey.policies),
           let saved = try? JSONDecoder().decode(SellerDashboardPolicySnapshot.self, from: data) {
            return saved
        }

        return SellerDashboardPolicySnapshot(
            acceptsReturns: true,
            returnWindowDays: 14,
            allowsExchanges: true,
            allowsCancellations: true,
            cancellationWindowHours: 12
        )
    }

    var dashboardSummary: String {
        let returnsText = acceptsReturns ? "\(returnWindowDays)-day returns" : "No returns"
        let exchangesText = allowsExchanges ? "exchanges on" : "no exchanges"
        let cancellationText = allowsCancellations ? "\(cancellationWindowHours)h cancellations" : "no cancellations"
        return "\(returnsText) • \(exchangesText) • \(cancellationText)"
    }
}

private struct SellerDashboardPayoutSnapshot: Codable {
    let schedule: String
    let emailNotificationsEnabled: Bool
    let bankName: String
    let accountLast4: String

    static func load() -> SellerDashboardPayoutSnapshot {
        if let data = UserDefaults.standard.data(forKey: SellerDashboardSettingsStorageKey.payout),
           let saved = try? JSONDecoder().decode(SellerDashboardPayoutSnapshot.self, from: data) {
            return saved
        }

        return SellerDashboardPayoutSnapshot(
            schedule: "weekly",
            emailNotificationsEnabled: true,
            bankName: "Chase",
            accountLast4: "4242"
        )
    }

    var dashboardSummary: String {
        let scheduleLabel = schedule.capitalized
        let notificationsLabel = emailNotificationsEnabled ? "email updates on" : "email updates off"
        let accountLabel = accountLast4.isEmpty ? bankName : "\(bankName) ••••\(accountLast4)"
        return "\(scheduleLabel) • \(accountLabel) • \(notificationsLabel)"
    }
}
