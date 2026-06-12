import SwiftUI

struct WishlistView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        resolvedSellerProfilesByID(
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private var savedProducts: [Product] {
        let favoriteIDs = buyerEngagement.favoriteProductIDs
        return storefrontProducts
            .filter { favoriteIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        Group {
            if savedProducts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(savedProducts) { product in
                            ProductCard(
                                product: product,
                                seller: sellerProfilesByID[product.sellerId],
                                allProducts: storefrontProducts,
                                style: .compact,
                                showsAccentBorder: true
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(TBFrostBackground())
        .navigationTitle("Wishlist")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(TBTheme.icyBlue)

            Text("Nothing saved yet")
                .font(.tbHeadline)
                .foregroundStyle(TBTheme.deepSky)

            Text("Tap the heart on any product in Shop to build your wishlist.")
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
