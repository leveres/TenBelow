//
//  SellerProfileView.swift
//  TenBelow
//

import SwiftUI

struct SellerProfileView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @AppStorage("sellerBusinessName") private var businessName = ""
    @AppStorage("sellerAccountCreated") private var accountCreated = false

    @State private var status: SellerStatusResponse?
    @State private var dropSubmissions: SellerSubmissionsResponse?
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var isRegistered: Bool { accountCreated && !sellerId.isEmpty }
    private var isOnboarded: Bool { status?.onboardingComplete == true }

    var body: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingXL) {

                // Header
                VStack(spacing: TBTheme.spacingMD) {
                    Image(systemName: isRegistered ? "storefront.fill" : "storefront")
                        .font(.system(size: 48))
                        .foregroundStyle(TBTheme.icyBlue)

                    Text(isRegistered ? businessName.isEmpty ? "Seller Account" : businessName : "Become a Seller")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.frostTitleGradient)

                    if isRegistered, let s = status {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(s.onboardingComplete ? .green : .orange)
                                .frame(width: 8, height: 8)
                            Text(s.onboardingComplete ? "Active" : "Onboarding incomplete")
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

                previewSection
            }
            .padding()
        }
        .background(TBTheme.cloudWhite)
        .navigationTitle("Seller Profile")
        .task {
            if isRegistered { await refreshStatus() }
        }
    }

    // MARK: - Registration form

    @ViewBuilder
    private var registrationForm: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            Text("Start selling on TenBelow — list 3D-printed products for $10 & under.")
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
                if isCreating {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding()
                } else {
                    Text("Create Seller Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sellerId.isEmpty || sellerEmail.isEmpty || isCreating)
        }
    }

    // MARK: - Registered seller view

    @ViewBuilder
    private var registeredView: some View {
        VStack(spacing: TBTheme.spacingMD) {

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
            .background(TBTheme.cardGradient)
            .cornerRadius(TBTheme.radiusLG)
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
            )

            // Onboarding incomplete — show button to finish
            if let s = status, !s.onboardingComplete {
                Button {
                    Task { await openOnboarding() }
                } label: {
                    Label("Complete Onboarding", systemImage: "arrow.right.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            // Weekly Drop (only for fully onboarded sellers)
            if isOnboarded {
                NavigationLink {
                    DropSubmitView()
                } label: {
                    HStack {
                        Image(systemName: "flame.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)

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
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(TBTheme.spacingMD)
                    .background(TBTheme.cardGradient)
                    .cornerRadius(TBTheme.radiusLG)
                    .overlay(
                        RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                            .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Stripe Express Dashboard
            if isOnboarded {
                Button {
                    Task { await openDashboard() }
                } label: {
                    Label("Open Stripe Dashboard", systemImage: "chart.bar.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(GlassPillButtonStyle(isFinal: true))
            }

            // Refresh
            Button {
                Task { await refreshStatus() }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .foregroundStyle(TBTheme.skyBlue)
            .disabled(isLoading)
        }
    }

    // MARK: - Preview section (no server required)

    @ViewBuilder
    private var previewSection: some View {
        VStack(spacing: TBTheme.spacingMD) {
            Divider().padding(.vertical, TBTheme.spacingSM)

            Text("Preview Mode")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("See the new seller views with sample data — no server needed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            NavigationLink {
                SellerDashboardView(seller: .sample, products: MockData.products)
            } label: {
                Label("Seller Dashboard", systemImage: "rectangle.grid.1x2.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(SecondaryCTAButtonStyle())

            NavigationLink {
                PublicSellerProfileView(seller: .sample, products: MockData.products)
            } label: {
                Label("Public Store Profile", systemImage: "person.crop.rectangle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(SecondaryCTAButtonStyle())
        }
    }

    private var dropSlotText: String {
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
        do {
            let response = try await SellerAPI.createAccount(
                sellerId: sellerId,
                email: sellerEmail,
                businessName: businessName.isEmpty ? nil : businessName
            )
            accountCreated = true
            if let url = URL(string: response.onboardingUrl) {
                openURL(url)
            }
            await refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }

    private func refreshStatus() async {
        guard isRegistered else { return }
        isLoading = true
        do {
            status = try await SellerAPI.onboardingStatus(sellerId: sellerId)
            if status?.onboardingComplete == true {
                dropSubmissions = try await DropAPI.mySubmissions(sellerId: sellerId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openOnboarding() async {
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
        do {
            let response = try await SellerAPI.dashboardLink(sellerId: sellerId)
            if let url = URL(string: response.dashboardUrl) {
                openURL(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

#Preview {
    NavigationStack {
        SellerProfileView()
    }
    .environmentObject(CartStore())
    .environmentObject(CatalogStore())
}
