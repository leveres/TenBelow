import SwiftUI

struct PublicSellerProfileView: View {
    let seller: SellerProfile
    let products: [Product]
    var avatarNamespace: Namespace.ID? = nil

    @EnvironmentObject private var cart: CartStore
    @Environment(\.openURL) private var openURL
    @State private var isLoading = true

    private var sellerProducts: [Product] {
        products.filter { $0.sellerId == seller.id }
    }

    var body: some View {
        Group {
            if isLoading {
                skeletonContent
            } else {
                loadedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await reloadProfile()
        }
    }

    // MARK: - Banner Header

    private var bannerHeader: some View {
        ZStack(alignment: .bottom) {
            bannerGradient
                .frame(height: 100)

            HStack(alignment: .bottom, spacing: TBTheme.spacingLG) {
                profileAvatar
                    .offset(y: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(seller.displayName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if seller.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    Text(seller.handle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 10) {
                        Text("\(seller.productCount) products")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))

                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                            Text(formattedLikes)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.bottom, TBTheme.spacingMD)
        }
        .padding(.bottom, 12)
    }

    private var bannerGradient: some View {
        LinearGradient(
            colors: [
                TBTheme.deepSky,
                TBTheme.skyBlue,
                TBTheme.skyLight.opacity(0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarNamespace {
            avatarView
                .matchedGeometryEffect(id: "sellerAvatar", in: avatarNamespace)
        } else {
            avatarView
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 56, height: 56)
                .shadow(color: TBTheme.deepSky.opacity(0.15), radius: 8, y: 4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [TBTheme.skyLight, TBTheme.skyBlue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)

            Text(avatarInitials)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
        }
    }

    private var avatarInitials: String {
        let words = seller.displayName.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined()
    }

    // MARK: - Badges (compact pills)

    private var badgeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SellerBadge(
                    text: seller.designLicense,
                    icon: "doc.text.fill",
                    tint: TBTheme.deepSky
                )
                SellerBadge(
                    text: "Ships in \(seller.shipsInDays.lowerBound)–\(seller.shipsInDays.upperBound) days",
                    icon: "shippingbox"
                )
                SellerBadge(
                    text: seller.location,
                    icon: "location.fill"
                )
                if seller.isVerified {
                    SellerBadge(text: "Verified", icon: "checkmark.seal.fill", tint: .green)
                }
            }
        }
    }

    // MARK: - Products Section (single row, fits screen)

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            HStack {
                Text("Products")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Spacer()

                if !sellerProducts.isEmpty {
                    NavigationLink {
                        SellerAllProductsView(seller: seller, products: sellerProducts)
                    } label: {
                        Text("See All")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(TBTheme.accent)
                    }
                }
            }

            if sellerProducts.isEmpty {
                emptyProductsState
                    .padding(.vertical, TBTheme.spacingMD)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TBTheme.spacingMD) {
                        ForEach(sellerProducts) { product in
                            ProductCard(product: product)
                                .frame(width: 140)
                        }
                    }
                }
                .frame(height: 260)
            }
        }
    }

    private var emptyProductsState: some View {
        GlassCard {
            VStack(spacing: TBTheme.spacingSM) {
                Image(systemName: "cube")
                    .font(.system(size: 24))
                    .foregroundStyle(TBTheme.skyBlue.opacity(0.5))

                Text("No products yet")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TBTheme.spacingLG)
        }
    }

    // MARK: - About Section (compact)

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            Text(seller.bio)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(2)
                .lineLimit(2)

            if let url = seller.websiteURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .medium))
                        Text(url.absoluteString)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(TBTheme.accent)
                }
                .buttonStyle(.plain)
            }

        }
    }

    private var formattedLikes: String {
        let count = seller.likeCount
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    // MARK: - Loading & Skeleton

    private var loadedContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                bannerHeader

                badgeRow
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.top, TBTheme.spacingSM)

                aboutCard
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.top, TBTheme.spacingSM)

                HStack(spacing: TBTheme.spacingMD) {
                    Button {} label: {
                        Label("Message", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(PrimaryCTAButtonStyle())

                    Button {} label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(SecondaryCTAButtonStyle())
                }
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

                productsSection
                    .padding(.top, TBTheme.spacingLG)
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.bottom, TBTheme.spacingXL)
            }
        }
    }

    private var skeletonContent: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TBTheme.skyLight.opacity(0.6))
                .frame(height: 112)

            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .fill(TBTheme.skyLight.opacity(0.4))
                .frame(height: 28)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .fill(TBTheme.skyLight.opacity(0.35))
                .frame(height: 52)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .fill(TBTheme.skyLight.opacity(0.35))
                .frame(height: 44)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

            VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .fill(TBTheme.skyLight.opacity(0.35))
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(TBTheme.skyLight.opacity(0.35))
                    .frame(height: 200)
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingLG)

            Spacer(minLength: 0)
        }
        .redacted(reason: .placeholder)
    }

    private func reloadProfile() async {
        await MainActor.run {
            isLoading = true
        }

        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s shimmer-style pause

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - About Badge Pill (reference-style: icon + title + chevron)

private struct AboutBadgePill: View {
    let icon: String
    let title: String
    var tint: Color = TBTheme.icyBlue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Featured Product Card

private struct FeaturedProductCard: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            Image(product.imageNames.first ?? "")
                .resizable()
                .scaledToFill()
                .frame(width: 150, height: 120)
                .clipped()
                .cornerRadius(TBTheme.radiusMD)

            Text(product.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .lineLimit(1)

            Text(Money.format(cents: product.priceCents))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.icyBlue)
        }
        .frame(width: 150)
        .padding(TBTheme.spacingSM)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TBTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Seller All Products (full grid via See All)

private struct SellerAllProductsView: View {
    let seller: SellerProfile
    let products: [Product]

    private let gridColumns = [
        GridItem(.flexible(), spacing: TBTheme.spacingMD),
        GridItem(.flexible(), spacing: TBTheme.spacingMD)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: TBTheme.spacingMD) {
                ForEach(products) { product in
                    ProductCard(product: product)
                }
            }
            .padding()
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle(seller.displayName)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Flow Layout (for material chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.origins[index].x,
                y: bounds.minY + result.origins[index].y
            )
            subview.place(at: point, proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, origins: [CGPoint])
    {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), origins)
    }
}

// MARK: - Preview

#Preview("Public Profile") {
    NavigationStack {
        PublicSellerProfileView(
            seller: .sample,
            products: MockData.products
        )
        .environmentObject(CartStore())
    }
}

#Preview("Empty Seller") {
    NavigationStack {
        PublicSellerProfileView(
            seller: .sampleSecond,
            products: []
        )
        .environmentObject(CartStore())
    }
}
