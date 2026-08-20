//
//  CartItem.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import Foundation

struct CartItem: Identifiable, Hashable {
    let id: String
    let product: Product
    let selectedColor: ProductColorOption?
    var quantity: Int

    static func lineID(productId: String, selectedColorId: String?) -> String {
        guard let selectedColorId, !selectedColorId.isEmpty else { return productId }
        return "\(productId)::color::\(selectedColorId)"
    }
}
