//
//  NotificationsHubView.swift
//

import SwiftUI

/// Hub for saved favorites (buyers) and in-app notifications. Preferences live in Settings.
struct NotificationsHubView: View {
    var body: some View {
        NotificationActivityView()
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationTitle("Favorites & notifications")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

