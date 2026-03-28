//
//  SettingsView.swift
//  TenBelow
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("sellerAccountCreated") private var sellerAccountCreated = false
    @State private var showSellerMembershipSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SnowfallTitleContainer(cornerRadius: 24, horizontalPadding: 12, verticalPadding: 10, flakeCount: 68) {
                        Image("SettingsTitle")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 52)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 0))
                }

                if userRole == "seller" {
                    Section("Seller membership") {
                        SellerMembershipSummaryCard {
                            showSellerMembershipSheet = true
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }

                Section("Account") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notification settings", systemImage: "bell.badge")
                    }

                    if sellerAccountCreated, userRole != "seller" {
                        Button {
                            switchAppMode(to: "seller", launchTab: 1)
                        } label: {
                            Label("Switch to seller mode", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        }
                    }

                    if userRole == "seller" {
                        Button {
                            switchAppMode(to: "buyer", launchTab: 0)
                        } label: {
                            Label("Switch to buyer mode", systemImage: "arrow.triangle.2.circlepath.circle")
                        }
                    }

                    NavigationLink {
                        SellOnTenBelowGatewayView()
                    } label: {
                        Label(sellerAccountCreated ? "Manage seller account" : "Become a seller", systemImage: "storefront")
                    }
                }

                Section("Legal") {
                    Button("View terms of service") {
                        openURL(AppConstants.termsURL)
                    }

                    Button("View IP policy") {
                        openURL(AppConstants.ipPolicyURL)
                    }

                    Button("View DMCA policy") {
                        openURL(AppConstants.dmcaURL)
                    }

                    Button("View seller agreement") {
                        openURL(AppConstants.sellerAgreementURL)
                    }
                }
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showSellerMembershipSheet) {
                SellerSubscriptionView()
                    .environmentObject(sellerSubscription)
            }
            .task(id: userRole) {
                guard userRole == "seller" else { return }
                await sellerSubscription.refresh()
            }
        }
    }

    private func switchAppMode(to role: String, launchTab: Int) {
        userRole = role
        pendingLaunchTab = launchTab
    }
}

#Preview {
    let events = CommerceEventStore()
    let engagement = BuyerEngagementStore(eventStore: events)
    let products = LocalProductStore(eventStore: events)
    let orders = OrderStore(eventStore: events)
    return SettingsView()
        .environmentObject(
            NotificationStore(
                eventStore: events,
                buyerEngagement: engagement,
                localProducts: products,
                orderStore: orders
            )
        )
        .environmentObject(SellerSubscriptionStore.previewInactive)
}
