import SwiftUI

/// Shown when a buyer must sign in before server-backed shop or order messaging.
struct OrderMessagingGateSheet: View {
    let sellerName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(TBTheme.icyBlue)

                    Text("Sign in to message")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Create or sign in to your buyer account to message \(sellerName). Shop questions and order updates use the same secure inbox.")
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(TBTheme.cloudWhite.ignoresSafeArea())
            .navigationTitle("Message seller")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
