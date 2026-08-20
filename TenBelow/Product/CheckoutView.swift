//
//  CheckoutView.swift
//  TenBelow
//

import SwiftUI
import StripePaymentSheet

#if os(iOS)
import UIKit
#endif

private enum CheckoutFocusField: Hashable {
    case email
    case name
    case line1
    case line2
    case city
    case state
    case postalCode
    case country
}

struct CheckoutView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var orderStore: OrderStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerHasPlacedOrder") private var buyerHasPlacedOrder = false
    var onSuccess: (String) -> Void

    @State private var email = ""
    @State private var name = ""
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @State private var country = "US"

    @State private var agreedToTerms = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var orderId: String?
    /// Keeps the current `PaymentSheet` alive for the duration of UIKit presentation (see `presentPaymentSheetFromKeyWindow`).
    @State private var paymentSheetRetainer: PaymentSheet?
    @State private var presentedLegal: LegalDocument?

    @FocusState private var focusedField: CheckoutFocusField?

    private var isCheckoutReady: Bool {
        AppConstants.hasLiveCheckoutConfiguration || AppConstants.isTestingOverridesEnabled
    }

    private var minimumOrderCents: Int {
        AppConstants.minimumOrderCents
    }

    private var canProceed: Bool {
        !trimmedEmail.isEmpty
            && !trimmedName.isEmpty
            && !trimmedAddressLine1.isEmpty
            && !trimmedCity.isEmpty
            && !normalizedState.isEmpty
            && !normalizedPostalCode.isEmpty
            && isValidEmail(trimmedEmail)
            && isValidUSState(normalizedState)
            && isValidUSPostalCode(normalizedPostalCode)
            && agreedToTerms
    }

    private var checkoutBlockingReasons: [String] {
        var reasons: [String] = []
        if !isCheckoutReady { reasons.append(AppConstants.checkoutSetupMessage) }
        if cart.subtotalCents < minimumOrderCents {
            reasons.append("Minimum order is \(Money.format(cents: minimumOrderCents)).")
        }
        if trimmedEmail.isEmpty || !isValidEmail(trimmedEmail) { reasons.append("Enter a valid email.") }
        if trimmedName.count < 2 { reasons.append("Enter full name.") }
        if trimmedAddressLine1.isEmpty { reasons.append("Enter street address.") }
        if trimmedCity.isEmpty { reasons.append("Enter city.") }
        if !isValidUSState(normalizedState) { reasons.append("Use a 2-letter state code.") }
        if !isValidUSPostalCode(normalizedPostalCode) { reasons.append("Enter a valid ZIP code.") }
        if normalizedCountry != "US" { reasons.append("US shipping only right now.") }
        if !agreedToTerms { reasons.append("Accept terms to continue.") }
        return reasons
    }

    private var itemsBySeller: [(sellerId: String, items: [CartItem])] {
        Dictionary(grouping: cart.items, by: { $0.product.sellerId })
            .sorted { $0.key < $1.key }
            .map { (sellerId: $0.key, items: $0.value)
        }
    }

    private var checkoutProducts: [Product] {
        cart.items.map(\.product)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddressLine1: String {
        line1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddressLine2: String {
        line2.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedState: String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var normalizedPostalCode: String {
        postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedCountry: String {
        country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func sellerDisplayName(for sellerId: String) -> String {
        resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: checkoutProducts,
            remoteProfiles: catalog.sellerProfiles
        )?.displayName ?? sellerId
    }

    var body: some View {
        let content = ZStack {
            ScrollView {
                VStack(spacing: TBTheme.spacingXL) {

                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(TBTheme.radiusMD)
                        .padding(.horizontal)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                    }

                    if !isCheckoutReady {
                        stripeSetupNotice
                    }

                    orderSummarySection

                    shippingSection

                    policyAgreementSection

                    payButton
                }
                .padding(.vertical, TBTheme.spacingLG)
                .padding(.bottom, 40)
                .animation(reduceMotion ? nil : TBMotion.stateChange, value: errorMessage)
            }
            .scrollDismissesKeyboard(.interactively)
            .dynamicTypeSize(.xSmall ... .accessibility5)
        }
        .onAppear {
            errorMessage = nil
            if email.isEmpty { email = buyerEmail }
            if name.isEmpty { name = buyerFullName }
        }

        content
            .sheet(item: $presentedLegal) { document in
                LegalDocumentSheet(document: document)
            }
    }

    private var stripeSetupNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "creditcard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TBTheme.icyBlue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Checkout unavailable")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text(AppConstants.checkoutSetupMessage)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                #if DEBUG
                if !AppConstants.hasLiveCheckoutConfiguration {
                    Text("Until Stripe is ready: Settings → Developer → turn on Testing mode to simulate checkout.")
                        .font(.tbCaption)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
        .padding(.horizontal)
    }

    // MARK: - Order Summary

    @ViewBuilder
    private var orderSummarySection: some View {
        GlassCard(cornerRadius: 22, showsBorder: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption)
                        .foregroundStyle(TBTheme.icyBlue)
                    Text("Order Summary")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                }

                ForEach(itemsBySeller, id: \.sellerId) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 34)
                            Text("From \(sellerDisplayName(for: group.sellerId))")
                        }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(TBTheme.skyBlue)

                        ForEach(group.items) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.product.name)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(TBTheme.deepSky)
                                        .lineLimit(1)
                                    if let color = item.selectedColor {
                                        HStack(spacing: 5) {
                                            ProductColorSwatch(hex: color.hex, size: 12)
                                            Text(color.name)
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(item.quantity) × \(Money.format(cents: item.product.priceCents))")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider().background(Color.secondary.opacity(0.2))

                HStack {
                    Text("Subtotal")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(cents: cart.subtotalCents))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                HStack {
                    Text("Shipping")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(cart.shippingCents == 0 ? "Free" : Money.format(cents: cart.shippingCents))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(cart.shippingCents == 0 ? .green : TBTheme.deepSky)
                }
                HStack {
                    Text("Total")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                    Spacer()
                    Text(Money.format(cents: cart.totalCents))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.icyBlue)
                }
            }
        }
        .padding(.horizontal)

        if itemsBySeller.count > 1 {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .font(.caption2)
                Text("Items may ship separately from different sellers.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
    }

    // MARK: - Shipping

    private var shippingSection: some View {
        GlassCard(cornerRadius: 22, showsBorder: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(TBTheme.icyBlue)
                    Text("Shipping Address")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                }

                CheckoutField(
                    label: "Email",
                    text: $email,
                    icon: "envelope",
                    focus: $focusedField,
                    focusValue: .email
                )
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)

                CheckoutField(
                    label: "Full name",
                    text: $name,
                    icon: "person",
                    focus: $focusedField,
                    focusValue: .name
                )
                    .textContentType(.name)

                CheckoutField(
                    label: "Address",
                    text: $line1,
                    icon: "house",
                    focus: $focusedField,
                    focusValue: .line1
                )
                    .textContentType(.streetAddressLine1)

                CheckoutField(
                    label: "Apt, suite (optional)",
                    text: $line2,
                    icon: nil,
                    focus: $focusedField,
                    focusValue: .line2
                )
                    .textContentType(.streetAddressLine2)

                HStack(spacing: TBTheme.spacingMD) {
                    CheckoutField(
                        label: "City",
                        text: $city,
                        icon: nil,
                        focus: $focusedField,
                        focusValue: .city
                    )
                        .textContentType(.addressCity)
                    CheckoutField(
                        label: "State",
                        text: $state,
                        icon: nil,
                        focus: $focusedField,
                        focusValue: .state
                    )
                        .textContentType(.addressState)
                        .textInputAutocapitalization(.characters)
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: TBTheme.spacingMD) {
                    CheckoutField(
                        label: "ZIP",
                        text: $postalCode,
                        icon: nil,
                        focus: $focusedField,
                        focusValue: .postalCode
                    )
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .frame(maxWidth: .infinity)
                    CheckoutField(
                        label: "Country",
                        text: $country,
                        icon: nil,
                        focus: $focusedField,
                        focusValue: .country
                    )
                        .textContentType(.countryName)
                        .textInputAutocapitalization(.characters)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Policy Agreement

    private var policyAgreementSection: some View {
        HStack(alignment: .top, spacing: TBTheme.spacingMD) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                agreedToTerms.toggle()
            } label: {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(agreedToTerms ? TBTheme.icyBlue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(agreedToTerms ? "Terms accepted" : "Accept terms")
            .accessibilityHint("Double tap to toggle agreement with the Terms of Service, Privacy Policy, and Exchange Policy.")

            policyAgreementText
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var policyAgreementText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("By placing your order, you agree to our ")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                presentedLegal = .termsOfService
            } label: {
                Text("Terms of Service")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkout.policy.terms")
            Text(", ")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                presentedLegal = .privacyPolicy
            } label: {
                Text("Privacy Policy")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkout.policy.privacy")
            Text(", and ")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                presentedLegal = .exchangePolicy
            } label: {
                Text("Exchange Policy")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkout.policy.exchange")
            Text(".")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .tint(TBTheme.icyBlue)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pay Button

    @ViewBuilder
    private var payButton: some View {
        Button {
            Task { await createAndPresentPayment() }
        } label: {
            ZStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack {
                        Text(isCheckoutReady
                             ? "Pay \(Money.format(cents: cart.totalCents))"
                             : "Checkout Unavailable")
                            .contentTransition(.numericText())
                        Image(systemName: isCheckoutReady ? "creditcard.fill" : "lock.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        .buttonStyle(PrimaryCTAButtonStyle())
        .disabled(!canProceed || isSubmitting || cart.subtotalCents < minimumOrderCents || !isCheckoutReady)
        .opacity(canProceed && !isSubmitting && cart.subtotalCents >= minimumOrderCents && isCheckoutReady ? 1 : 0.6)
        .padding(.horizontal)
        .accessibilityIdentifier("checkout.pay")
        .accessibilityHint("Places your order and opens payment when checkout is ready.")
        .animation(reduceMotion ? nil : TBMotion.stateChange, value: isSubmitting)

        if cart.subtotalCents < minimumOrderCents {
            Text("Minimum order \(Money.format(cents: minimumOrderCents)) to proceed.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        } else if !isCheckoutReady {
            Text(AppConstants.checkoutSetupMessage)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }

        if !isSubmitting, let firstReason = checkoutBlockingReasons.first {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                Text(firstReason)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    @MainActor
    private func createAndPresentPayment() async {
        errorMessage = nil
        paymentSheetRetainer = nil

        guard isCheckoutReady else {
            errorMessage = AppConstants.checkoutSetupMessage
            return
        }

        guard cart.subtotalCents >= minimumOrderCents else {
            errorMessage = "Minimum order is \(Money.format(cents: minimumOrderCents))."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard trimmedName.count >= 2 else {
            errorMessage = "Enter the full name for this order."
            return
        }

        guard !trimmedAddressLine1.isEmpty, !trimmedCity.isEmpty else {
            errorMessage = "Enter the full shipping address."
            return
        }

        guard isValidUSState(normalizedState) else {
            errorMessage = "Enter a valid 2-letter state code."
            return
        }

        guard isValidUSPostalCode(normalizedPostalCode) else {
            errorMessage = "Enter a valid ZIP code."
            return
        }

        guard normalizedCountry == "US" else {
            errorMessage = "Checkout currently supports US shipping only."
            return
        }

        guard agreedToTerms else {
            errorMessage = "Please accept Terms, Privacy, and Exchange Policy."
            return
        }

        if AppConstants.isTestingOverridesEnabled && !AppConstants.hasLiveCheckoutConfiguration {
            isSubmitting = true
            let simulatedOrderId = "TB-TEST-\(Int(Date().timeIntervalSince1970))"
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {}
            isSubmitting = false
            completeSuccessfulCheckout(orderIdentifier: simulatedOrderId)
            return
        }

        isSubmitting = true

        do {
            try await MarketplaceAuthSession.ensureCheckoutSession(
                email: trimmedEmail,
                fullName: trimmedName
            )
        } catch let apiError as BuyerAccountAPIError where apiError.code == "buyer_account_exists" {
            errorMessage = apiError.message
            isSubmitting = false
            return
        } catch let apiError as BuyerAccountAPIError {
            errorMessage = friendlyGuestCheckoutErrorMessage(apiError.message)
            isSubmitting = false
            return
        } catch let checkoutError as CheckoutAPIError {
            errorMessage = checkoutError.message
            isSubmitting = false
            return
        } catch {
            errorMessage = friendlyCheckoutErrorMessage(for: error)
            isSubmitting = false
            return
        }

        let req = CreatePaymentIntentRequest(
            email: trimmedEmail,
            shipping: ShippingAddress(
                name: trimmedName,
                line1: trimmedAddressLine1,
                line2: trimmedAddressLine2.isEmpty ? nil : trimmedAddressLine2,
                city: trimmedCity,
                state: normalizedState,
                postalCode: normalizedPostalCode,
                country: normalizedCountry
            ),
            items: cart.items.map {
                CheckoutItem(
                    productId: $0.product.id,
                    selectedColorId: $0.selectedColor?.id,
                    quantity: $0.quantity
                )
            }
        )

        do {
            let response = try await CheckoutAPI.createPaymentIntent(req: req)
            orderId = response.orderId

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "TenBelow"
            configuration.paymentMethodOrder = ["card"]

            let sheet = PaymentSheet(
                paymentIntentClientSecret: response.clientSecret,
                configuration: configuration
            )

            isSubmitting = false

            #if os(iOS)
            presentPaymentSheetFromKeyWindow(sheet)
            #else
            errorMessage = "Payments are only supported on iOS."
            #endif
            return
        } catch {
            errorMessage = friendlyCheckoutErrorMessage(for: error)
        }
        isSubmitting = false
    }

    @MainActor
    private func handlePaymentCompletion(_ result: PaymentSheetResult) {
        paymentSheetRetainer = nil
        switch result {
        case .completed:
            if let id = orderId {
                completeSuccessfulCheckout(orderIdentifier: id)
            }
        case .canceled:
            break
        case .failed(let error):
            errorMessage = friendlyCheckoutErrorMessage(for: error)
        }
    }

    #if os(iOS)
    /// Presents Stripe using UIKit. The SwiftUI `.paymentSheet` modifier can crash on recent OS/SDK builds when the view tree toggles.
    private func presentPaymentSheetFromKeyWindow(_ sheet: PaymentSheet) {
        dismissKeyboard()
        DispatchQueue.main.async {
            guard let presenter = Self.topMostViewController() else {
                errorMessage = "Could not open the payment screen. Please try again."
                return
            }
            paymentSheetRetainer = sheet
            sheet.present(from: presenter) { result in
                Task { @MainActor in
                    handlePaymentCompletion(result)
                }
            }
        }
    }

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let window = windowScene?.windows.first(where: \.isKeyWindow) ?? windowScene?.windows.first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif

    @MainActor
    private func completeSuccessfulCheckout(orderIdentifier: String) {
        let purchasedProducts = cart.items.map(\.product)
        buyerEmail = trimmedEmail
        buyerHasPlacedOrder = true
        orderStore.placeOrder(
            orderId: orderIdentifier,
            items: cart.items,
            buyerEmail: trimmedEmail,
            shipToCity: trimmedCity,
            shipToState: normalizedState
        )
        buyerEngagement.trackPurchase(products: purchasedProducts)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await orderStore.refreshBuyerOrders(email: trimmedEmail)
        }
        onSuccess(orderIdentifier)
        cart.clear()
    }

    #if os(iOS)
    @MainActor
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    private func friendlyGuestCheckoutErrorMessage(_ message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("cannot post /auth/guest-checkout-session")
            || lowered.contains("<!doctype html>")
            || lowered.contains("<html") {
            return "Guest checkout is not live on the server yet. Deploy the latest TenBelow backend to Render, wait for the deploy to finish, then try again."
        }
        return message
    }

    private func friendlyCheckoutErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Reconnect to finish checkout."
            case .timedOut:
                return "Checkout took too long to respond. Please try again."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func isValidUSState(_ state: String) -> Bool {
        state.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil
    }

    private func isValidUSPostalCode(_ postalCode: String) -> Bool {
        postalCode.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil
    }
}

// MARK: - Checkout Field

private struct CheckoutField: View {
    let label: String
    @Binding var text: String
    var icon: String? = nil
    var focus: FocusState<CheckoutFocusField?>.Binding
    var focusValue: CheckoutFocusField

    private var isFocused: Bool {
        focus.wrappedValue == focusValue
    }

    private var checkoutFieldAccessibilityIdentifier: String {
        switch label {
        case "Email": return "checkout.field.email"
        case "Full name": return "checkout.field.fullName"
        case "Address": return "checkout.field.addressLine1"
        case "Apt, suite (optional)": return "checkout.field.addressLine2"
        case "City": return "checkout.field.city"
        case "State": return "checkout.field.state"
        case "ZIP": return "checkout.field.postalCode"
        case "Country": return "checkout.field.country"
        default: return "checkout.field.other"
        }
    }

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(isFocused ? 0.88 : 0.7))
            .cornerRadius(TBTheme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .strokeBorder(
                        isFocused ? TBTheme.accent.opacity(0.55) : Color.secondary.opacity(0.2),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .focused(focus, equals: focusValue)
            .autocorrectionDisabled()
            .accessibilityIdentifier(checkoutFieldAccessibilityIdentifier)
            .animation(TBMotion.stateChange, value: isFocused)
    }
}

