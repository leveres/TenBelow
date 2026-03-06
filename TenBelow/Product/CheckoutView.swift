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
    @Environment(\.openURL) private var openURL
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

    private var minimumOrderCents: Int {
        catalog.config.minimumOrderCents
    }

    private var canProceed: Bool {
        !email.isEmpty && !name.isEmpty && !line1.isEmpty && !city.isEmpty && !state.isEmpty && !postalCode.isEmpty && agreedToTerms
    }

    private var itemsBySeller: [(sellerId: String, items: [CartItem])] {
        Dictionary(grouping: cart.items, by: { $0.product.sellerId })
            .sorted { $0.key < $1.key }
            .map { (sellerId: $0.key, items: $0.value)
        }
    }

    var body: some View {
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

                orderSummarySection

                shippingSection

                policyAgreementSection

                payButton
            }
            .padding(.vertical, TBTheme.spacingLG)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { errorMessage = nil }
        .paymentSheet(
            isPresented: $showPaymentSheet,
            paymentSheet: paymentSheet!,
            onCompletion: handlePaymentCompletion
        )
    }

    // MARK: - Order Summary

    @ViewBuilder
    private var orderSummarySection: some View {
        GlassCard(cornerRadius: 22) {
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
                        Text("From \(group.sellerId.replacingOccurrences(of: "seller_", with: "Seller #"))")
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
                    Text("FREE")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
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
        GlassCard(cornerRadius: 22) {
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
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: TBTheme.spacingMD) {
                    CheckoutField(label: "ZIP", text: $postalCode, icon: nil)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .frame(maxWidth: .infinity)
                    CheckoutField(label: "Country", text: $country, icon: nil)
                        .textContentType(.countryName)
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
            Link("Refund Policy", destination: AppConstants.refundPolicyURL)
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
                    Text("Pay \(Money.format(cents: cart.subtotalCents))")
                    Image(systemName: "lock.fill")
                        .font(.caption)
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(PrimaryCTAButtonStyle())
        .disabled(!canProceed || isSubmitting || cart.subtotalCents < minimumOrderCents)
        .opacity(canProceed && !isSubmitting && cart.subtotalCents >= minimumOrderCents ? 1 : 0.6)
        .padding(.horizontal)

        if cart.subtotalCents < minimumOrderCents {
            Text("Minimum order \(Money.format(cents: minimumOrderCents)) to proceed.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func createAndPresentPayment() async {
        errorMessage = nil

        guard cart.subtotalCents >= minimumOrderCents else {
            errorMessage = "Minimum order is \(Money.format(cents: minimumOrderCents))."
            return
        }

        guard agreedToTerms else {
            errorMessage = "Please agree to the Terms and policies to continue."
            return
        }

        isSubmitting = true

        let req = CreatePaymentIntentRequest(
            email: email,
            shipping: ShippingAddress(
                name: name,
                line1: line1,
                line2: line2.isEmpty ? nil : line2,
                city: city,
                state: state,
                postalCode: postalCode,
                country: country
            ),
            items: cart.items.map { CheckoutItem(productId: $0.product.id, quantity: $0.quantity) }
        )

        do {
            let response = try await CheckoutAPI.createPaymentIntent(req: req)
            orderId = response.orderId

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "TenBelow"

            paymentSheet = PaymentSheet(
                paymentIntentClientSecret: response.clientSecret,
                configuration: configuration
            )
            showPaymentSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func handlePaymentCompletion(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            if let id = orderId {
                onSuccess(id)
            }
            cart.clear()
        case .canceled:
            break
        case .failed(let error):
            errorMessage = error.localizedDescription
        }
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
