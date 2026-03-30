//
//  NotificationsHubView.swift
//

import SwiftUI

/// In-app activity hub for favorites and notifications. Manage notification preferences in Settings.
struct NotificationsHubView: View {
    var body: some View {
        NotificationActivityView()
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationTitle("Activity")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        NotificationsHubView()
            .environmentObject(
                NotificationStore(
                    eventStore: CommerceEventStore(),
                    buyerEngagement: BuyerEngagementStore(eventStore: CommerceEventStore()),
                    localProducts: LocalProductStore(eventStore: CommerceEventStore()),
                    orderStore: OrderStore(eventStore: CommerceEventStore())
                )
            )
            .environmentObject(LocalProductStore(eventStore: CommerceEventStore()))
            .environmentObject(OrderStore(eventStore: CommerceEventStore()))
    }
}
