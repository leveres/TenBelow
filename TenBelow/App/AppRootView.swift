//
//  AppRootView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct AppRootView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @State private var showSplash = true
    @State private var splashOpacity = 1.0
    @State private var destinationOpacity = 0.0
    @State private var hasStartedSplashTransition = false
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    @AppStorage("userRole") var userRole = ""
    #if os(iOS)
    @AppStorage("sellerSellerId") private var sellerSellerId = ""
    @AppStorage("sellerAccountCreated") private var sellerAccountCreated = false
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = "guest"
    @AppStorage("buyerHasPlacedOrder") private var buyerHasPlacedOrder = false
    #endif

    var body: some View {
        ZStack {
            destinationContent
                .opacity(showSplash ? destinationOpacity : 1.0)
                .allowsHitTesting(!showSplash)

            if showSplash {
                SplashView {
                    beginSplashCrossDissolve()
                }
                .opacity(splashOpacity)
                .zIndex(1)
            }
        }
        .task(id: cartSyncTaskKey) {
            guard !showSplash else { return }
            let availableProducts = resolvedStorefrontProducts(
                remoteProducts: catalog.products,
                fallbackProducts: localProducts.products
            )
            cart.syncAvailableProducts(availableProducts)
        }
        #if os(iOS)
        .task(id: "\(userRole)|\(sellerSellerId)|\(buyerEmail)|\(buyerAccountCreated)") {
            await MarketplaceAuthSession.syncAfterIdentityChange()
            await PushDeviceRegistration.syncAfterIdentityChange()
        }
        .task(id: notificationPromptFingerprint) {
            guard shouldRequestNotificationPermission else { return }
            await AppDelegate.ensureNotificationsAuthorizedIfNeeded()
        }
        #endif
    }

    @ViewBuilder
    private var destinationContent: some View {
        if userRole.isEmpty {
            RolePickerView()
        } else if !hasSeenOnboarding {
            OnboardingView()
        } else {
            MainTabView()
        }
    }

    private func beginSplashCrossDissolve() {
        guard !hasStartedSplashTransition else { return }
        hasStartedSplashTransition = true

        withAnimation(.easeInOut(duration: 0.5)) {
            destinationOpacity = 1.0
            splashOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showSplash = false
        }
    }

    private var cartSyncTaskKey: String {
        "\(showSplash)|\(catalog.contentRevision)|\(localProducts.productsRevision)"
    }

    #if os(iOS)
    private var shouldRequestNotificationPermission: Bool {
        guard hasSeenOnboarding, !userRole.isEmpty else { return false }

        if userRole == "seller" {
            return sellerAccountCreated && !sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return buyerHasPlacedOrder && !buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var notificationPromptFingerprint: String {
        "\(hasSeenOnboarding)|\(userRole)|\(sellerAccountCreated)|\(sellerSellerId)|\(buyerAccountCreated)|\(buyerEmail)|\(buyerCheckoutPreference)|\(buyerHasPlacedOrder)"
    }
    #endif
}


