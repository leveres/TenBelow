//
//  Money.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import Foundation

enum Money {
    static func dollars(fromCents cents: Int) -> Double {
        Double(cents) / 100.0
    }

    static func format(cents: Int) -> String {
        let value = dollars(fromCents: cents)
        return value.formatted(.currency(code: "USD"))
    }
}
