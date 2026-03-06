import SwiftUI

struct BuyerProfileView: View {
    private let sampleSellers: [SellerProfile] = [.sample, .sampleSecond]
    private let recentOrders = Array(SampleOrders.data.prefix(3))

    var body: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingXXL) {
                headerSection
                trendingSellersSection
                categoriesSection

                if !recentOrders.isEmpty {
                    recentOrdersSection
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle("Profile")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: TBTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TBTheme.skyLight, TBTheme.skyBlue.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "person.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(TBTheme.deepSky)
            }

            VStack(spacing: 4) {
                Text("Welcome to TenBelow")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.frostTitleGradient)

                Text("Discover 3D-printed products, all $10 and under.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {} label: {
                Label("Sign In", systemImage: "person.badge.key")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .buttonStyle(SecondaryCTAButtonStyle())
            .frame(width: 200)
        }
        .padding(.top, TBTheme.spacingXL)
        .padding(.horizontal, TBTheme.spacingLG)
    }

    // MARK: - Trending Sellers

    private var trendingSellersSection: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            Text("Trending Sellers")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .padding(.horizontal, TBTheme.spacingLG)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TBTheme.spacingMD) {
                    ForEach(sampleSellers) { seller in
                        NavigationLink {
                            PublicSellerProfileView(seller: seller, products: MockData.products)
                        } label: {
                            SellerCard(seller: seller)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TBTheme.spacingLG)
            }
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            Text("Browse Categories")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .padding(.horizontal, TBTheme.spacingLG)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TBTheme.spacingMD) {
                    ForEach(tbCategories) { cat in
                        NavigationLink {
                            if let filterCat = cat.filterCategory {
                                CategoryView(category: filterCat)
                            } else {
                                CategoryView(allProducts: cat)
                            }
                        } label: {
                            CategoryTile(category: cat)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TBTheme.spacingLG)
            }
        }
    }

    // MARK: - Recent Orders

    private var recentOrdersSection: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            HStack {
                Text("Recent Orders")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Spacer()

                NavigationLink {
                    OrdersView()
                } label: {
                    Text("See All")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.accent)
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)

            VStack(spacing: TBTheme.spacingSM) {
                ForEach(recentOrders) { order in
                    NavigationLink {
                        OrderDetailView(order: order, mode: .buyer)
                    } label: {
                        CompactOrderRow(order: order)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)
        }
    }
}

// MARK: - Seller Card (horizontal scroll)

private struct SellerCard: View {
    let seller: SellerProfile

    private var initials: String {
        let words = seller.displayName.split(separator: " ")
        return words.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    var body: some View {
        VStack(spacing: TBTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TBTheme.skyLight, TBTheme.skyBlue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                Text(initials)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
            }

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(seller.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                        .lineLimit(1)

                    if seller.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TBTheme.accent)
                    }
                }

                Text(seller.handle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SellerBadge(
                text: "\(seller.shipsInDays.lowerBound)–\(seller.shipsInDays.upperBound) days",
                icon: "shippingbox"
            )
        }
        .frame(width: 160)
        .padding(TBTheme.spacingLG)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TBTheme.radiusXL))
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusXL)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.05), radius: 8, y: 3)
    }
}

// MARK: - Compact Order Row

private struct CompactOrderRow: View {
    let order: Order

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(order.shipments.first?.items.first?.productName ?? "Order")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .lineLimit(1)

                Text(Self.dateFormatter.string(from: order.createdAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(Money.format(cents: order.totalCents))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.icyBlue)

            StatusChip(status: order.status)
        }
        .padding(TBTheme.spacingMD)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TBTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        BuyerProfileView()
    }
    .environmentObject(CartStore())
    .environmentObject(CatalogStore())
}
