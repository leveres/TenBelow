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

    func add(_ product: Product, qty: Int = 1) {
        if let idx = items.firstIndex(where: { $0.product.id == product.id }) {
            items[idx].quantity += qty
        } else {
            items.append(CartItem(id: product.id, product: product, quantity: qty))
        }
    }

    func remove(_ product: Product) {
        items.removeAll { $0.product.id == product.id }
    }

    func setQuantity(_ product: Product, qty: Int) {
        guard qty > 0 else { remove(product); return }
        if let idx = items.firstIndex(where: { $0.product.id == product.id }) {
            items[idx].quantity = qty
        }
    }

    var subtotalCents: Int {
        items.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) }
    }

    func clear() {
        items.removeAll()
    }
}
