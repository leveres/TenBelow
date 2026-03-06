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
    var quantity: Int
}
