//
//  SellerDashboardView.swift
//  TenBelow
//

import SwiftUI

struct SellerDashboardView: View {
    let seller: SellerProfile
    let products: [Product]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TBTheme.spacingLG) {
                    headerCard
                    primaryActions
                    secondaryActions
                    settingsSection
                }
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)
                .padding(.bottom, TBTheme.spacingXXL)
            }
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard(cornerRadius: 26) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.9))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(avatarInitials)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(TBTheme.deepSky)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(seller.displayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(TBTheme.deepSky)

                        if seller.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(TBTheme.accent)
                        }

                        Spacer()

                        NavigationLink {
                            EditSellerProfileView()
                        } label: {
                            Text("Edit")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(TBTheme.icyBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(TBTheme.skyBlue.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(seller.handle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        chip(icon: "shippingbox", text: "Ships in \(seller.shipsInDays.lowerBound)–\(seller.shipsInDays.upperBound) days")
                        chip(icon: "paperplane.fill", text: seller.location)
                    }
                }
            }
            .contentShape(Rectangle())
        }
    }

    private var avatarInitials: String {
        let words = seller.displayName.split(separator: " ")
        return words.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.55))
        .overlay(
            Capsule()
                .stroke(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
        )
        .clipShape(Capsule())
        .foregroundStyle(TBTheme.deepSky)
    }

    // MARK: - Actions

    private var primaryActions: some View {
        NavigationLink {
            AddProductView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text("Add Product")
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [TBTheme.accent, TBTheme.deepSky],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: TBTheme.accent.opacity(0.25), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var secondaryActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                SellerProductsView()
            } label: {
                secondaryButton(icon: "cube.box", title: "My Products")
            }
            .buttonStyle(.plain)

            NavigationLink {
                SellerStorePreviewView(seller: seller, products: products)
            } label: {
                secondaryButton(icon: "eye", title: "Store Preview")
            }
            .buttonStyle(.plain)
        }
    }

    private func secondaryButton(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(title)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(TBTheme.deepSky)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTINGS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            GlassCard(cornerRadius: 22) {
                VStack(spacing: 0) {
                    NavigationLink {
                        ShippingSettingsView()
                    } label: {
                        settingsRow(icon: "shippingbox", title: "Shipping Settings", subtitle: "Rates, regions, processing time")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SellerPoliciesView()
                    } label: {
                        settingsRow(icon: "doc.text", title: "Policies", subtitle: "Returns, refunds, exchanges")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SupportView()
                    } label: {
                        settingsRow(icon: "questionmark.circle", title: "Support", subtitle: "Help center & contact")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        PayoutSettingsView()
                    } label: {
                        settingsRow(icon: "dollarsign.circle", title: "Payout", subtitle: "Bank account, schedule")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(TBTheme.icyBlue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(TBTheme.deepSky)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    SellerDashboardView(seller: .sample, products: MockData.products)
}
