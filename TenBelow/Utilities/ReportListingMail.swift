//
//  ReportListingMail.swift
//  TenBelow
//

import Foundation

enum ReportListingMail {

    static func subject(for product: Product) -> String {
        "TenBelow listing report: \(product.name) (\(product.id))"
    }

    static func body(for product: Product) -> String {
        """
        I'm reporting this listing on TenBelow.

        Product name: \(product.name)
        Product ID: \(product.id)
        Seller ID: \(product.sellerId)
        Category: \(product.category.rawValue)

        Reason (please describe what’s wrong):

        """
    }

    /// Pre-filled `mailto:` for the trust & safety inbox.
    static func mailtoURL(for product: Product) -> URL? {
        guard var components = URLComponents(string: "mailto:\(AppConstants.reportListingEmail)") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject(for: product)),
            URLQueryItem(name: "body", value: body(for: product))
        ]
        return components.url
    }
}
