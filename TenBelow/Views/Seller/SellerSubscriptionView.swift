import SwiftUI

struct SellerSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore

    @AppStorage("sellerBusinessName") private var businessName = ""
    @AppStorage("sellerSellerId") private var sellerId = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                    heroCard
                    benefitsCard
                    purchaseCard

                    if let message = sellerSubscription.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(TBTheme.spacingLG)
            }
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationTitle("Seller Membership")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await sellerSubscription.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await sellerSubscription.refresh() }
            }
        }
    }

    private var heroCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(sellerSubscription.productName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                } icon: {
                    Image(systemName: sellerSubscription.hasActiveSubscription ? "checkmark.seal.fill" : "storefront")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(sellerSubscription.hasActiveSubscription ? .green : TBTheme.accent)
                }

                Text(sellerSubscription.hasActiveSubscription ? "Membership active" : "\(sellerSubscription.displayPrice) / month")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(sellerSubscription.hasActiveSubscription ? .green : TBTheme.accent)

                Text(sellerSubscription.renewalDescription)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)

                Text(sellerSubscription.syncDescription)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)

                if !businessName.isEmpty || !sellerId.isEmpty {
                    Text("Seller account: \(businessName.isEmpty ? sellerId : businessName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.88))
                }
            }
        }
    }

    private var benefitsCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Included with membership")
                    .font(.tbHeadline)
                    .foregroundStyle(TBTheme.deepSky)

                benefitRow(icon: "plus.circle.fill", title: "Product uploads", detail: "Create and update listings in TenBelow.")
                benefitRow(icon: "shippingbox.fill", title: "Weekly Drop", detail: "Submit weekend listings when your membership is active.")
                benefitRow(icon: "checkmark.seal.fill", title: "Billed through Apple", detail: "Subscriptions use your Apple ID. Manage or cancel in Settings → Apple Account → Subscriptions.")
            }
        }
    }

    private var purchaseCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(sellerSubscription.hasActiveSubscription ? "Membership tools" : "Activate membership")
                    .font(.tbHeadline)
                    .foregroundStyle(TBTheme.deepSky)

                Text(sellerSubscription.hasActiveSubscription
                     ? "You’re ready to upload products and manage inventory."
                     : "Tap below to use your Apple ID and the App Store subscription sheet. You can restore past purchases or manage the subscription from this screen.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await sellerSubscription.purchaseMembership() }
                } label: {
                    if sellerSubscription.isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(sellerSubscription.hasActiveSubscription ? "Membership Active" : "Start for \(sellerSubscription.displayPrice) / month")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sellerSubscription.hasActiveSubscription || sellerSubscription.isPurchasing || sellerSubscription.isLoadingProduct)
                .opacity((sellerSubscription.hasActiveSubscription || sellerSubscription.isLoadingProduct) ? 0.7 : 1)

                Button {
                    Task { await sellerSubscription.restorePurchases() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button {
                    openURL(AppConstants.manageSubscriptionsURL)
                } label: {
                    Label("Manage in App Store", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(TBTheme.deepSky)
            }
        }
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TBTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text(detail)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


