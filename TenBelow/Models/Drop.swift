//
//  Drop.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/10/26.
//

import Foundation

struct Drop: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let tagline: String
    let daysRemaining: Int
    let products: [Product]
    let imageName: String
}
