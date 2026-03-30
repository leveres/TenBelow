//
//  CheckoutView.swift
//  TenBelow
//

import SwiftUI
import StripePaymentSheet

#if os(iOS)
import UIKit
#endif

struct CheckoutView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var orderStore: OrderStore
    @Environment(\.openURL) private var openURL
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
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
    @State private var showPaymentSheet = false
    @State private var paymentSheet: PaymentSheet?

    private var isCheckoutReady: Bool {
        AppConstants.isBackendConfigured && AppConstants.isStripeConfigured
    }

    private var minimumOrderCents: Int {
        catalog.config.minimumOrderCents
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
            }
            .scrollDismissesKeyboard(.interactively)

            if isSubmitting {
                AppLoadingOverlay(
                    title: "Preparing Payment",
                    subtitle: "Securing your order details."
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onAppear {
            errorMessage = nil
            if email.isEmpty { email = buyerEmail }
            if name.isEmpty { name = buyerFullName }
        }

        if let paymentSheet {
            content.paymentSheet(
                isPresented: $showPaymentSheet,
                paymentSheet: paymentSheet,
                onCompletion: handlePaymentCompletion
            )
        } else {
            content
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
                                .frame(width: 34, height: 34)
                            Text("From \(sellerDisplayName(for: group.sellerId))")
                        }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(TBTheme.skyBlue)

                        ForEach(group.items) { item in
                            HStack {
                                Text(item.product.name)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(TBTheme.deepSky)
                                    .lineLimit(1)
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
                    Text("Set by seller")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                    Spacer()
                    Text(Money.format(cents: cart.subtotalCents))
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

                CheckoutField(label: "Email", text: $email, icon: "envelope")
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)

                CheckoutField(label: "Full name", text: $name, icon: "person")
                    .textContentType(.name)

                CheckoutField(label: "Address", text: $line1, icon: "house")
                    .textContentType(.streetAddressLine1)

                CheckoutField(label: "Apt, suite (optional)", text: $line2, icon: nil)
                    .textContentType(.streetAddressLine2)

                HStack(spacing: TBTheme.spacingMD) {
                    CheckoutField(label: "City", text: $city, icon: nil)
                        .textContentType(.addressCity)
                    CheckoutField(label: "State", text: $state, icon: nil)
                        .textContentType(.addressState)
                        .textInputAutocapitalization(.characters)
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: TBTheme.spacingMD) {
                    CheckoutField(label: "ZIP", text: $postalCode, icon: nil)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .frame(maxWidth: .infinity)
                    CheckoutField(label: "Country", text: $country, icon: nil)
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
            Link("Terms of Service", destination: AppConstants.termsURL)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(", ")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(", and ")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Link("Exchange Policy", destination: AppConstants.exchangePolicyURL)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            if isSubmitting {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                HStack {
                    Text(isCheckoutReady
                         ? "Pay \(Money.format(cents: cart.subtotalCents))"
                         : "Checkout Unavailable")
                    Image(systemName: isCheckoutReady ? "lock.fill" : "clock")
                        .font(.caption.weight(.semibold))
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(PrimaryCTAButtonStyle())
        .disabled(!canProceed || isSubmitting || cart.subtotalCents < minimumOrderCents || !isCheckoutReady)
        .opacity(canProceed && !isSubmitting && cart.subtotalCents >= minimumOrderCents && isCheckoutReady ? 1 : 0.6)
        .padding(.horizontal)

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
    }

    // MARK: - Actions

    @MainActor
    private func createAndPresentPayment() async {
        errorMessage = nil
        showPaymentSheet = false
        paymentSheet = nil

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

        isSubmitting = true

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
            items: cart.items.map { CheckoutItem(productId: $0.product.id, quantity: $0.quantity) }
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

            #if os(iOS)
            dismissKeyboard()
            #endif

            paymentSheet = sheet
            isSubmitting = false

            // Stripe's SwiftUI presenter can fail silently if the sheet is requested
            // in the same update cycle that creates it, especially after text input.
            DispatchQueue.main.async {
                showPaymentSheet = true
            }
            return
        } catch {
            errorMessage = friendlyCheckoutErrorMessage(for: error)
        }
        isSubmitting = false
    }

    @MainActor
    private func handlePaymentCompletion(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            if let id = orderId {
                let purchasedProducts = cart.items.map(\.product)
                orderStore.placeOrder(
                    orderId: id,
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
                onSuccess(id)
            }
            cart.clear()
        case .canceled:
            break
        case .failed(let error):
            errorMessage = friendlyCheckoutErrorMessage(for: error)
        }
    }

    #if os(iOS)
    @MainActor
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

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

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.7))
            .cornerRadius(TBTheme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .autocorrectionDisabled()
    }
}

#Preview {
    CheckoutView(onSuccess: { _ in })
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
}
