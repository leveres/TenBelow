//
//  SellerProfileView.swift
//  TenBelow
//

import SwiftUI

struct SellerProfileView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @AppStorage("sellerBusinessName") private var businessName = ""
    @AppStorage("sellerAccountCreated") private var accountCreated = false
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @AppStorage("sellerPayoutSetupDeferred") private var payoutSetupDeferred = false

    @State private var status: SellerStatusResponse?
    @State private var dropSubmissions: SellerSubmissionsResponse?
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showDropSubmit = false

    private var isRegistered: Bool { accountCreated && !sellerId.isEmpty }
    private var isOnboarded: Bool { status?.onboardingComplete == true }
    private var isShowingOperationOverlay: Bool { isCreating }
    private var storeTabIndex: Int { 1 }
    private var isTrustedTesterVerified: Bool {
        if let status {
            return status.trustedTesterVerified
        }
        return SellerVerificationStore.isTrustedTesterVerified(sellerId: sellerId)
    }
    private var verificationSalesCount: Int {
        status?.completedSalesCount ?? localPreviewSeller.orderCount
    }
    private var verificationPositiveReviews: Int {
        status?.positiveReviewCount ?? localPreviewSeller.positiveReviewCount
    }
    private var verificationRating: Double {
        status?.averageRating ?? localPreviewSeller.rating
    }
    private var verificationActiveDays: Int {
        status?.activeDays ?? localPreviewSeller.activeDays
    }
    private var hasEarnedVerificationByPolicy: Bool {
        verificationSalesCount >= SellerVerificationPolicy.minSuccessfulSales &&
        verificationPositiveReviews >= SellerVerificationPolicy.minPositiveReviews &&
        verificationRating >= SellerVerificationPolicy.minAverageRating &&
        verificationActiveDays >= SellerVerificationPolicy.minActiveDays
    }
    private var shouldShowVerificationBadge: Bool {
        isTrustedTesterVerified || hasEarnedVerificationByPolicy || localPreviewSeller.showsVerifiedBadge
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var localPreviewSeller: SellerProfile {
        resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
            remoteProfiles: catalog.sellerProfiles
        ) ?? .previewProfile(sellerId: sellerId, businessName: businessName)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: TBTheme.spacingXL) {

                    // Header
                    VStack(spacing: TBTheme.spacingMD) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 96)
                            .frame(maxWidth: .infinity)

                        Text(isRegistered ? businessName.isEmpty ? "Seller Account" : businessName : "Become a Seller")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky.opacity(0.94))
                            .multilineTextAlignment(.center)

                        if isRegistered, let s = status {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(s.onboardingComplete ? .green : .orange)
                                    .frame(width: 8, height: 8)
                                Text(s.onboardingComplete ? "Payouts ready" : "Payout setup needed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(s.onboardingComplete ? .green : .orange)
                            }
                        }
                    }
                    .padding(.top, TBTheme.spacingXL)

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if isRegistered {
                        registeredView
                    } else {
                        registrationForm
                    }
                }
                .padding()
            }
            .background(TBFrostBackground())

            if isShowingOperationOverlay {
                AppOperationOverlay(
                    title: "Creating Seller Account",
                    subtitle: "Setting up your seller account."
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }

            if isLoading && !isCreating {
                ProgressView()
                    .controlSize(.regular)
                    .tint(TBTheme.deepSky)
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .zIndex(1)
            }
        }
        .navigationTitle("Seller Profile")
        .task {
            if isRegistered { await refreshStatus() }
            await sellerSubscription.refresh()
        }
        .onChange(of: status?.onboardingComplete) { _, complete in
            if complete == true {
                payoutSetupDeferred = false
            }
        }
        .navigationDestination(isPresented: $showDropSubmit) {
            DropSubmitView()
        }
    }

    // MARK: - Registration form

    @ViewBuilder
    private var registrationForm: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            Text("Start selling on TenBelow. List 3D-printed products for $10 and under.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            TextField("Seller ID (e.g. my_shop)", text: $sellerId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            TextField("Email", text: $sellerEmail)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)

            TextField("Business name (optional)", text: $businessName)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await createAccount() }
            } label: {
                Text(isCreating ? "Creating account..." : "Create seller account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sellerId.isEmpty || sellerEmail.isEmpty || isCreating)
        }
    }

    // MARK: - Registered seller view

    @ViewBuilder
    private var registeredView: some View {
        VStack(spacing: TBTheme.spacingMD) {
            if sellerPreviewMode {
                Text("Offline preview — the seller server didn’t respond; you’re seeing local demo data. Use a Debug build from Xcode, or connect the backend for a real account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            // Account details card
            VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                DetailRow(label: "Seller ID", value: sellerId)
                DetailRow(label: "Email", value: sellerEmail)
                if !businessName.isEmpty {
                    DetailRow(label: "Business", value: businessName)
                }
                if let s = status {
                    DetailRow(label: "Charges", value: s.chargesEnabled ? "Enabled" : "Pending")
                    DetailRow(label: "Payouts", value: s.payoutsEnabled ? "Enabled" : "Pending")
                }
            }
            .padding(TBTheme.spacingMD)
            .background(Color.white.opacity(0.84))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.035), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Verification")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if shouldShowVerificationBadge {
                        Label("Verified", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("In progress")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                if isTrustedTesterVerified {
                    Text("Trusted TestFlight collaborator status applied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Automatic thresholds: \(SellerVerificationPolicy.minSuccessfulSales)+ successful sales, \(SellerVerificationPolicy.minPositiveReviews)+ positive reviews (4.0★+), and \(SellerVerificationPolicy.minActiveDays)+ days active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits {
                    HStack(spacing: 10) {
                        verificationMiniPill(title: "Sales", value: "\(verificationSalesCount)/\(SellerVerificationPolicy.minSuccessfulSales)")
                        verificationMiniPill(title: "Positive", value: "\(verificationPositiveReviews)/\(SellerVerificationPolicy.minPositiveReviews)")
                        verificationMiniPill(title: "Rating", value: String(format: "%.1f", verificationRating))
                        verificationMiniPill(title: "Days", value: "\(verificationActiveDays)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            verificationMiniPill(title: "Sales", value: "\(verificationSalesCount)/\(SellerVerificationPolicy.minSuccessfulSales)")
                            verificationMiniPill(title: "Positive", value: "\(verificationPositiveReviews)/\(SellerVerificationPolicy.minPositiveReviews)")
                        }
                        HStack(spacing: 10) {
                            verificationMiniPill(title: "Rating", value: String(format: "%.1f", verificationRating))
                            verificationMiniPill(title: "Days", value: "\(verificationActiveDays)")
                        }
                    }
                }
            }
            .padding(TBTheme.spacingMD)
            .background(Color.white.opacity(0.84))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.03), radius: 6, y: 3)

            // Stripe Connect payout setup — optional until sellers need payouts (separate from App Store membership).
            if let s = status, !s.onboardingComplete {
                if payoutSetupDeferred {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Payout setup is still needed before you can receive transfers from orders. Finish any time here or in Settings → Manage payouts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task { await openPayoutSetup() }
                        } label: {
                            Text("Set up payouts")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            payoutSetupDeferred = false
                        } label: {
                            Text("More options")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TBTheme.deepSky)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(TBTheme.spacingMD)
                    .background(Color.white.opacity(0.84))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 10) {
                        Button {
                            Task { await openPayoutSetup() }
                        } label: {
                            Label("Set up payouts", systemImage: "banknote")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityHint("Opens secure payout setup in Safari. Membership is managed separately in the App Store.")

                        Button {
                            payoutSetupDeferred = true
                        } label: {
                            Text("I’ll set this up later")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TBTheme.deepSky)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Weekly Drop (only for fully onboarded sellers)
            if isOnboarded {
                Button {
                    showDropSubmit = true
                } label: {
                    HStack {
                        Image(systemName: "flame")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                            .symbolRenderingMode(.hierarchical)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly Drop")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                            Text(dropSlotText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let subs = dropSubmissions {
                            Text("\(subs.slotsUsed)/\(subs.slotsMax)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TBTheme.icyBlue)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(TBTheme.spacingMD)
                    .background(Color.white.opacity(0.84))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.orange.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Stripe Express Dashboard
            if isOnboarded {
                Button {
                    Task { await openDashboard() }
                } label: {
                    Label(
                        AppConstants.isStripeConfigured ? "View Stripe dashboard" : "Stripe dashboard coming soon",
                        systemImage: AppConstants.isStripeConfigured ? "chart.bar.fill" : "clock"
                    )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(GlassPillButtonStyle(isFinal: true))
                .disabled(!AppConstants.isStripeConfigured)
                .opacity(AppConstants.isStripeConfigured ? 1 : 0.78)

                if !AppConstants.isStripeConfigured {
                    Text("Connect Stripe first to enable seller payouts and dashboard access.")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }

            // Refresh
            Button {
                Task { await refreshStatus() }
            } label: {
                Label("Refresh status", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .foregroundStyle(TBTheme.skyBlue)
            .disabled(isLoading)
        }
    }

    private var dropSlotText: String {
        if !shouldShowVerificationBadge {
            return "Verification required to unlock"
        }
        guard let subs = dropSubmissions else { return "Submit premium products" }
        if subs.isActive {
            return subs.slotsUsed == 0 ? "Drop is open — submit products!" : "\(subs.slotsUsed) product\(subs.slotsUsed == 1 ? "" : "s") submitted this week"
        }
        if let next = subs.nextDropAt {
            return "Next drop \(DropCountdown.timeLeft(until: next))"
        }
        return "Submit premium products"
    }

    // MARK: - Actions

    private func createAccount() async {
        errorMessage = nil
        isCreating = true
        let starterProfile = SellerProfile.starterProfile(
            sellerId: sellerId,
            businessName: businessName
        )
        do {
            try await SellerAPI.createAccount(
                sellerId: sellerId,
                email: sellerEmail,
                businessName: businessName.isEmpty ? nil : businessName
            )
            sellerPreviewMode = false
            accountCreated = true
            userRole = "seller"
            pendingLaunchTab = storeTabIndex
            starterProfile.storeLocally()
            catalog.upsertSellerProfile(starterProfile)
            await MarketplaceAuthSession.syncAfterIdentityChange()
            _ = try? await MarketplaceAuthSession.ensureSellerSessionReady()
            await refreshStatus()
            await sellerSubscription.refresh()
        } catch {
            if SellerAPI.isSellerAlreadyExistsError(error) {
                sellerPreviewMode = false
                accountCreated = true
                userRole = "seller"
                pendingLaunchTab = storeTabIndex
                starterProfile.storeLocally()
                catalog.upsertSellerProfile(starterProfile)
                await MarketplaceAuthSession.syncAfterIdentityChange()
                _ = try? await MarketplaceAuthSession.ensureSellerSessionReady()
                await refreshStatus()
                await sellerSubscription.refresh()
                isCreating = false
                return
            }

            accountCreated = false
            sellerPreviewMode = false
            status = nil
            dropSubmissions = nil
            errorMessage = "We couldn't create your seller account right now. Connect the backend and try again. \(error.localizedDescription)"
            await sellerSubscription.refresh()
        }
        isCreating = false
    }

    private func refreshStatus() async {
        guard isRegistered else { return }

        if sellerPreviewMode {
            status = .preview(sellerId: sellerId)
            dropSubmissions = .preview(sellerId: sellerId)
            errorMessage = nil
            isLoading = false
            await sellerSubscription.refresh()
            return
        }

        isLoading = true
        do {
            status = try await SellerAPI.onboardingStatus(sellerId: sellerId)
            if let profile = try? await SellerAPI.fetchProfile(sellerId: sellerId) {
                profile.storeLocally()
                catalog.upsertSellerProfile(profile)
                if businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    businessName = profile.displayName
                }
            }
            if let status {
                // Trusted TestFlight collaborators can be force-verified via backend flag.
                SellerVerificationStore.setTrustedTesterVerified(status.trustedTesterVerified, sellerId: sellerId)
            }
            if status?.onboardingComplete == true {
                dropSubmissions = try await DropAPI.mySubmissions(sellerId: sellerId)
            }
            await sellerSubscription.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openPayoutSetup() async {
        if sellerPreviewMode {
            errorMessage = "Preview mode is active, so payout setup in the browser is skipped."
            return
        }

        do {
            let response = try await SellerAPI.onboardingLink(sellerId: sellerId)
            if let url = URL(string: response.onboardingUrl) {
                openURL(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDashboard() async {
        guard AppConstants.isStripeConfigured else {
            errorMessage = "Stripe dashboard will be available after Stripe is connected."
            return
        }

        do {
            let response = try await SellerAPI.dashboardLink(sellerId: sellerId)
            if let url = URL(string: response.dashboardUrl) {
                openURL(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verificationMiniPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TBTheme.deepSky)
        }
    }
}

