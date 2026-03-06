//
//  AppRootView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct AppRootView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    @AppStorage("userRole") var userRole = ""

    var body: some View {
        if !hasSeenOnboarding {
            OnboardingView()
        } else if userRole.isEmpty {
            RolePickerView()
        } else {
            MainTabView()
        }
    }
}

#Preview("Main App") {
    AppRootView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
}

#Preview("Onboarding") {
    OnboardingView()
}
