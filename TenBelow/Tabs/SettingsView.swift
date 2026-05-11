//
//  SettingsView.swift
//  TenBelow
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("sellerAccountCreated") private var sellerAccountCreated = false
    #if DEBUG
    @AppStorage(AppConstants.testingModeUserDefaultsKey) private var testingModeEnabled = false
    @AppStorage("buyerDropPreviewMode") private var buyerDropPreviewMode = false
    #endif
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SnowfallTitleContainer(
                        cornerRadius: 26,
                        horizontalPadding: 8,
                        verticalPadding: 14,
                        flakeCount: 78,
                        effectHorizontalInset: 18,
                        effectVerticalInset: 16
                    ) {
                        Image("SettingsTitle")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 108)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                }

                if userRole == "seller" {
                    Section("Seller membership") {
                        NavigationLink {
                            SellerSubscriptionView()
                                .environmentObject(sellerSubscription)
                        } label: {
                            Label("Manage seller membership", systemImage: "creditcard")
                        }
                    }
                }

                Section("Account") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notification settings", systemImage: "bell.badge")
                    }

                    if userRole != "seller" {
                        if sellerAccountCreated {
                            Button {
                                switchAppMode(to: "seller", launchTab: 1)
                            } label: {
                                Label("Switch to seller mode", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            }
                        } else {
                            NavigationLink {
                                SellOnTenBelowLandingView()
                            } label: {
                                Label("Become a seller", systemImage: "storefront")
                            }
                        }
                    }

                    if userRole == "seller" {
                        Button {
                            switchAppMode(to: "buyer", launchTab: 0)
                        } label: {
                            Label("Switch to buyer mode", systemImage: "arrow.triangle.2.circlepath.circle")
                        }
                    }
                }

                Section("Legal") {
                    NavigationLink("View terms of service") {
                        LegalDocumentView(document: .termsOfService)
                    }

                    NavigationLink("View privacy policy") {
                        LegalDocumentView(document: .privacyPolicy)
                    }

                    NavigationLink("View DMCA policy") {
                        LegalDocumentView(document: .dmcaPolicy)
                    }

                    NavigationLink("View seller agreement") {
                        LegalDocumentView(document: .sellerAgreement)
                    }

                    NavigationLink("View exchange policy") {
                        LegalDocumentView(document: .exchangePolicy)
                    }
                }

                #if DEBUG
                Section {
                    Toggle("Testing mode (relaxed checkout)", isOn: $testingModeEnabled)
                    Toggle("Sample Drop lineup (Drop tab)", isOn: $buyerDropPreviewMode)
                    DebugBackendURLField()
                } header: {
                    Text("Developer")
                } footer: {
                    Text(
                        "Testing mode allows checkout and related flows without a live backend URL and Stripe publishable key, using simulated behavior where applicable. "
                            + "For a real iPhone, run the full backend on your Mac and set “Backend URL (this device)” to http://YOUR_MAC_LAN_IP:3000 (same Wi‑Fi). "
                            + "Match BACKEND_URL in TenBelow/tenbelow-backend/.env to that URL so /media links resolve."
                    )
                }
                #endif
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

#if DEBUG
private struct DebugBackendURLField: View {
    @AppStorage(AppConstants.debugBackendBaseURLOverrideKey) private var overrideURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend URL (this device)")
                .font(.subheadline.weight(.semibold))

            TextField("http://192.168.1.12:3000", text: $overrideURL)
                #if os(iOS)
                .keyboardType(.URL)
                .textContentType(.URL)
                #endif
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Clear override (use Xcode plist URL)") {
                overrideURL = ""
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)

            if let active = AppConstants.backendBaseURL {
                Text("Active: \(active.absoluteString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No backend URL — enable Testing mode or set an override.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif

