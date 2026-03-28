//
//  RolePickerView.swift
//  TenBelow
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RolePickerView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = BuyerCheckoutPreference.guest.rawValue
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @AppStorage("sellerBusinessName") private var sellerBusinessName = ""
    @AppStorage("sellerAccountCreated") private var sellerAccountCreated = false
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @State private var step: RolePickerStep = .roleSelection
    @State private var buyerNameInput = ""
    @State private var buyerEmailInput = ""
    @State private var sellerIdInput = ""
    @State private var sellerEmailInput = ""
    @State private var sellerBusinessNameInput = ""
    @State private var buyerErrorMessage: String?
    @State private var sellerErrorMessage: String?
    @State private var sellerKeyboardHeight: CGFloat = 0
    @State private var isCreatingBuyerAccount = false
    @State private var isCreatingSellerAccount = false
    @State private var isTransitioningToOnboarding = false
    @FocusState private var focusedSellerField: SellerAccountFieldFocus?

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
            .opacity(isTransitioningToOnboarding ? 0.12 : 1.0)
            .blur(radius: isTransitioningToOnboarding ? 10 : 0)
            .scaleEffect(isTransitioningToOnboarding ? 1.015 : 1.0)
            .allowsHitTesting(!(isCreatingBuyerAccount || isCreatingSellerAccount || isTransitioningToOnboarding))

            if isCreatingBuyerAccount || isCreatingSellerAccount || isTransitioningToOnboarding {
                AppLoadingOverlay(
                    title: loadingOverlayTitle,
                    subtitle: loadingOverlaySubtitle
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: step)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: isTransitioningToOnboarding)
    }

    private var loadingOverlayTitle: String {
        if isTransitioningToOnboarding {
            return "Loading Onboarding"
        }

        return isCreatingSellerAccount ? "Creating Seller Account" : "Setting Up Your Account"
    }

    private var loadingOverlaySubtitle: String {
        if isTransitioningToOnboarding {
            return "Getting your welcome experience ready."
        }

        return isCreatingSellerAccount
            ? "Preparing your seller profile and onboarding."
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
                if isCreatingBuyerAccount {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text("Create buyer account")
                    }
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
                    Task { await createSellerAccount() }
                } label: {
                    if isCreatingSellerAccount {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "storefront")
                            Text("Create seller account")
                        }
                    }
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                .disabled(isCreatingSellerAccount)

                backButton
            }
        }
        .frame(maxWidth: 560)
        .onAppear {
            sellerIdInput = sellerId
            sellerEmailInput = sellerEmail
            sellerBusinessNameInput = sellerBusinessName
        }
    }

    private var sellerAccountScreen: some View {
        GeometryReader { _ in
            let keyboardLift = min(max(sellerKeyboardHeight - 34, 0) * 0.24, 76)

            VStack(spacing: 0) {
                Spacer().frame(height: 18)

                sellerAccountHeader

                VStack(spacing: 10) {
                    compactSellerSetupCard
                    sellerAccountContent
                }
                .padding(.top, 14)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, sellerKeyboardHeight > 0 ? 12 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: sellerKeyboardHeight > 0 ? -keyboardLift : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: sellerKeyboardHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissSellerKeyboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateSellerKeyboard(with: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    sellerKeyboardHeight = 0
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(focusedSellerField == .businessName ? "Done" : "Next") {
                        advanceSellerField()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                }
            }
        }
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

    private var compactSellerSetupCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 34, height: 34)

                Image(systemName: "storefront")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Simple setup")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Create your seller account first. Membership is separate and can be activated when you're ready to publish.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.44),
                                    .white.opacity(0.18),
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
                            .white.opacity(0.90),
                            .white.opacity(0.36),
                            TBTheme.skyBlue.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .white.opacity(0.18), radius: 4, y: -1)
        .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 14, y: 6)
        .frame(maxWidth: 560)
    }

    private var sellerAccountFormCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Account")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(TBTheme.accent)

                Text("Your seller details")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Add the core info needed to open your seller space.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .lineSpacing(2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
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
                    title: "Business Name",
                    text: $sellerBusinessNameInput,
                    prompt: "Optional",
                    keyboard: .default,
                    focus: .businessName,
                    submitLabel: .done
                )
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
    }

    private func createSellerAccount() async {
        let trimmedSellerId = normalizedSellerID(sellerIdInput)
        let trimmedEmail = sellerEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedBusinessName = sellerBusinessNameInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSellerId.isEmpty else {
            sellerErrorMessage = "Please choose a seller ID."
            return
        }

        guard isValidSellerID(trimmedSellerId) else {
            sellerErrorMessage = "Seller ID must be 3 to 24 characters using letters, numbers, hyphens, or underscores."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            sellerErrorMessage = "Please enter a valid email address."
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
            let response = try await SellerAPI.createAccount(
                sellerId: trimmedSellerId,
                email: trimmedEmail,
                businessName: trimmedBusinessName.isEmpty ? nil : trimmedBusinessName
            )

            await MainActor.run {
                sellerId = trimmedSellerId
                sellerEmail = trimmedEmail
                sellerBusinessName = trimmedBusinessName
                sellerAccountCreated = true
                isCreatingSellerAccount = false
            }

            await MainActor.run {
                transitionToOnboarding(as: "seller")
            }

            if let url = URL(string: response.onboardingUrl) {
                await MainActor.run {
                    openURL(url)
                }
            }
        } catch {
            await MainActor.run {
                sellerId = trimmedSellerId
                sellerEmail = trimmedEmail
                sellerBusinessName = trimmedBusinessName
                sellerAccountCreated = true
                sellerPreviewMode = true
                sellerErrorMessage = nil
                isCreatingSellerAccount = false
                transitionToOnboarding(as: "seller")
            }
        }
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
        guard !isTransitioningToOnboarding else { return }

        withAnimation(.easeInOut(duration: 0.22)) {
            isTransitioningToOnboarding = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
            withAnimation(.easeInOut(duration: 0.28)) {
                userRole = role
                hasSeenOnboarding = false
            }
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
        submitLabel: SubmitLabel
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky.opacity(0.92))

            TextField(prompt, text: text)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func advanceSellerField() {
        advanceSellerField(from: focusedSellerField)
    }

    private func advanceSellerField(from field: SellerAccountFieldFocus?) {
        switch field {
        case .sellerId:
            focusedSellerField = .email
        case .email:
            focusedSellerField = .businessName
        case .businessName:
            dismissSellerKeyboard()
        case .none:
            focusedSellerField = .sellerId
        }
    }

    private func dismissSellerKeyboard() {
        focusedSellerField = nil
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func updateSellerKeyboard(with notification: Notification) {
        #if os(iOS)
        guard
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let screenHeight = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?
            .screen.bounds.height ?? 0
        let overlap: CGFloat
        if screenHeight > 0 {
            overlap = max(0, screenHeight - endFrame.minY)
        } else {
            // No foreground scene (rare): fall back to visible keyboard height.
            overlap = max(0, endFrame.height)
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            sellerKeyboardHeight = overlap
        }
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
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    case sellerId
    case email
    case businessName
}

#Preview {
    RolePickerView()
}
