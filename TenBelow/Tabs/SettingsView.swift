//
//  SettingsView.swift
//  TenBelow
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Image("SettingsTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 38)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 0))
                }

                Section("Account") {
                    NavigationLink {
                        SellOnTenBelowGatewayView()
                    } label: {
                        Label("Sell on TenBelow", systemImage: "storefront")
                    }
                }

                Section("Legal") {
                    Button("Terms of Service") {
                        openURL(AppConstants.termsURL)
                    }

                    Button("IP Policy") {
                        openURL(AppConstants.ipPolicyURL)
                    }

                    Button("DMCA") {
                        openURL(AppConstants.dmcaURL)
                    }

                    Button("Seller Agreement") {
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
        }
    }
}

#Preview {
    SettingsView()
}
