//
//  RolePickerView.swift
//  TenBelow
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RolePickerView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = BuyerCheckoutPreference.guest.rawValue
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @AppStorage("sellerBusinessName") private var sellerBusinessName = ""
    @AppStorage("sellerAccountCreated") private var sellerAccountCreated = false
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    private let startsInSellerAccount: Bool
    private let sellerEntryMode: SellerAccountEntryMode
    @State private var step: RolePickerStep = .roleSelection
    @State private var buyerNameInput = ""
    @State private var buyerEmailInput = ""
    @State private var sellerIdInput = ""
    @State private var sellerEmailInput = ""
    @State private var sellerBusinessNameInput = ""
    @State private var sellerIdentifierInput = ""
    @State private var sellerPasswordInput = ""
    @State private var sellerLegalNameInput = ""
    @State private var sellerShippingCountryInput = "United States"
    @State private var sellerShippingStateInput = ""
    @State private var showSellerAgreementReview = false
    @State private var sellerAgreementCreationSucceeded = false
    @State private var isSellerPasswordVisible = false
    @State private var buyerErrorMessage: String?
    @State private var sellerErrorMessage: String?
    @State private var isCreatingBuyerAccount = false
    @State private var isCreatingSellerAccount = false
    @FocusState private var focusedSellerField: SellerAccountFieldFocus?

    init(startInSellerAccount: Bool = false, sellerEntryMode: SellerAccountEntryMode = .create) {
        startsInSellerAccount = startInSellerAccount
        self.sellerEntryMode = sellerEntryMode
        _step = State(initialValue: startInSellerAccount ? .sellerAccount : .roleSelection)
    }

    var body: some View {
        ZStack {
            WinterSceneBackground()

            Group {
                if step == .sellerAccount {
                    sellerAccountScreen
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 22)

                            header

                            Group {
                                switch step {
                                case .roleSelection:
                                    roleSelectionContent
                                case .buyerChoice:
                                    buyerChoiceContent
                                case .buyerAccount:
                                    buyerAccountContent
                                case .sellerAccount:
                                    EmptyView()
                                }
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))

                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
            .allowsHitTesting(!(isCreatingBuyerAccount || isCreatingSellerAccount))

            if isCreatingSellerAccount && !showSellerAgreementReview {
                AppOperationOverlay(
                    title: loadingOverlayTitle,
                    subtitle: loadingOverlaySubtitle
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: step)
        .animation(.easeInOut(duration: 0.45), value: showSellerAgreementReview)
    }

    private var loadingOverlayTitle: String {
        return isCreatingSellerAccount
            ? (sellerEntryMode == .signIn ? "Signing In" : "Creating Seller Account")
            : "Setting Up Your Account"
    }

    private var loadingOverlaySubtitle: String {
        return isCreatingSellerAccount
            ? (sellerEntryMode == .signIn ? "Checking your seller credentials." : "Saving your seller account.")
            : "Saving your buyer details and preferences."
    }

    private var header: some View {
        VStack(spacing: 20) {
            Image("TenBelowLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 238, height: 112)
                .shadow(color: .white.opacity(0.42), radius: 10)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TBTheme.deepSky, TBTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)

                Text(step.subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 8)
    }

    private var roleSelectionContent: some View {
        VStack(spacing: 16) {
            roleCard(
                icon: "cart",
                title: "I'm Shopping",
                description: "Browse 3D printed products under $10 and get items shipped to your door."
            ) {
                step = .buyerChoice
            }

            roleCard(
                icon: "storefront",
                title: "I'm Selling",
                description: "List your 3D printed products and reach thousands of buyers."
            ) {
                step = .sellerAccount
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
    }

    private var buyerChoiceContent: some View {
        VStack(spacing: 16) {
            decisionCard(
                icon: "bag",
                eyebrow: "Fastest start",
                title: "Continue as Guest",
                description: "Browse products, add items to cart, and check out quickly without creating an account."
            ) {
                completeBuyerFlow(preference: .guest)
            }

            decisionCard(
                icon: "person.crop.circle.badge.plus",
                eyebrow: "Best for repeat orders",
                title: "Create Account",
                description: "Save your details, track orders easily, and keep your TenBelow experience synced."
            ) {
                step = .buyerAccount
            }

            backButton
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
    }

    private var buyerAccountContent: some View {
        VStack(spacing: 16) {
            formCard(
                title: "Create your buyer account",
                subtitle: "Set up a simple account now so your orders and preferences stay with you."
            ) {
                VStack(spacing: 12) {
                    formField(title: "Full Name", text: $buyerNameInput, prompt: "Your name", keyboard: .default)
                    formField(title: "Email", text: $buyerEmailInput, prompt: "you@example.com", keyboard: .emailAddress)
                }
            }

            if let buyerErrorMessage {
                errorCard(message: buyerErrorMessage)
            }

            Button {
                createBuyerAccount()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text(isCreatingBuyerAccount ? "Creating account..." : "Create buyer account")
                }
            }
            .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
            .disabled(isCreatingBuyerAccount)

            backButton
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
        .onAppear {
            buyerNameInput = buyerFullName
            buyerEmailInput = buyerEmail
        }
    }

    private var sellerAccountContent: some View {
        VStack(spacing: 10) {
            sellerAccountFormCard

            if let sellerErrorMessage {
                errorCard(message: sellerErrorMessage)
            }

            VStack(spacing: 8) {
                Button {
                    dismissSellerKeyboard()
                    Task {
                        if sellerEntryMode == .signIn {
                            await signInSellerAccount()
                        } else {
                            prepareSellerAgreementReview()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "storefront")
                        Text(
                            isCreatingSellerAccount
                                ? (sellerEntryMode == .signIn ? "Signing in..." : "Preparing agreement...")
                                : (sellerEntryMode == .signIn ? "Sign in as seller" : "Create seller account")
                        )
                    }
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                .disabled(isCreatingSellerAccount)

                backButton
            }
        }
        .frame(maxWidth: 560)
        .onAppear {
            if sellerEntryMode == .signIn {
                sellerIdentifierInput = sellerEmail.isEmpty ? sellerId : sellerEmail
            } else {
                sellerIdInput = sellerId
                sellerEmailInput = sellerEmail
                sellerBusinessNameInput = sellerBusinessName
            }
        }
        .fullScreenCover(isPresented: $showSellerAgreementReview) {
            SellerAgreementAcceptanceView(
                legalName: sellerLegalNameInput.trimmingCharacters(in: .whitespacesAndNewlines),
                email: sellerEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                shippingOrigin: sellerShippingOriginSummary,
                isCreatingAccount: isCreatingSellerAccount,
                accountCreationSucceeded: sellerAgreementCreationSucceeded,
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        showSellerAgreementReview = false
                    }
                },
                onAccept: {
                    Task { await createSellerAccount() }
                }
            )
        }
    }

    private var sellerAccountScreen: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer().frame(height: 18)

                sellerAccountHeader

                VStack(spacing: 10) {
                    sellerAccountContent
                }
                .padding(.top, 14)

                Spacer(minLength: 28)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSellerKeyboard()
        }
        // Keep the screen from sliding up with the keyboard; users scroll the form by focus if needed.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var sellerAccountHeader: some View {
        VStack(spacing: 10) {
            Image("TenBelowLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 176, height: 78)
                .shadow(color: .white.opacity(0.34), radius: 7)

            Text("Seller Account")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [TBTheme.deepSky, TBTheme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 560)
    }

    private var sellerAccountFormCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Account")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(TBTheme.accent)

                Text(sellerEntryMode == .signIn ? "Sign in details" : "Your seller details")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text(sellerEntryMode == .signIn ? "Use your seller ID or email and password." : "Add the core info needed to open your seller space.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .lineSpacing(2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                if sellerEntryMode == .signIn {
                    sellerAccountField(
                        title: "Seller ID or Email",
                        text: $sellerIdentifierInput,
                        prompt: "fff or fff@gmail.com",
                        keyboard: .emailAddress,
                        autocapitalize: false,
                        focus: .identifier,
                        submitLabel: .next
                    )
                    Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                    sellerAccountField(
                        title: "Password",
                        text: $sellerPasswordInput,
                        prompt: "Password",
                        keyboard: .default,
                        autocapitalize: false,
                        focus: .password,
                        submitLabel: .done,
                        isSecure: true
                    )
                } else {
                    sellerAccountField(
                        title: "Seller ID",
                        text: $sellerIdInput,
                        prompt: "my_shop",
                        keyboard: .default,
                        autocapitalize: false,
                        focus: .sellerId,
                        submitLabel: .next
                    )
                    Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                    sellerAccountField(
                        title: "Email",
                        text: $sellerEmailInput,
                        prompt: "you@example.com",
                        keyboard: .emailAddress,
                        autocapitalize: false,
                        focus: .email,
                        submitLabel: .next
                    )
                    Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                    sellerAccountField(
                        title: "Password",
                        text: $sellerPasswordInput,
                        prompt: "At least 8 characters",
                        keyboard: .default,
                        autocapitalize: false,
                        focus: .password,
                        submitLabel: .next,
                        isSecure: true
                    )
                    Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                    sellerAccountField(
                        title: "Legal Name",
                        text: $sellerLegalNameInput,
                        prompt: "Your legal first and last name",
                        keyboard: .default,
                        focus: .legalName,
                        submitLabel: .next
                    )
                    Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                    HStack(spacing: 0) {
                        sellerAccountField(
                            title: "Origin Country",
                            text: $sellerShippingCountryInput,
                            prompt: "United States",
                            keyboard: .default,
                            focus: .shippingCountry,
                            submitLabel: .next
                        )
                        Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                        sellerAccountField(
                            title: "State",
                            text: $sellerShippingStateInput,
                            prompt: "PA",
                            keyboard: .default,
                            autocapitalize: false,
                            focus: .shippingState,
                            submitLabel: .next
                        )
                    }
                    Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                    sellerAccountField(
                        title: "Business Name",
                        text: $sellerBusinessNameInput,
                        prompt: "Optional",
                        keyboard: .default,
                        focus: .businessName,
                        submitLabel: .done
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.54),
                                        .white.opacity(0.18),
                                        TBTheme.skyLight.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.58),
                                    .white.opacity(0.22),
                                    TBTheme.skyLight.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.94),
                            .white.opacity(0.42),
                            TBTheme.skyBlue.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .white.opacity(0.18), radius: 4, y: -1)
        .shadow(color: TBTheme.deepSky.opacity(0.09), radius: 18, y: 7)
    }

    private var sellerHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("Seller account")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(TBTheme.accent)

            imageShowcase(name: "seller_account_hero", height: 150)

            VStack(alignment: .leading, spacing: 6) {
                Text("Bring your 3D products to life")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Set up your shop, upload clear media, and keep product details polished.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.60))
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.72), .white.opacity(0.32), TBTheme.skyLight.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.78), lineWidth: 1)
        )
    }

    private var backButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                step = step.backDestination
            }
        } label: {
            Text("Back")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func completeBuyerFlow(preference: BuyerCheckoutPreference) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        buyerCheckoutPreference = preference.rawValue
        transitionToOnboarding(as: "buyer")
    }

    private func createBuyerAccount() {
        let trimmedName = buyerNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = buyerEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedName.isEmpty else {
            buyerErrorMessage = "Please enter your name."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            buyerErrorMessage = "Please enter a valid email address."
            return
        }

        buyerErrorMessage = nil
        isCreatingBuyerAccount = true

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        buyerFullName = trimmedName
        buyerEmail = trimmedEmail
        buyerAccountCreated = true
        buyerCheckoutPreference = BuyerCheckoutPreference.account.rawValue
        isCreatingBuyerAccount = false

        transitionToOnboarding(as: "buyer")

        Task {
            await MarketplaceAuthSession.syncAfterIdentityChange()
            await PushDeviceRegistration.syncAfterIdentityChange()
        }
    }

    private func validateSellerAccountInputs() -> (sellerId: String, email: String, businessName: String, legalName: String, shippingCountry: String, shippingState: String)? {
        let trimmedSellerId = normalizedSellerID(sellerIdInput)
        let trimmedEmail = sellerEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedBusinessName = sellerBusinessNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLegalName = sellerLegalNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShippingCountry = sellerShippingCountryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShippingState = sellerShippingStateInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !trimmedSellerId.isEmpty else {
            sellerErrorMessage = "Please choose a seller ID."
            return nil
        }

        guard isValidSellerID(trimmedSellerId) else {
            sellerErrorMessage = "Seller ID must be 3 to 24 characters using letters, numbers, hyphens, or underscores."
            return nil
        }

        guard isValidEmail(trimmedEmail) else {
            sellerErrorMessage = "Please enter a valid email address."
            return nil
        }

        guard sellerPasswordInput.count >= 8 else {
            sellerErrorMessage = "Password must be at least 8 characters."
            return nil
        }

        guard !trimmedLegalName.isEmpty else {
            sellerErrorMessage = "Please enter your legal name."
            return nil
        }

        guard !trimmedShippingCountry.isEmpty else {
            sellerErrorMessage = "Please enter your shipping origin country."
            return nil
        }

        guard !trimmedShippingState.isEmpty else {
            sellerErrorMessage = "Please enter your shipping origin state."
            return nil
        }

        sellerErrorMessage = nil
        return (trimmedSellerId, trimmedEmail, trimmedBusinessName, trimmedLegalName, trimmedShippingCountry, trimmedShippingState)
    }

    private func prepareSellerAgreementReview() {
        dismissSellerKeyboard()
        guard validateSellerAccountInputs() != nil else { return }
        showSellerAgreementReview = true
    }

    private var sellerShippingOriginSummary: String {
        let country = sellerShippingCountryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = sellerShippingStateInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if country.isEmpty { return state }
        if state.isEmpty { return country }
        return "\(country), \(state)"
    }

    private func createSellerAccount() async {
        await MainActor.run {
            dismissSellerKeyboard()
        }

        guard let validated = await MainActor.run(body: { validateSellerAccountInputs() }) else { return }

        await MainActor.run {
            sellerErrorMessage = nil
            isCreatingSellerAccount = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }

        do {
            // Membership is purchased in-app via StoreKit (`SellerSubscriptionStore`). We do not open Stripe Connect onboarding here—that flow remains available from the seller dashboard for payouts when needed.
            try await SellerAPI.createAccount(
                sellerId: validated.sellerId,
                email: validated.email,
                businessName: validated.businessName.isEmpty ? nil : validated.businessName,
                password: sellerPasswordInput,
                legalName: validated.legalName,
                shippingOriginCountry: validated.shippingCountry,
                shippingOriginState: validated.shippingState,
                sellerAgreementAccepted: true,
                sellerPoliciesAcknowledged: true
            )

            await applyCreatedSellerRegistration(
                trimmedSellerId: validated.sellerId,
                trimmedEmail: validated.email,
                trimmedBusinessName: validated.businessName,
                useOfflinePreview: false,
                releaseCreatingState: false
            )
            await completeSellerAgreementTransition()
        } catch {
            if SellerAPI.isSellerAlreadyExistsError(error) {
                await MainActor.run {
                    sellerErrorMessage = "That seller ID already exists. Use Sign in as seller from Settings."
                    isCreatingSellerAccount = false
                }
                return
            }

            await MainActor.run {
                sellerAccountCreated = false
                sellerPreviewMode = false
                #if DEBUG
                let localhostHint: String = {
                    guard let host = AppConstants.backendBaseURL?.host?.lowercased() else { return "" }
                    if host == "localhost" || host == "127.0.0.1" {
                        return " On a real iPhone, open Settings → Developer and set Backend URL to http://<your Mac’s LAN IP>:3000, or use the same Wi‑Fi and your Mac’s IP (not localhost)."
                    }
                    return ""
                }()
                #else
                let localhostHint = ""
                #endif
                sellerErrorMessage = "We couldn't create your seller account right now. Connect the backend and try again. \(error.localizedDescription)\(localhostHint)"
                isCreatingSellerAccount = false
            }
        }
    }

    private func signInSellerAccount() async {
        await MainActor.run {
            dismissSellerKeyboard()
        }

        let identifier = sellerIdentifierInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = sellerPasswordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !identifier.isEmpty else {
            sellerErrorMessage = "Enter your seller ID or email."
            return
        }

        guard password.count >= 8 else {
            sellerErrorMessage = "Enter your seller password."
            return
        }

        await MainActor.run {
            sellerErrorMessage = nil
            isCreatingSellerAccount = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }

        do {
            let response = try await SellerAPI.login(identifier: identifier, password: password)
            await MainActor.run {
                sellerId = response.sellerId
                sellerEmail = response.sellerEmail ?? identifier
                sellerBusinessName = response.businessName ?? ""
                sellerAccountCreated = true
                sellerPreviewMode = false
                sellerErrorMessage = nil
                isCreatingSellerAccount = false
                userRole = "seller"
                pendingLaunchTab = 1
                hasSeenOnboarding = false
                MarketplaceAuthSession.storeSellerSessionToken(response.token)
            }
            await PushDeviceRegistration.syncAfterIdentityChange()
        } catch {
            await MainActor.run {
                sellerErrorMessage = error.localizedDescription
                isCreatingSellerAccount = false
            }
        }
    }

    @MainActor
    private func completeSellerAgreementTransition() async {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            sellerAgreementCreationSucceeded = true
        }

        try? await Task.sleep(for: .milliseconds(900))

        isCreatingSellerAccount = false

        try? await Task.sleep(for: .milliseconds(180))

        withAnimation(.easeInOut(duration: 0.48)) {
            showSellerAgreementReview = false
        }

        try? await Task.sleep(for: .milliseconds(520))

        sellerAgreementCreationSucceeded = false
        transitionToOnboarding(as: "seller")
    }

    private func applyCreatedSellerRegistration(
        trimmedSellerId: String,
        trimmedEmail: String,
        trimmedBusinessName: String,
        useOfflinePreview: Bool,
        releaseCreatingState: Bool = true
    ) async {
        let starterProfile = SellerProfile.starterProfile(
            sellerId: trimmedSellerId,
            businessName: trimmedBusinessName
        )

        await MainActor.run {
            sellerId = trimmedSellerId
            sellerEmail = trimmedEmail
            sellerBusinessName = trimmedBusinessName
            sellerAccountCreated = true
            sellerPreviewMode = useOfflinePreview
            sellerErrorMessage = nil
            starterProfile.storeLocally()
            catalog.upsertSellerProfile(starterProfile)
            if releaseCreatingState {
                isCreatingSellerAccount = false
            }
            userRole = "seller"
            pendingLaunchTab = 1
            hasSeenOnboarding = false
        }

        await MarketplaceAuthSession.syncAfterIdentityChange()
        _ = try? await MarketplaceAuthSession.ensureSellerSessionReady()
        await PushDeviceRegistration.syncAfterIdentityChange()
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func normalizedSellerID(_ sellerID: String) -> String {
        sellerID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private func isValidSellerID(_ sellerID: String) -> Bool {
        let pattern = #"^[a-z0-9][a-z0-9_-]{2,23}$"#
        return sellerID.range(of: pattern, options: .regularExpression) != nil
    }

    private func transitionToOnboarding(as role: String) {
        withAnimation(.easeInOut(duration: 0.45)) {
            userRole = role
            hasSeenOnboarding = false
        }
    }

    private func roleCard(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8), action)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.90),
                                    TBTheme.skyLight.opacity(0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)

                    Text(description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 34, height: 34)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.7))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.74),
                                        .white.opacity(0.40),
                                        TBTheme.skyLight.opacity(0.14)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 18, y: 8)
                    .shadow(color: .white.opacity(0.30), radius: 4, y: -1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func decisionCard(icon: String, eyebrow: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.90), TBTheme.skyLight.opacity(0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(TBTheme.accent)

                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)

                    Text(description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.72), .white.opacity(0.32), TBTheme.skyLight.opacity(0.14)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func infoCard(icon: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.90), TBTheme.skyLight.opacity(0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }

                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TBTheme.accent)
                            .padding(.top, 3)

                        Text(line)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.62))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.72), .white.opacity(0.32), TBTheme.skyLight.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.78), lineWidth: 1)
        )
    }

    private func imageShowcase(name: String, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.82),
                            TBTheme.skyLight.opacity(0.36)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(name)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.86), lineWidth: 1)
        )
        .shadow(color: .white.opacity(0.25), radius: 3, y: -1)
        .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 10, y: 5)
    }

    private func formCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.58))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.78),
                                    .white.opacity(0.34),
                                    TBTheme.skyLight.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.92),
                            .white.opacity(0.42),
                            TBTheme.skyBlue.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .white.opacity(0.18), radius: 4, y: -1)
        .shadow(color: TBTheme.deepSky.opacity(0.09), radius: 18, y: 8)
    }

    private func sellerAccountField(
        title: String,
        text: Binding<String>,
        prompt: String,
        keyboard: UIKeyboardType,
        autocapitalize: Bool = true,
        focus: SellerAccountFieldFocus,
        submitLabel: SubmitLabel,
        isSecure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky.opacity(0.92))

            HStack(spacing: 10) {
                Group {
                    if isSecure && !isSellerPasswordVisible {
                        SecureField(prompt, text: text)
                    } else {
                        TextField(prompt, text: text)
                    }
                }
                .textInputAutocapitalization(autocapitalize ? .words : .never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .focused($focusedSellerField, equals: focus)
                .submitLabel(submitLabel)
                .onSubmit {
                    advanceSellerField(from: focus)
                }
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.78))

                if isSecure {
                    Button {
                        isSellerPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isSellerPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TBTheme.deepSky.opacity(0.62))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSellerPasswordVisible ? "Hide password" : "Show password")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func advanceSellerField(from field: SellerAccountFieldFocus?) {
        switch field {
        case .identifier:
            focusedSellerField = .password
        case .sellerId:
            focusedSellerField = .email
        case .email:
            focusedSellerField = sellerEntryMode == .signIn ? .password : .password
        case .password:
            focusedSellerField = sellerEntryMode == .signIn ? nil : .legalName
        case .legalName:
            focusedSellerField = .shippingCountry
        case .shippingCountry:
            focusedSellerField = .shippingState
        case .shippingState:
            focusedSellerField = .businessName
        case .businessName:
            dismissSellerKeyboard()
        case .none:
            focusedSellerField = sellerEntryMode == .signIn ? .identifier : .sellerId
        }
    }

    private func dismissSellerKeyboard() {
        focusedSellerField = nil
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func formField(title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType, autocapitalize: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            TextField(prompt, text: text)
                .textInputAutocapitalization(autocapitalize ? .words : .never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.50),
                                            .white.opacity(0.16),
                                            TBTheme.skyLight.opacity(0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.94),
                                    .white.opacity(0.42),
                                    TBTheme.skyBlue.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.16), lineWidth: 1)
            )
    }
}

