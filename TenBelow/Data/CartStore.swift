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

    func add(_ product: Product, selectedColor: ProductColorOption? = nil, qty: Int = 1) {
        guard qty > 0 else { return }
        let lineID = CartItem.lineID(productId: product.id, selectedColorId: selectedColor?.id)
        if let idx = items.firstIndex(where: { $0.id == lineID }) {
            items[idx].quantity += qty
        } else {
            items.append(CartItem(id: lineID, product: product, selectedColor: selectedColor, quantity: qty))
        }

        if let storedIndex = storedItems.firstIndex(where: { $0.lineID == lineID }) {
            storedItems[storedIndex].quantity += qty
        } else {
            storedItems.append(
                PersistedCartItem(
                    productId: product.id,
                    selectedColor: selectedColor,
                    quantity: qty
                )
            )
        }
        persist()
    }

    func remove(_ product: Product) {
        items.removeAll { $0.product.id == product.id }
        storedItems.removeAll { $0.productId == product.id }
        persist()
    }

    func remove(_ item: CartItem) {
        items.removeAll { $0.id == item.id }
        storedItems.removeAll { $0.lineID == item.id }
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

    func setQuantity(_ item: CartItem, qty: Int) {
        guard qty > 0 else {
            remove(item)
            return
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].quantity = qty
        }
        if let storedIndex = storedItems.firstIndex(where: { $0.lineID == item.id }) {
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
            let selectedColor: ProductColorOption?
            if let snapshot = storedItem.selectedColor {
                guard let currentColor = product.availableColors.first(where: { $0.id == snapshot.id }) else {
                    return nil
                }
                selectedColor = currentColor
            } else {
                guard product.availableColors.isEmpty else {
                    // A seller added color choices after this legacy cart row was saved.
                    // Remove it so the buyer must make an explicit selection on the product page.
                    return nil
                }
                selectedColor = nil
            }
            let lineID = CartItem.lineID(productId: product.id, selectedColorId: selectedColor?.id)
            return CartItem(
                id: lineID,
                product: product,
                selectedColor: selectedColor,
                quantity: storedItem.quantity
            )
        }

        let removedCount = max(0, storedItems.count - syncedItems.count)
        items = syncedItems
        storedItems = syncedItems.map {
            PersistedCartItem(
                productId: $0.product.id,
                selectedColor: $0.selectedColor,
                quantity: $0.quantity
            )
        }
        persist()
        return removedCount
    }

    private func persist() {
        LocalCodableStore.save(storedItems, key: storageKey)
    }
}

private struct PersistedCartItem: Codable, Hashable {
    let productId: String
    let selectedColor: ProductColorOption?
    var quantity: Int

    var lineID: String {
        CartItem.lineID(productId: productId, selectedColorId: selectedColor?.id)
    }

    private enum CodingKeys: String, CodingKey {
        case productId, selectedColor, quantity
    }

    init(productId: String, selectedColor: ProductColorOption?, quantity: Int) {
        self.productId = productId
        self.selectedColor = selectedColor
        self.quantity = quantity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productId = try container.decode(String.self, forKey: .productId)
        selectedColor = try container.decodeIfPresent(ProductColorOption.self, forKey: .selectedColor)
        quantity = try container.decode(Int.self, forKey: .quantity)
    }
}
