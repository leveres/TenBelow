//
//  NotificationBannerPreviewView.swift
//  TenBelow
//
//  DEBUG-only gallery for reviewing every in-app banner variant.
//

import SwiftUI

#if DEBUG
struct NotificationBannerPreviewView: View {
    private enum Audience: String, CaseIterable, Identifiable {
        case buyer = "Buyer"
        case seller = "Seller"
        var id: String { rawValue }
    }

    @State private var audience: Audience = .buyer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Audience", selection: $audience) {
                    ForEach(Audience.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("These are sample banners using the live component. They are not added to your inbox.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(samples(for: audience)) { sample in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sample.label)
                            .font(.tbCaption.weight(.semibold))
                            .foregroundStyle(TBTheme.icyBlue)

                        InAppNotificationBanner(
                            notification: sample.notification,
                            context: sample.context,
                            openAction: {},
                            dismissAction: {}
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(TBFrostBackground())
        .navigationTitle("Banner preview")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func samples(for audience: Audience) -> [PreviewSample] {
        audience == .buyer ? Self.buyerSamples : Self.sellerSamples
    }
}

private struct PreviewSample: Identifiable {
    let id: String
    let label: String
    let notification: AppNotification
    let context: NotificationBannerContext
}

private extension NotificationBannerPreviewView {
    static let buyerSamples: [PreviewSample] = [
        sample(
            id: "price-drop",
            label: "Price drop",
            userId: "buyer:preview",
            type: .priceDrop,
            title: "Price drop",
            message: "Frost Knit Beanie just dropped to $24.00. Grab it before it's gone.",
            productId: "preview-product",
            image: "preview"
        ),
        sample(
            id: "new-drop",
            label: "New drop",
            userId: "buyer:preview",
            type: .newProduct,
            title: "New Drop from Northwind Studio",
            message: "They just added Glacier Mittens. Check it out.",
            productId: "preview-product",
            image: "preview"
        ),
        sample(
            id: "order-confirmed",
            label: "Order confirmed",
            userId: "buyer:preview",
            type: .orderStatusUpdate,
            title: "Order confirmed",
            message: "We’ll keep you updated on Frost Knit Beanie.",
            orderId: "preview-order",
            productId: "preview-product",
            orderLabel: "TB-8F42C7",
            image: "preview"
        ),
        sample(
            id: "production",
            label: "Production started",
            userId: "buyer:preview",
            type: .orderStatusUpdate,
            title: "Production started",
            message: "Your Frost Knit Beanie is being made.",
            orderId: "preview-order",
            productId: "preview-product",
            orderLabel: "TB-8F42C7",
            image: "preview"
        ),
        sample(
            id: "shipped",
            label: "Order shipped",
            userId: "buyer:preview",
            type: .orderStatusUpdate,
            title: "Order shipped",
            message: "Frost Knit Beanie is on the way. Tracking: USPS 9400111899223851.",
            orderId: "preview-order",
            productId: "preview-product",
            orderLabel: "TB-8F42C7",
            image: "preview"
        ),
        sample(
            id: "delivered",
            label: "Order delivered",
            userId: "buyer:preview",
            type: .orderStatusUpdate,
            title: "Order delivered",
            message: "Frost Knit Beanie has been delivered.",
            orderId: "preview-order",
            productId: "preview-product",
            orderLabel: "TB-8F42C7",
            image: "preview"
        ),
        sample(
            id: "cancelled",
            label: "Shipment cancelled",
            userId: "buyer:preview",
            type: .orderStatusUpdate,
            title: "Shipment cancelled",
            message: "Frost Knit Beanie was cancelled for this order.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "refund-approved",
            label: "Refund approved",
            userId: "buyer:preview",
            type: .orderSupportUpdate,
            title: "Refund request approved",
            message: "Your refund request for Frost Knit Beanie was approved.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "seller-message",
            label: "Seller message",
            userId: "buyer:preview",
            type: .orderSupportUpdate,
            title: "Seller message",
            message: "Ships tomorrow morning. I’ll add the tracking number as soon as the label prints.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "exchange-approved",
            label: "Exchange approved",
            userId: "buyer:preview",
            type: .exchangeUpdate,
            title: "Exchange approved",
            message: "Your replacement request was approved.",
            orderId: "preview-order",
            exchangeId: "preview-exchange",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "more-info",
            label: "More info needed",
            userId: "buyer:preview",
            type: .exchangeUpdate,
            title: "More info needed",
            message: "Add more proof to keep your exchange request moving.",
            orderId: "preview-order",
            exchangeId: "preview-exchange",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "replacement-shipped",
            label: "Replacement shipped",
            userId: "buyer:preview",
            type: .exchangeUpdate,
            title: "Replacement shipped",
            message: "Your replacement is on the way.",
            orderId: "preview-order",
            exchangeId: "preview-exchange",
            orderLabel: "TB-8F42C7"
        ),
    ]

    static let sellerSamples: [PreviewSample] = [
        sample(
            id: "new-order",
            label: "New order",
            userId: "seller:preview",
            type: .orderReceived,
            title: "New order received",
            message: "You received a new order for Frost Knit Beanie. Open Orders to fulfill it.",
            orderId: "preview-order",
            productId: "preview-product",
            orderLabel: "TB-8F42C7",
            image: "preview"
        ),
        sample(
            id: "buyer-request",
            label: "New buyer request",
            userId: "seller:preview",
            type: .orderSupportUpdate,
            title: "New buyer request",
            message: "A buyer submitted a refund request for Frost Knit Beanie.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "buyer-message",
            label: "Buyer message",
            userId: "seller:preview",
            type: .orderSupportUpdate,
            title: "Buyer message",
            message: "Can you ship this without the gift note? Thanks.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "withdrawn",
            label: "Request withdrawn",
            userId: "seller:preview",
            type: .orderSupportUpdate,
            title: "Request withdrawn",
            message: "The buyer withdrew their refund request for order TB-8F42C7.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
        sample(
            id: "action-needed",
            label: "Action needed",
            userId: "seller:preview",
            type: .system,
            title: "Action needed",
            message: "Update your order status to keep buyers informed.",
            orderId: "preview-order",
            orderLabel: "TB-8F42C7"
        ),
    ]

    static func sample(
        id: String,
        label: String,
        userId: String,
        type: NotificationType,
        title: String,
        message: String,
        orderId: String? = nil,
        productId: String? = nil,
        exchangeId: String? = nil,
        orderLabel: String? = nil,
        image: String? = nil
    ) -> PreviewSample {
        PreviewSample(
            id: id,
            label: label,
            notification: AppNotification(
                id: id,
                userId: userId,
                type: type,
                title: title,
                message: message,
                relatedProductId: productId,
                relatedOrderId: orderId,
                relatedExchangeRequestId: exchangeId,
                createdAt: .now
            ),
            context: NotificationBannerContext(
                orderLabel: orderLabel,
                productImageReference: image
            )
        )
    }
}
#endif
