import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lets a guest buyer finish account creation without returning to role selection (`RolePickerView`).
struct BuyerAccountSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = "guest"

    @State private var nameInput = ""
    @State private var emailInput = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Create your buyer account")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Save your name and email so checkout and orders stay with you.")
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    labeledField(title: "Full name") {
                        TextField("Your name", text: $nameInput)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(false)
                            .padding(12)
                            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    labeledField(title: "Email") {
                        TextField("you@example.com", text: $emailInput)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.tbBody)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: saveAccount) {
                        Label("Create buyer account", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Buyer account")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if nameInput.isEmpty {
                nameInput = buyerFullName
            }
            if emailInput.isEmpty {
                emailInput = buyerEmail
            }
        }
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func saveAccount() {
        let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter your name."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        errorMessage = nil

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        buyerFullName = trimmedName
        buyerEmail = trimmedEmail
        buyerAccountCreated = true
        buyerCheckoutPreference = "account"

        dismiss()
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
