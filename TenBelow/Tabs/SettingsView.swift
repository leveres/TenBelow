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
    @AppStorage("sellerSellerId") private var sellerSellerId = ""
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let metrics = SettingsScreenMetrics.resolved(for: proxy.size.height)

                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    settingsTitle(height: metrics.titleHeight)

                    if userRole == "seller" {
                        settingsSection("Seller membership") {
                            settingsNavigationRow(
                                title: "Manage seller membership",
                                systemImage: "creditcard",
                                rowHeight: metrics.rowHeight
                            ) {
                                SellerSubscriptionView()
                                    .environmentObject(sellerSubscription)
                            }
                        }
                    }

                    sellerAccountSection(rowHeight: metrics.rowHeight, footerFontSize: metrics.footerFontSize)
                    accountSection(rowHeight: metrics.rowHeight)
                    legalSection(rowHeight: metrics.compactRowHeight)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .background(TBTheme.cloudWhite)
            }
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

    private func settingsTitle(height: CGFloat) -> some View {
        SnowfallTitleContainer(
            cornerRadius: 26,
            horizontalPadding: 8,
            verticalPadding: 2,
            flakeCount: 78,
            effectHorizontalInset: 18,
            effectVerticalInset: 16
        ) {
            Image("SettingsTitle")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .scaleEffect(1.10)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sellerAccountSection(rowHeight: CGFloat, footerFontSize: CGFloat) -> some View {
        settingsSection("Seller account") {
            if userRole == "seller" {
                if !sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settingsStaticRow(title: sellerSellerId, systemImage: "person.text.rectangle", rowHeight: rowHeight)
                }

                if !sellerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settingsStaticRow(title: sellerEmail, systemImage: "envelope", rowHeight: rowHeight)
                }

                settingsButtonRow(
                    title: "Sign out of seller account",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    isDestructive: true,
                    rowHeight: rowHeight,
                    action: signOutSeller
                )

                Text("Seller sign-out only removes this device's seller session. Your shop stays on TenBelow.")
                    .font(.system(size: footerFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, -2)
                    .padding(.bottom, 2)
            } else {
                settingsNavigationRow(title: "Sign in as seller", systemImage: "storefront", rowHeight: rowHeight) {
                    RolePickerView(startInSellerAccount: true, sellerEntryMode: .signIn)
                }
            }
        }
    }

    private func accountSection(rowHeight: CGFloat) -> some View {
        settingsSection("Account") {
            settingsNavigationRow(title: "Notification settings", systemImage: "bell.badge", rowHeight: rowHeight) {
                NotificationSettingsView()
            }

            if userRole != "seller" {
                if sellerAccountCreated {
                    settingsButtonRow(
                        title: "Switch to seller mode",
                        systemImage: "arrow.triangle.2.circlepath.circle.fill",
                        rowHeight: rowHeight
                    ) {
                        switchAppMode(to: "seller", launchTab: 1)
                    }
                } else {
                    settingsNavigationRow(title: "Become a seller", systemImage: "storefront", rowHeight: rowHeight) {
                        RolePickerView(startInSellerAccount: true, sellerEntryMode: .create)
                    }
                }
            }

            if userRole == "seller" {
                settingsButtonRow(
                    title: "Switch to buyer mode",
                    systemImage: "arrow.triangle.2.circlepath.circle",
                    rowHeight: rowHeight
                ) {
                    switchAppMode(to: "buyer", launchTab: 0)
                }
            }
        }
    }

    private func legalSection(rowHeight: CGFloat) -> some View {
        settingsSection("Legal") {
            settingsNavigationRow(title: "View terms of service", rowHeight: rowHeight) {
                LegalDocumentView(document: .termsOfService)
            }
            settingsNavigationRow(title: "View privacy policy", rowHeight: rowHeight) {
                LegalDocumentView(document: .privacyPolicy)
            }
            settingsNavigationRow(title: "View DMCA policy", rowHeight: rowHeight) {
                LegalDocumentView(document: .dmcaPolicy)
            }
            settingsNavigationRow(title: "View seller agreement", rowHeight: rowHeight) {
                LegalDocumentView(document: .sellerAgreement)
            }
            settingsNavigationRow(title: "View exchange policy", rowHeight: rowHeight) {
                LegalDocumentView(document: .exchangePolicy)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func settingsNavigationRow<Destination: View>(
        title: String,
        systemImage: String? = nil,
        rowHeight: CGFloat,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingsRowContent(title: title, systemImage: systemImage, rowHeight: rowHeight, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func settingsStaticRow(title: String, systemImage: String, rowHeight: CGFloat) -> some View {
        settingsRowContent(title: title, systemImage: systemImage, rowHeight: rowHeight, showsChevron: false)
    }

    private func settingsButtonRow(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        rowHeight: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowContent(
                title: title,
                systemImage: systemImage,
                rowHeight: rowHeight,
                showsChevron: false,
                foregroundColor: isDestructive ? .red : TBTheme.deepSky
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsRowContent(
        title: String,
        systemImage: String?,
        rowHeight: CGFloat,
        showsChevron: Bool,
        foregroundColor: Color = .primary
    ) -> some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TBTheme.deepSky.opacity(0.82))
                    .frame(width: 26)
            }

            Text(title)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(height: 0.6)
                .padding(.leading, systemImage == nil ? 16 : 54)
                .padding(.trailing, 16)
        }
    }

    private func signOutSeller() {
        MarketplaceAuthSession.clearSellerSession()
        sellerAccountCreated = false
        sellerPreviewMode = false
        switchAppMode(to: "buyer", launchTab: 0)
    }

    private func switchAppMode(to role: String, launchTab: Int) {
        userRole = role
        pendingLaunchTab = launchTab

        Task {
            await MarketplaceAuthSession.syncAfterIdentityChange()
            if role == "seller" {
                await sellerSubscription.refresh()
            }
        }
    }
}

private struct SettingsScreenMetrics {
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let horizontalPadding: CGFloat
    let sectionSpacing: CGFloat
    let titleHeight: CGFloat
    let rowHeight: CGFloat
    let compactRowHeight: CGFloat
    let footerFontSize: CGFloat

    static func resolved(for height: CGFloat) -> SettingsScreenMetrics {
        if height < 720 {
            return SettingsScreenMetrics(
                topPadding: 2,
                bottomPadding: 8,
                horizontalPadding: 12,
                sectionSpacing: 8,
                titleHeight: 76,
                rowHeight: 44,
                compactRowHeight: 40,
                footerFontSize: 11
            )
        }

        return SettingsScreenMetrics(
            topPadding: 6,
            bottomPadding: 10,
            horizontalPadding: 14,
            sectionSpacing: 8,
            titleHeight: 82,
            rowHeight: 46,
            compactRowHeight: 42,
            footerFontSize: 12
        )
    }
}
