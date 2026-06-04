import SwiftUI

#if DEBUG
/// DEBUG-only tools for backend overrides and pre-Stripe checkout testing.
struct DeveloperSettingsView: View {
    @AppStorage(AppConstants.testingModeUserDefaultsKey) private var testingModeEnabled = false
    @AppStorage(AppConstants.debugBackendBaseURLOverrideKey) private var backendURLOverride = ""
    @State private var overrideDraft = ""

    var body: some View {
        List {
            Section {
                Text(StripeSetupStatus.summaryLine)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Checkout status")
            }

            Section("Stripe readiness") {
                ForEach(StripeSetupStatus.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isComplete ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.tbBodyStrong)
                            Text(item.detail)
                                .font(.tbCaption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Section {
                Toggle("Testing mode", isOn: $testingModeEnabled)
                Text("Simulates a successful order when Stripe or the backend is not configured. Use for UI and flow testing before Stripe keys are ready.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Without Stripe (this week)")
            }

            Section {
                TextField("https://192.168.x.x:3000", text: $overrideDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Apply backend override") {
                    backendURLOverride = overrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !backendURLOverride.isEmpty {
                    Button("Clear override", role: .destructive) {
                        backendURLOverride = ""
                        overrideDraft = ""
                    }
                }
                Text("Overrides TENBELOW_BACKEND_BASE_URL on device. Use your Mac’s LAN IP when running tenbelow-backend locally.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Backend URL override")
            } footer: {
                Text("Full Stripe setup steps: docs/stripe-setup.md in the repo.")
            }
        }
        .navigationTitle("Developer")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            overrideDraft = backendURLOverride
        }
    }
}
#endif
