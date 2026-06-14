//
//  CartStore.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class CartStore: ObservableObject {
    @Published private(set) var items: [CartItem] = []
    private let storageKey = "cartStore.items"
    private var storedItems: [PersistedCartItem]

    init() {
        storedItems = LocalCodableStore.load(
            key: storageKey,
            default: [PersistedCartItem]()
        )
    }

    func add(_ product: Product, qty: Int = 1) {
        guard qty > 0 else { return }
        if let idx = items.firstIndex(where: { $0.product.id == product.id }) {
            items[idx].quantity += qty
        } else {
            items.append(CartItem(id: product.id, product: product, quantity: qty))
        }

        if let storedIndex = storedItems.firstIndex(where: { $0.productId == product.id }) {
            storedItems[storedIndex].quantity += qty
        } else {
            storedItems.append(PersistedCartItem(productId: product.id, quantity: qty))
        }
        persist()
    }

    func remove(_ product: Product) {
        items.removeAll { $0.product.id == product.id }
        storedItems.removeAll { $0.productId == product.id }
        persist()
    }

    func setQuantity(_ product: Product, qty: Int) {
        guard qty > 0 else { remove(product); return }
        if let idx = items.firstIndex(where: { $0.product.id == product.id }) {
            items[idx].quantity = qty
        }
        if let storedIndex = storedItems.firstIndex(where: { $0.productId == product.id }) {
            storedItems[storedIndex].quantity = qty
            persist()
        }
    }

    var subtotalCents: Int {
        items.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) }
    }

    var shippingCents: Int {
        MarketplaceShippingCalculator.totalShippingCents(for: items)
    }

    var totalCents: Int {
        subtotalCents + shippingCents
    }

    var sellerShippingQuotes: [SellerShippingQuote] {
        MarketplaceShippingCalculator.quotes(for: items)
    }

    func clear() {
        items.removeAll()
        storedItems.removeAll()
        persist()
    }

    @discardableResult
    func syncAvailableProducts(_ availableProducts: [Product]) -> Int {
        let productsById = Dictionary(uniqueKeysWithValues: availableProducts.map { ($0.id, $0) })
        let syncedItems = storedItems.compactMap { storedItem -> CartItem? in
            guard let product = productsById[storedItem.productId], storedItem.quantity > 0 else {
                return nil
            }
            return CartItem(id: storedItem.productId, product: product, quantity: storedItem.quantity)
        }

        let removedCount = max(0, storedItems.count - syncedItems.count)
        items = syncedItems
        storedItems = syncedItems.map { PersistedCartItem(productId: $0.product.id, quantity: $0.quantity) }
        persist()
        return removedCount
    }

    private func persist() {
        LocalCodableStore.save(storedItems, key: storageKey)
    }
}

private struct PersistedCartItem: Codable, Hashable {
    let productId: String
    var quantity: Int
}
