//
//  CategoryView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct CategoryView: View {
    let category: Category?
    let displayTitle: String
    let displayIcon: String

    init(category: Category) {
        self.category = category
        self.displayTitle = category.rawValue
        self.displayIcon = category.icon
    }

    init(allProducts tbCategory: TBCategory) {
        self.category = nil
        self.displayTitle = tbCategory.title
        self.displayIcon = tbCategory.icon
    }

    private var products: [Product] {
        guard let category else { return MockData.products }
        return MockData.products(for: category)
    }

    var body: some View {
        ScrollView {
            if products.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: displayIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(TBTheme.skyBlue)

                    Text("Coming soon")
                        .font(.headline)

                    Text("We're printing up new \(displayTitle) items. Check back soon!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TBTheme.spacingMD) {
                    ForEach(products) { product in
                        ProductCard(
                            product: product,
                            seller: .mockLookup(id: product.sellerId),
                            allProducts: MockData.products
                        )
                    }
                }
                .padding()
            }
        }
        .background(TBTheme.cloudWhite)
        .navigationTitle(displayTitle)
    }
}

#Preview {
    NavigationStack {
        CategoryView(category: .desk)
    }
    .environmentObject(CartStore())
}
