import Foundation

enum ShopSortOption: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case newest = "Newest"
    case priceLow = "Price: Low to High"
    case priceHigh = "Price: High to Low"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .recommended: return "Recommended"
        case .newest: return "Newest"
        case .priceLow: return "Price ↑"
        case .priceHigh: return "Price ↓"
        }
    }
}

enum ShopBrowseHighlight: String, CaseIterable, Identifiable {
    case everything = "All items"
    case latest = "Latest"
    case creatorClips = "Creator Clips"
    case priceDrops = "Price Drops"
    case saved = "Saved"

    var id: String { rawValue }
}

enum ShopBrowseFilters {
    static func filterByCategory(_ products: [Product], category: TBCategory) -> [Product] {
        guard category.title != "All" else { return products }
        return products.filter { $0.category.rawValue == category.title }
    }

    static func filterBySearch(
        _ products: [Product],
        query: String,
        sellerProfilesByID: [String: SellerProfile]
    ) -> [Product] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return products }

        return products.filter { product in
            matchesSearchQuery(product, query: normalized, sellerProfilesByID: sellerProfilesByID)
        }
    }

    static func filterBySeller(_ products: [Product], sellerId: String?) -> [Product] {
        guard let sellerId, !sellerId.isEmpty else { return products }
        return products.filter { $0.sellerId == sellerId }
    }

    static func filterBySaved(_ products: [Product], favoriteProductIDs: Set<String>) -> [Product] {
        products.filter { favoriteProductIDs.contains($0.id) }
    }

    static func applyHighlight(
        _ products: [Product],
        highlight: ShopBrowseHighlight,
        favoriteProductIDs: Set<String>
    ) -> [Product] {
        switch highlight {
        case .everything:
            return products
        case .latest:
            return products.sorted { $0.createdAt > $1.createdAt }
        case .creatorClips:
            let clipped = products.filter(\.hasCreatorClip)
            return clipped.isEmpty ? products : clipped
        case .priceDrops:
            let dropped = products.filter(\.hasPriceDrop)
            if dropped.isEmpty { return products }
            return dropped.sorted {
                ($0.previousPriceCents ?? $0.priceCents) > ($1.previousPriceCents ?? $1.priceCents)
            }
        case .saved:
            let saved = filterBySaved(products, favoriteProductIDs: favoriteProductIDs)
            return saved.sorted { $0.createdAt > $1.createdAt }
        }
    }

    static func applySort(_ products: [Product], sort: ShopSortOption, highlight: ShopBrowseHighlight) -> [Product] {
        switch sort {
        case .recommended:
            if highlight == .latest || highlight == .saved {
                return products
            }
            return products.sorted { lhs, rhs in
                let lhsScore = engagementScore(lhs)
                let rhsScore = engagementScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhsScore > rhsScore
            }
        case .newest:
            return products.sorted { $0.createdAt > $1.createdAt }
        case .priceLow:
            return products.sorted {
                if $0.priceCents == $1.priceCents {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.priceCents < $1.priceCents
            }
        case .priceHigh:
            return products.sorted {
                if $0.priceCents == $1.priceCents {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.priceCents > $1.priceCents
            }
        }
    }

    static func sellerOptions(
        from products: [Product],
        profilesByID: [String: SellerProfile]
    ) -> [(id: String, name: String)] {
        let grouped = Dictionary(grouping: products, by: \.sellerId)
        return grouped.keys
            .sorted()
            .compactMap { sellerId in
                let name = profilesByID[sellerId]?.displayName
                    ?? products.first(where: { $0.sellerId == sellerId })?.sellerId
                    ?? sellerId
                return (id: sellerId, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func engagementScore(_ product: Product) -> Double {
        Double(product.favoriteCount) * 12 + Double(product.pageViewCount) * 0.4 + (product.hasCreatorClip ? 6 : 0)
    }

    private static func matchesSearchQuery(
        _ product: Product,
        query: String,
        sellerProfilesByID: [String: SellerProfile]
    ) -> Bool {
        let seller = sellerProfilesByID[product.sellerId]
        let handle = seller?.handle
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let haystack = [
            product.name,
            product.material,
            product.availableColors.map(\.name).joined(separator: " "),
            product.productionNote,
            product.durabilityNote,
            product.category.rawValue,
            product.careWarnings.joined(separator: " "),
            product.sellerId,
            seller?.displayName ?? "",
            handle,
            seller?.location ?? "",
            seller?.materials.joined(separator: " ") ?? "",
            seller?.bio ?? "",
        ]
        .joined(separator: " ")
        .lowercased()

        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if tokens.isEmpty {
            return haystack.localizedStandardContains(query)
        }

        return tokens.allSatisfy { token in
            haystack.localizedStandardContains(token.lowercased())
        }
    }
}