private struct SellerAgreementAcceptanceView: View {
    let legalName: String
    let email: String
    let shippingOrigin: String
    let isCreatingAccount: Bool
    let accountCreationSucceeded: Bool
    let onCancel: () -> Void
    let onAccept: () -> Void

    @State private var hasReachedAgreementEnd = false
    @State private var hasAcceptedAgreement = false
    @State private var agreementViewportHeight: CGFloat = 0

    private var isTransitioning: Bool {
        isCreatingAccount || accountCreationSucceeded
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WinterSceneBackground()
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    header

                    requirementSummary

                    agreementCard
                        .layoutPriority(1)

                    actionBar
                }
                .padding(.horizontal, 20)
                .padding(.top, max(geometry.safeAreaInsets.top - 24, 0))
                .padding(.bottom, geometry.safeAreaInsets.bottom + 6)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .blur(radius: isTransitioning ? 2 : 0)
                .opacity(isTransitioning ? 0.28 : 1)
                .allowsHitTesting(!isTransitioning)

                if isCreatingAccount && !accountCreationSucceeded {
                    AppOperationOverlay(
                        title: "Creating seller account",
                        subtitle: "Saving your shop profile and agreement acceptance."
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if accountCreationSucceeded {
                    AppOperationOverlay(
                        title: "Account ready",
                        subtitle: "Taking you to seller onboarding...",
                        systemImage: "checkmark.circle.fill",
                        showsProgress: false
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isCreatingAccount)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: accountCreationSucceeded)
        .interactiveDismissDisabled(isTransitioning)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seller onboarding")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(TBTheme.icyBlue)
                    Text("Seller Agreement")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(TBTheme.deepSky)
                }
                .padding(.leading, 46)

                Text("Review and accept before seller onboarding continues.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TBTheme.deepSky.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button {
                onCancel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TBTheme.deepSky)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isCreatingAccount)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var requirementSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(TBTheme.skyLight.opacity(0.62))
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TBTheme.icyBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Required before selling")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                    Text("Account details ready for review.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 3) {
                compactRequirementRow("Legal name · Email", "\(legalName) · \(email)")
                compactRequirementRow("Shipping origin", shippingOrigin)
                compactRequirementRow("Payout · Policies", "Stripe setup · Included in agreement")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.66), TBTheme.skyLight.opacity(0.18), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.82), lineWidth: 1)
        )
    }

    private func compactRequirementRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TBTheme.icyBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                Text(value.isEmpty ? "Required" : value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
    }

    private var agreementCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Agreement document", systemImage: "doc.text.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Spacer(minLength: 8)

                Text(hasReachedAgreementEnd ? "Reviewed" : "Scroll")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(hasReachedAgreementEnd ? .green : TBTheme.icyBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((hasReachedAgreementEnd ? Color.green : TBTheme.skyBlue).opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(hasReachedAgreementEnd ? Color.green.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
                    .shadow(color: hasReachedAgreementEnd ? Color.green.opacity(0.22) : .clear, radius: 8, y: 2)
                    .scaleEffect(hasReachedAgreementEnd ? 1.04 : 1)
                    .animation(.spring(response: 0.34, dampingFraction: 0.76), value: hasReachedAgreementEnd)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(LegalDocument.sellerAgreement.displayBodyText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.84))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("End of Seller Agreement")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SellerAgreementEndPositionKey.self,
                                    value: proxy.frame(in: .named("sellerAgreementScroll")).minY
                                )
                            }
                        )
                }
                .padding(.bottom, 4)
            }
            .coordinateSpace(name: "sellerAgreementScroll")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SellerAgreementViewportHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(SellerAgreementViewportHeightKey.self) { newHeight in
                agreementViewportHeight = newHeight
            }
            .onPreferenceChange(SellerAgreementEndPositionKey.self) { endMinY in
                guard !hasReachedAgreementEnd, agreementViewportHeight > 0 else { return }
                if endMinY <= agreementViewportHeight - 8 {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        hasReachedAgreementEnd = true
                    }
                }
            }

            agreementAcceptanceToggle
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.82), lineWidth: 1)
        )
    }

    private var agreementAcceptanceToggle: some View {
        Button {
            guard hasReachedAgreementEnd else { return }
            hasAcceptedAgreement.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: hasAcceptedAgreement ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(hasAcceptedAgreement ? TBTheme.icyBlue : TBTheme.deepSky.opacity(0.5))
                Text("I have read and agree to the TenBelow Seller Agreement, Seller Policies, and payout setup requirements.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!hasReachedAgreementEnd)
        .opacity(hasReachedAgreementEnd ? 1 : 0.55)
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                onAccept()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text(isCreatingAccount ? "Creating account..." : "Agree and create seller account")
                }
            }
            .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
            .disabled(!hasReachedAgreementEnd || !hasAcceptedAgreement || isCreatingAccount)
            .opacity(hasReachedAgreementEnd && hasAcceptedAgreement ? 1 : 0.55)

            Text(hasReachedAgreementEnd ? "Check the agreement box to continue." : "Scroll the agreement box to the end.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct SellerAgreementViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SellerAgreementEndPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private enum RolePickerStep {
    case roleSelection
    case buyerChoice
    case buyerAccount
    case sellerAccount

    var title: String {
        switch self {
        case .roleSelection:
            return "Choose Your TenBelow Experience"
        case .buyerChoice:
            return "How Would You Like To Shop?"
        case .buyerAccount:
            return "Create Your Buyer Account"
        case .sellerAccount:
            return "Set Up Your Seller Account"
        }
    }

    var subtitle: String {
        switch self {
        case .roleSelection:
            return "Start as a shopper or seller. You can change this anytime in Settings."
        case .buyerChoice:
            return "Choose the checkout style that feels best for you. You can always update this later."
        case .buyerAccount:
            return "Save your details now so your orders, preferences, and future checkouts are all easier."
        case .sellerAccount:
            return "Create your seller profile now. After this, we will walk you through how selling on TenBelow works."
        }
    }

    var backDestination: RolePickerStep {
        switch self {
        case .roleSelection:
            return .roleSelection
        case .buyerChoice:
            return .roleSelection
        case .buyerAccount:
            return .buyerChoice
        case .sellerAccount:
            return .roleSelection
        }
    }
}

private enum BuyerCheckoutPreference: String {
    case guest
    case account
}

private enum SellerAccountFieldFocus: Hashable {
    case identifier
    case sellerId
    case email
    case password
    case legalName
    case shippingCountry
    case shippingState
    case businessName
}

enum SellerAccountEntryMode {
    case create
    case signIn
}

