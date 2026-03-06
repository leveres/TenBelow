import SwiftUI

struct AddProductView: View {
    var body: some View { Text("Add Product").navigationTitle("Add Product") }
}

struct SellerProductsView: View {
    var body: some View { Text("My Products").navigationTitle("My Products") }
}

struct SellerStorePreviewView: View {
    var seller: SellerProfile?
    var products: [Product] = []

    var body: some View {
        if let seller, !products.isEmpty {
            PublicSellerProfileView(seller: seller, products: products)
        } else {
            Text("Store Preview").navigationTitle("Store Preview")
        }
    }
}

struct SellerOrdersView: View {
    var body: some View { Text("Manage Orders").navigationTitle("Manage Orders") }
}

struct SellerReviewsView: View {
    var body: some View { Text("Reviews").navigationTitle("Reviews") }
}

struct ShippingSettingsView: View {
    var body: some View { Text("Shipping Settings").navigationTitle("Shipping Settings") }
}

struct SellerPoliciesView: View {
    var body: some View { Text("Policies").navigationTitle("Policies") }
}

struct SupportView: View {
    var body: some View { Text("Support").navigationTitle("Support") }
}

struct PayoutSettingsView: View {
    var body: some View { Text("Payout").navigationTitle("Payout") }
}

struct EditSellerProfileView: View {
    var body: some View { Text("Edit Profile").navigationTitle("Edit Profile") }
}
