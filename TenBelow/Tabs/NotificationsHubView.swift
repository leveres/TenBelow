//
//  NotificationsHubView.swift
//

import SwiftUI

/// In-app notification inbox (activity only). Manage preferences in Settings → Notification settings.
struct NotificationsHubView: View {
    var body: some View {
        NotificationActivityView()
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationTitle("Notifications")
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
