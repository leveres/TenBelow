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
    @EnvironmentObject private var orderStore: OrderStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    let product: Product

    @State private var addedToCart = false
    @State private var showCart = false
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var selectedMediaIndex = 0
    @State private var showFullscreenMedia = false
    @State private var showReportListingHelp = false
    @State private var showRatingSheet = false
    @State private var selectedRating = 0
    @State private var ratingReviewText = ""
    @State private var isSubmittingRating = false
    @State private var ratingErrorMessage: String?
    @State private var ratingSuccessMessage: String?
    @State private var latestAverageRating: Double?
    @State private var latestReviewCount: Int?
    @State private var loadedReviews: [ProductReview] = []

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

    private var featuredVideoURL: URL? {
        product.demoVideoURL
    }

    private var featuredVideoLabel: String {
        "Creator clip"
    }

    private var mediaCount: Int {
        product.imageNames.count + (featuredVideoURL == nil ? 0 : 1)
    }

    private var isInCart: Bool {
        cart.items.contains { $0.product.id == product.id }
    }

    private var displayedAverageRating: Double {
        latestAverageRating ?? product.averageRating
    }

    private var displayedReviewCount: Int {
        latestReviewCount ?? product.reviewCount
    }

    private var deliveredOrderForRating: Order? {
        guard userRole != "seller" else { return nil }

        return orderStore.orders.first { order in
            (order.shipments).contains { shipment in
                let delivered = shipment.status == .delivered || order.status == .delivered
                let matchesProduct = shipment.items.contains { $0.productId == product.id }
                return delivered && matchesProduct
            }
        }
    }

    private var hasPurchasedProduct: Bool {
        orderStore.orders.contains { order in
            order.shipments.contains { shipment in
                shipment.items.contains { $0.productId == product.id }
            }
        }
    }

    private var canRateProduct: Bool {
        guard let order = deliveredOrderForRating else { return false }
        let normalizedBuyerEmail = order.buyerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !normalizedBuyerEmail.isEmpty
    }

    private var hasFeaturedVideo: Bool {
        featuredVideoURL != nil
    }

    private var displayedReviews: [ProductReview] {
        Array(loadedReviews.prefix(3))
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
        if isInCart {
            showCart = true
            return
        }

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

    @MainActor
    private func submitRating() async {
        guard let order = deliveredOrderForRating,
              let buyerEmail = order.buyerEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !buyerEmail.isEmpty else {
            ratingErrorMessage = "You can rate this product after a delivered order is linked to your account."
            return
        }

        guard (1...5).contains(selectedRating) else {
            ratingErrorMessage = "Choose a star rating from 1 to 5."
            return
        }

        ratingErrorMessage = nil
        ratingSuccessMessage = nil
        isSubmittingRating = true
        defer { isSubmittingRating = false }

        do {
            let response = try await ProductReviewsAPI.submitReview(
                orderId: order.id,
                productId: product.id,
                buyerEmail: buyerEmail,
                rating: selectedRating,
                reviewText: ratingReviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ratingReviewText
            )
            latestAverageRating = response.averageRating
            latestReviewCount = response.reviewCount
            ratingSuccessMessage = "Thanks for rating this product."
            await loadReviews()
            catalogRefreshToken += 1
            showRatingSheet = false
        } catch {
            ratingErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadReviews() async {
        guard AppConstants.isBackendConfigured else { return }
        do {
            let response = try await ProductReviewsAPI.fetchReviews(for: product.id)
            latestAverageRating = response.averageRating
            latestReviewCount = response.reviewCount
            loadedReviews = response.reviews
        } catch {
            // Keep the current summary from product data if fetching reviews fails.
        }
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

                if let url = featuredVideoURL {
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

            if featuredVideoURL != nil, selectedMediaIndex == product.imageNames.count {
                MediaKindPill(label: featuredVideoLabel)
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

                        productRatingSection

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

                    if hasFeaturedVideo {
                        watchHowItsMadeSection
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
        .sheet(isPresented: $showRatingSheet) {
            ProductRatingSheet(
                productName: product.name,
                selectedRating: $selectedRating,
                reviewText: $ratingReviewText,
                isSubmitting: isSubmittingRating,
                onSubmit: {
                    Task { await submitRating() }
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StickyBuyBar(
                productName: product.name,
                priceText: Money.format(cents: product.priceCents),
                isAdded: isInCart,
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
            latestAverageRating = product.averageRating
            latestReviewCount = product.reviewCount
            Task { await loadReviews() }
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

    private var productRatingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProductRatingStars(rating: displayedAverageRating)
                VStack(alignment: .leading, spacing: 2) {
                    if displayedReviewCount > 0 {
                        Text(String(format: "%.1f out of 5", displayedAverageRating))
                            .font(.tbBodyStrong)
                            .foregroundStyle(.primary.opacity(0.9))
                        Text("\(displayedReviewCount) \(displayedReviewCount == 1 ? "rating" : "ratings")")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No ratings yet")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if canRateProduct {
                Button {
                    if selectedRating == 0 {
                        selectedRating = 5
                    }
                    showRatingSheet = true
                } label: {
                    Label("Rate this product", systemImage: "star.bubble.fill")
                        .font(.tbCaption.weight(.semibold))
                        .foregroundStyle(TBTheme.icyBlue)
                }
                .buttonStyle(.plain)
            } else if hasPurchasedProduct {
                Text("You can rate this product after it is delivered.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !displayedReviews.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent reviews")
                        .font(.tbCaption.weight(.semibold))
                        .foregroundStyle(TBTheme.deepSky)

                    ForEach(displayedReviews) { review in
                        ProductReviewCard(review: review)
                    }
                }
            }

            if let ratingSuccessMessage {
                Text(ratingSuccessMessage)
                    .font(.tbCaption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ratingErrorMessage {
                Text(ratingErrorMessage)
                    .font(.tbCaption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var watchHowItsMadeSection: some View {
        GlassCard(cornerRadius: 22, showsBorder: false) {
            Button {
                selectedMediaIndex = product.imageNames.count
                showFullscreenMedia = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TBTheme.skyLight.opacity(0.32))
                            .frame(width: 48, height: 48)

                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TBTheme.icyBlue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(featuredVideoLabel == "Creator clip" ? "Watch Creator Clip" : "Watch Maker Video")
                            .font(.tbHeadline)
                            .foregroundStyle(TBTheme.deepSky)

                        Text("Open the product \(featuredVideoLabel.lowercased()) in full screen.")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(featuredVideoLabel == "Creator clip" ? "Watch creator clip" : "Watch maker video")
            .accessibilityHint("Opens the product video in full screen.")
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
        // Keep add-to-cart affordance consistent with list rows: a single long capsule button,
        // rather than a floating card that can feel like a modal the first time.
        buyButton
            .frame(maxWidth: .infinity)
    }

    private var buyButton: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isAdded ? "checkmark" : "cart.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(buttonTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("• \(priceText)")
                    .font(.body.weight(.semibold))
                    .opacity(0.92)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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

    private var buttonTitle: String {
        isAdded ? "Added" : "Add to Cart"
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

private struct ProductRatingStars: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: starName(for: index))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(index <= Int(rating.rounded()) ? TBTheme.accent : Color.secondary.opacity(0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(format: "%.1f", rating)) out of 5 stars")
    }

    private func starName(for index: Int) -> String {
        index <= Int(rating.rounded()) ? "star.fill" : "star"
    }
}

private struct ProductRatingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let productName: String
    @Binding var selectedRating: Int
    @Binding var reviewText: String
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Rate \(productName)")
                    .font(.tbSectionTitle)
                    .foregroundStyle(TBTheme.deepSky)

                Text("Your rating helps future buyers understand product quality and experience.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            selectedRating = value
                        } label: {
                            Image(systemName: value <= selectedRating ? "star.fill" : "star")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(value <= selectedRating ? TBTheme.accent : Color.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Write a review (optional)")
                        .font(.tbCaption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Share a quick note about the product", text: $reviewText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.tbBody)
                        .lineLimit(4, reservesSpace: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(TBTheme.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                Button {
                    onSubmit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Submit Rating")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                .disabled(isSubmitting || selectedRating == 0)
                .opacity((isSubmitting || selectedRating == 0) ? 0.6 : 1.0)

                Spacer()
            }
            .padding(20)
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationTitle("Product Rating")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProductReviewCard: View {
    let review: ProductReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProductRatingStars(rating: Double(review.rating))
                Text(relativeDate)
                    .font(.tbCaption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            if let reviewText = review.reviewText, !reviewText.isEmpty {
                Text(reviewText)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Rated \(review.rating) out of 5")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: review.updatedAt, relativeTo: .now)
    }
}

private struct SellerAttributionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let seller: SellerProfile

    var body: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 0.8)
                )

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

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = seller.avatarURL {
            StorefrontImageView(reference: avatarURL.absoluteString, contentMode: .fill) {
                avatarPlaceholder
            }
            .clipShape(Circle())
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.96), TBTheme.skyLight.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(TBTheme.deepSky.opacity(0.7))
        }
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

