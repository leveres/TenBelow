//
//  Product.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/10/26.
//

import Foundation

struct Product: Identifiable, Hashable {
    let id: String
    let sellerId: String
    let name: String
    let priceCents: Int
    let category: Category

    let imageNames: [String]
    let demoVideoURL: URL?

    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInDays: ClosedRange<Int>
}
