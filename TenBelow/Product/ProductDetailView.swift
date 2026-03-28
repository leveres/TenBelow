//
//  ProductDetailView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import AVKit
import Combine

struct ProductDetailView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var localProducts: LocalProductStore
    let product: Product

    @State private var addedToCart = false
    @State private var showCart = false
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var selectedMediaIndex = 0
    @State private var showFullscreenMedia = false
    @State private var showReportListingHelp = false

    private var sellerProfile: SellerProfile? {
        resolvedSellerProfile(
            sellerId: product.sellerId,
            storefrontProducts: sellerProducts,
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private var sellerProducts: [Product] {
        let storefrontProducts = resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
        return storefrontProducts.filter { $0.sellerId == product.sellerId }
    }

    private var mediaCount: Int {
        product.imageNames.count + (product.demoVideoURL == nil ? 0 : 1)
    }

    private func reportListing(product: Product) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        guard let url = ReportListingMail.mailtoURL(for: product) else {
            showReportListingHelp = true
            return
        }

        PlatformURLOpener.open(url) {
            showReportListingHelp = true
        }
    }

    private func handleAddToCart() {
        cart.add(product)
        buyerEngagement.trackAddToCart(product)

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        withAnimation(.easeInOut(duration: 0.25)) {
            addedToCart = true
        }

        scheduleToastDismiss()
    }

    private func scheduleToastDismiss() {
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    addedToCart = false
                }
            }
        }
    }

    private func openCartFromToast() {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            addedToCart = false
        }
        showCart = true
    }

    private var isFavorited: Bool {
        buyerEngagement.isProductFavorited(product.id)
    }

    private var showsFavoriteButton: Bool {
        buyerEngagement.showsFavoriteButton(for: product)
    }

    private func toggleFavorite() {
        let isNowFavorited = buyerEngagement.toggleFavorite(for: product)
        localProducts.setFavoriteState(for: product.id, isFavorited: isNowFavorited)
    }

    @ViewBuilder
    private var productMediaHero: some View {
        ZStack(alignment: .bottomLeading) {
            TabView(selection: $selectedMediaIndex) {
                ForEach(Array(product.imageNames.enumerated()), id: \.offset) { index, name in
                    productDetailImagePage(name: name, index: index)
                }

                if let url = product.demoVideoURL {
                    productDetailVideoPage(url: url)
                }
            }
            .frame(height: 336)
            #if os(iOS) || os(visionOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            LinearGradient(
                colors: [.black.opacity(0.16), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            .allowsHitTesting(false)

            productMediaOverlayChrome
        }
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
    }

    @ViewBuilder
    private func productDetailImagePage(name: String, index: Int) -> some View {
        StorefrontImageView(reference: name) {
            ZStack {
                TBTheme.skyLight.opacity(0.42)
                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 336)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                showFullscreenMedia = true
            }
        )
        .accessibilityLabel("Product photo \(index + 1) of \(product.imageNames.count). Tap to view full screen.")
        .accessibilityAddTraits(.isButton)
        .tag(index)
    }

    @ViewBuilder
    private func productDetailVideoPage(url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 336)
                .clipShape(RoundedRectangle(cornerRadius: 0))

            Button {
                showFullscreenMedia = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Open video full screen")
        }
        .tag(product.imageNames.count)
    }

    @ViewBuilder
    private var productMediaOverlayChrome: some View {
        HStack(alignment: .bottom) {
            MediaPagePill(
                currentIndex: selectedMediaIndex,
                totalCount: mediaCount
            )

            Spacer()

            if mediaCount > 0 {
                Button {
                    showFullscreenMedia = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Expand")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.38), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View media full screen")
            }

            if product.demoVideoURL != nil, selectedMediaIndex == product.imageNames.count {
                MediaKindPill(label: "Video")
            }
        }
        .padding(16)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    productMediaHero

                    // Title + Price
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.tbProductTitleXL)
                                .tracking(-0.3)
                                .tbProductNameTitleStyle()

                            Text(Money.format(cents: product.priceCents))
                                .font(.tbProductPriceMD)
                                .foregroundStyle(.primary.opacity(0.82))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ProductStatusBadge(
                                text: product.productionNote,
                                icon: "checkmark.seal"
                            )

                            Text("Ships from seller")
                                .font(.tbCaption)
                                .foregroundStyle(.tertiary)
                        }

                        if let sellerProfile {
                            NavigationLink {
                                PublicSellerProfileView(
                                    seller: sellerProfile,
                                    products: sellerProducts.isEmpty ? [product] : sellerProducts
                                )
                            } label: {
                                SellerAttributionRow(seller: sellerProfile)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Quick facts
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick facts")
                            .font(.tbHeadline)
                            .foregroundStyle(TBTheme.icyBlue)

                        VStack(spacing: 0) {
                            QuickFactRow(title: "Material", value: product.material)
                            Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                            QuickFactRow(
                                title: "Ships",
                                value: "\(product.shipsInDays.lowerBound)–\(product.shipsInDays.upperBound) business days"
                            )
                            Divider().overlay(TBTheme.skyBlue.opacity(0.10))
                            QuickFactRow(title: "Category", value: product.category.rawValue)
                        }
                        .padding(20)
                        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
                    }

                    // Durability note
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Durability")
                            .font(.tbHeadline)
                            .tracking(-0.1)
                            .foregroundStyle(TBTheme.deepSky.opacity(0.92))

                        Text(product.durabilityNote)
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }

                    // Care + warnings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Care & Warnings")
                            .font(.tbHeadline)
                            .tracking(-0.1)
                            .foregroundStyle(TBTheme.deepSky.opacity(0.92))

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(product.careWarnings, id: \.self) { warning in
                                CareWarningRow(text: warning)
                            }
                        }
                    }

                }
                .padding()
            }

            // Toast banner
            if addedToCart {
                AddedToCartToast(
                    productName: product.name,
                    onViewCart: openCartFromToast
                )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        // Shop root hides the bar; restore it for pushed product detail (back button + actions).
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if showsFavoriteButton {
                        Button {
                            toggleFavorite()
                        } label: {
                            Image(systemName: isFavorited ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(isFavorited ? TBTheme.accent : TBTheme.deepSky)
                        }
                        .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
                    }

                    Button {
                        reportListing(product: product)
                    } label: {
                        Image(systemName: "flag")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(TBTheme.deepSky)
                    }
                    .accessibilityLabel("Report listing")
                }
            }
        }
        #endif
        .sheet(isPresented: $showCart) {
            CartView()
                .environmentObject(cart)
                .environmentObject(catalog)
                .environmentObject(localProducts)
        }
        .sheet(isPresented: $showReportListingHelp) {
            ReportListingFallbackSheet(product: product)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StickyBuyBar(
                productName: product.name,
                priceText: Money.format(cents: product.priceCents),
                isAdded: addedToCart,
                action: handleAddToCart
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(
                LinearGradient(
                    colors: [
                        TBTheme.cloudWhite.opacity(0.0),
                        TBTheme.cloudWhite.opacity(0.82),
                        TBTheme.cloudWhite
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .onAppear {
            selectedMediaIndex = 0
            buyerEngagement.trackProductView(product)
            localProducts.registerProductView(for: product.id)
        }
        .onDisappear {
            toastDismissTask?.cancel()
        }
        .fullScreenCover(isPresented: $showFullscreenMedia) {
            ProductMediaFullscreenView(
                product: product,
                initialIndex: selectedMediaIndex
            )
        }
    }
}

// MARK: - Full screen product media (photos + demo video)

private struct ProductMediaFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var selectedIndex: Int

    init(product: Product, initialIndex: Int) {
        self.product = product
        _selectedIndex = State(initialValue: initialIndex)
    }

    private var mediaCount: Int {
        product.imageNames.count + (product.demoVideoURL == nil ? 0 : 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if mediaCount == 0 {
                    ContentUnavailableView("No media", systemImage: "photo")
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(product.imageNames.enumerated()), id: \.offset) { index, name in
                            ProductFullscreenZoomableImage(imageReference: name)
                                .tag(index)
                        }

                        if let url = product.demoVideoURL {
                            VideoPlayer(player: AVPlayer(url: url))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .tag(product.imageNames.count)
                        }
                    }
                    #if os(iOS) || os(visionOS)
                    .tabViewStyle(.page(indexDisplayMode: mediaCount > 1 ? .automatic : .never))
                    #endif
                }
            }
            .navigationTitle("Media")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct ProductFullscreenZoomableImage: View {
    let imageReference: String
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        StorefrontImageView(reference: imageReference, contentMode: .fit) {
            ZStack {
                Color.black.opacity(0.2)
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let next = baseScale * value
                        scale = min(max(next, 1), 5)
                    }
                    .onEnded { _ in
                        baseScale = scale
                        if scale < 1.02 {
                            scale = 1
                            baseScale = 1
                        }
                    }
            )
            .padding(12)
    }
}

private struct MediaPagePill: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        Text("\(currentIndex + 1) of \(max(totalCount, 1))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.22), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}

private struct StickyBuyBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let productName: String
    let priceText: String
    let isAdded: Bool
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                productInfo
                Spacer(minLength: 12)
                buyButton
            }

            VStack(alignment: .leading, spacing: 12) {
                productInfo
                buyButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.72), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }

    private var productInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(productName)
                .font(.tbProductTitleSM)
                .tbProductNameTitleStyle()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            Text(priceText)
                .font(.tbProductPriceSM)
                .foregroundStyle(.primary.opacity(0.82))
        }
    }

    private var buyButton: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isAdded ? "checkmark" : "cart.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(isAdded ? "Added" : "Add to Cart")
                    .font(.body.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [TBTheme.accent, TBTheme.deepSky],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MediaKindPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.22), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}

