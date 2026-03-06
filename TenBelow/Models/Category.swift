//
//  Category.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/10/26.
//

import Foundation

struct TBCategory: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
}

let tbCategories: [TBCategory] = [
    .init(title: "All", icon: "sparkles"),
    .init(title: "Home", icon: "house"),
    .init(title: "Desk", icon: "desktopcomputer"),
    .init(title: "Car", icon: "car"),
    .init(title: "Tech", icon: "cpu"),
    .init(title: "Gifts", icon: "gift"),
    .init(title: "Didn't Know I Needed This", icon: "wand.and.stars")
]

extension TBCategory {
    /// Maps to Category enum for filtering; nil when "All".
    var filterCategory: Category? {
        Category(rawValue: title)
    }
}

enum Category: String, CaseIterable, Identifiable {
    case home = "Home"
    case desk = "Desk"
    case car = "Car"
    case tech = "Tech"
    case gifts = "Gifts"
    case didntKnow = "Didn't Know I Needed This"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .desk:      return "desktopcomputer"
        case .car:       return "car.fill"
        case .tech:      return "cpu"
        case .gifts:     return "gift.fill"
        case .didntKnow: return "sparkles"
        }
    }
}
