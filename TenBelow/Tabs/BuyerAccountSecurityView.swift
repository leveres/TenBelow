import SwiftUI

struct BuyerAccountSecurityView: View {
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @State private var emailInput = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var statusMessage = ""
    @State private var errorMessage = ""

    private var trimmedEmailInput: String {
        emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSubmit: Bool {
        !isSaving && (hasEmailChange || hasPasswordChange)
    }

    private var hasEmailChange: Bool {
        !trimmedEmailInput.isEmpty && trimmedEmailInput != buyerEmail
    }

    private var hasPasswordChange: Bool {
        !newPassword.isEmpty || !confirmPassword.isEmpty
    }

    var body: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Account security")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Update your saved email and password. We will send a confirmation email when changes are made.")
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Email", text: $emailInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .padding(12)
                        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .padding(12)
                        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .padding(12)
                        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.tbBody)
                            .foregroundStyle(.red)
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.tbBody)
                            .foregroundStyle(.green)
                    }

                    Button {
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save changes", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                    .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(TBFrostBackground())
        .navigationTitle("Email & Password")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if emailInput.isEmpty {
                emailInput = buyerEmail
            }
        }
    }

    private func saveChanges() async {
        errorMessage = ""
        statusMessage = ""

        let nextEmail = hasEmailChange ? trimmedEmailInput : nil
        let nextPassword = hasPasswordChange ? newPassword : nil

        guard nextEmail != nil || nextPassword != nil else {
            errorMessage = "Change your email or password first."
            return
        }

        if let nextEmail, !isValidEmail(nextEmail) {
            errorMessage = "Enter a valid email address."
            return
        }

        if hasPasswordChange {
            if newPassword.count < 8 {
                errorMessage = "Use at least 8 characters for your password."
                return
            }
            if newPassword != confirmPassword {
                errorMessage = "Password confirmation does not match."
                return
            }
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let response = try await BuyerAccountAPI.updateAccount(
                newEmail: nextEmail,
                newPassword: nextPassword
            )
            buyerEmail = response.email
            if let token = response.token, !token.isEmpty {
                MarketplaceAuthSession.storeBuyerSessionToken(token)
            } else if response.verification != nil {
                MarketplaceAuthSession.clearBuyerSession()
            }
            await PushDeviceRegistration.syncAfterIdentityChange()

            let destinations = response.confirmationTargets.joined(separator: ", ")
            if let verification = response.verification {
                statusMessage = "Email changed. Enter the verification code sent to \(verification.deliveryTarget) the next time you sign in."
            } else {
                statusMessage = destinations.isEmpty
                    ? "Changes saved."
                    : "Changes saved. Confirmation sent to \(destinations)."
            }
            newPassword = ""
            confirmPassword = ""
            emailInput = response.email
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^\S+@\S+\.\S+$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