private struct SellerAttributionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let seller: SellerProfile

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.96), TBTheme.skyLight.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 0.8)
                    )

                Text(initials)
                    .font(.tbMeta)
                    .foregroundStyle(TBTheme.deepSky)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(seller.displayName)
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                    if seller.showsVerifiedBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TBTheme.accent)
                    }
                }

                Text("Ships in \(seller.shipsInDays.lowerBound)-\(seller.shipsInDays.upperBound) days")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
    }

    private var initials: String {
        let chars = seller.displayName.split(separator: " ").prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "TB" : String(chars)
    }
}

private struct ProductStatusBadge: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.tbMeta)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(TBTheme.deepSky)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.76), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.02), radius: 8, y: 4)
    }
}

private struct QuickFactRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(.primary.opacity(0.92))

            Spacer(minLength: 12)

            Text(value)
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }
}

private struct CareWarningRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.55))
                    .frame(width: 22, height: 22)

                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TBTheme.icyBlue)
            }
            .padding(.top, 1)

            Text(text)
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AddedToCartToast: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let productName: String
    let onViewCart: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                toastMessage
                Spacer(minLength: 8)
                viewCartButton
            }

            VStack(alignment: .leading, spacing: 10) {
                toastMessage
                viewCartButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [TBTheme.accent, TBTheme.skyBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: TBTheme.accent.opacity(0.35), radius: 12, y: 6)
        )
        .clipShape(Capsule())
        .padding(.horizontal, 16)
    }

    private var toastMessage: some View {
        HStack(spacing: 10) {
            Image(systemName: "cart.badge.plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)

            Text("\(productName) added to cart")
                .font(.tbBodyStrong)
                .foregroundStyle(.white)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    private var viewCartButton: some View {
        Button(action: onViewCart) {
            HStack(spacing: 4) {
                Text("View Cart")
                Image(systemName: "arrow.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let events = CommerceEventStore()
    NavigationStack {
        ProductDetailView(product: MockData.products[0])
    }
    .environmentObject(CartStore())
    .environmentObject(CatalogStore())
    .environmentObject(BuyerEngagementStore(eventStore: events))
    .environmentObject(LocalProductStore(eventStore: events))
}
