import SwiftUI
#if os(iOS)
import UIKit
#endif

struct BuyerSignInView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = "guest"

    @State private var emailInput = ""
    @State private var passwordInput = ""
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sign in to your buyer account")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Use the email and password from when you created your TenBelow buyer account.")
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    labeledField(title: "Email") {
                        TextField("you@example.com", text: $emailInput)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    labeledField(title: "Password") {
                        SecureField("Your password", text: $passwordInput)
                            .textContentType(.password)
                            .padding(12)
                            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.tbBody)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        if isSigningIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Sign in", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                    .disabled(isSigningIn)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(TBFrostBackground())
        .navigationTitle("Sign in")
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

    private func signIn() async {
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPassword = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        guard !trimmedPassword.isEmpty else {
            errorMessage = "Please enter your password."
            return
        }

        guard AppConstants.isBackendConfigured else {
            errorMessage = "TenBelow could not reach the server. Check your connection and try again."
            return
        }

        errorMessage = nil
        isSigningIn = true

        do {
            let response = try await BuyerAccountAPI.login(email: trimmedEmail, password: trimmedPassword)

            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif

            buyerEmail = response.buyerEmail
            buyerFullName = response.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (response.fullName ?? "")
                : buyerFullName
            buyerAccountCreated = true
            buyerCheckoutPreference = "account"
            MarketplaceAuthSession.storeBuyerSessionToken(response.token)

            await PushDeviceRegistration.syncAfterIdentityChange()

            isSigningIn = false
            dismiss()
        } catch {
            isSigningIn = false
            errorMessage = error.localizedDescription
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
