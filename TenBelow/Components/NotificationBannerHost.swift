//
//  NotificationBannerHost.swift
//  TenBelow
//
//  The single app-level overlay that draws transient in-app notification banners.
//
//  It lives above the tab bar in `AppRootView`, so a banner looks and behaves the same on
//  Home, Shop, Weekly Drop, Orders, and Settings. No screen owns its own banner instance.
//

import SwiftUI

struct NotificationBannerHost: View {
    @EnvironmentObject private var bannerCenter: NotificationBannerCenter
    @EnvironmentObject private var notifications: NotificationStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var orderStore: OrderStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Banners are only drawn once the user is in the app proper, never over the splash,
    /// role picker, or onboarding.
    let isEligible: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let request = bannerCenter.current, isEligible {
                InAppNotificationBanner(
                    notification: request.notification,
                    context: context(for: request.notification),
                    openAction: { open(request.notification) },
                    dismissAction: { bannerCenter.dismissCurrent() },
                    pressChanged: { bannerCenter.setInteracting($0) }
                )
                .padding(.horizontal, 14)
                .transition(.tbNotificationBanner(reduceMotion: reduceMotion))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.92),
            value: bannerCenter.current?.id
        )
        .accessibilitySortPriority(1)
        .onAppear {
            bannerCenter.setSceneActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            bannerCenter.setSceneActive(phase == .active)
        }
    }

    private func context(for notification: AppNotification) -> NotificationBannerContext {
        NotificationBannerContext(
            orderLabel: orderLabel(for: notification),
            productImageReference: productImageReference(for: notification)
        )
    }

    private func orderLabel(for notification: AppNotification) -> String? {
        guard let orderId = notification.relatedOrderId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !orderId.isEmpty,
              let order = orderStore.order(withId: orderId)
        else { return nil }

        let number = order.orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return number.isEmpty ? nil : number
    }

    private func productImageReference(for notification: AppNotification) -> String? {
        guard let productId = notification.relatedProductId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty
        else { return nil }

        let products = resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
        return products.first(where: { $0.id == productId })?.primaryImageReference
            ?? localProducts.product(withId: productId)?.primaryImageReference
    }

    /// Routes to the destinations that already exist. Tab selection goes through
    /// `TabLaunchBridge` so the host does not need to own `MainTabView`'s selection state.
    private func open(_ notification: AppNotification) {
        notifications.markAsRead(notification.id)

        if shouldOpenOrders(for: notification) {
            if let orderId = notification.relatedOrderId {
                OrderNavigationBridge.requestOpenOrder(orderId: orderId)
            } else {
                TabLaunchBridge.requestTab(MainTab.orders.rawValue)
            }
        } else if notification.relatedProductId != nil {
            TabLaunchBridge.requestTab(MainTab.store.rawValue)
        } else {
            TabLaunchBridge.requestTab(MainTab.home.rawValue)
        }

        bannerCenter.dismissCurrent()
    }

    private func shouldOpenOrders(for notification: AppNotification) -> Bool {
        switch notification.type {
        case .orderReceived:
            return UserDefaults.standard.string(forKey: "userRole") == "seller"
        case .orderStatusUpdate, .orderSupportUpdate:
            return notification.relatedOrderId != nil
        case .exchangeUpdate:
            return notification.relatedOrderId != nil
                || notification.relatedExchangeRequestId != nil
        default:
            return notification.relatedOrderId != nil
        }
    }
}
