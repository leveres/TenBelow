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
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
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
        .animation(.easeInOut(duration: 0.35), value: hasSeenOnboarding)
        .task(id: cartSyncFingerprint) {
            let availableProducts = resolvedStorefrontProducts(
                remoteProducts: catalog.products,
                fallbackProducts: localProducts.products
            )
            cart.syncAvailableProducts(availableProducts)
        }
        #if os(iOS)
        .task(id: "\(userRole)|\(sellerSellerId)|\(buyerEmail)|\(buyerAccountCreated)") {
            await PushDeviceRegistration.syncAfterIdentityChange()
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

    private var cartSyncFingerprint: String {
        let remoteFingerprint = catalog.products
            .map { "\($0.id):\($0.priceCents):\($0.isActive):\($0.isApproved)" }
            .joined(separator: "|")
        let fallbackFingerprint = localProducts.products
            .map { "\($0.id):\($0.priceCents)" }
            .joined(separator: "|")
        return "\(remoteFingerprint)#\(fallbackFingerprint)"
    }
}

#Preview("Main App") {
    AppRootView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(LocalProductStore(eventStore: CommerceEventStore()))
        .environmentObject(SellerSubscriptionStore.previewActive)
}

#Preview("Onboarding") {
    OnboardingView()
}
