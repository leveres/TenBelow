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
    @State private var passwordInput = ""
    @State private var verificationCode = ""
    @State private var verificationChallengeId = ""
    @State private var verificationDeliveryTarget = ""
    @State private var errorMessage: String?
    @State private var isCreatingAccount = false
    @State private var isVerifyingEmail = false
    @FocusState private var focusedField: BuyerSetupFieldFocus?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Create your buyer account")
                            .font(.tbSectionTitle)
                            .foregroundStyle(TBTheme.deepSky)

                        Text("Save your name and email so checkout and orders stay with you.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        setupField(title: "Full name", id: .name) {
                            TextField("Your name", text: $nameInput)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled(false)
                        }

                        setupField(title: "Email", id: .email) {
                            TextField("you@example.com", text: $emailInput)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        setupField(title: "Password", id: .password) {
                            SecureField("At least 8 characters", text: $passwordInput)
                                .textContentType(.newPassword)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.tbBody)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if verificationChallengeId.isEmpty {
                            Button {
                                Task { await saveAccount() }
                            } label: {
                                if isCreatingAccount {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Create buyer account", systemImage: "person.crop.circle.badge.checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                            .disabled(isCreatingAccount)
                        } else {
                            setupField(title: "Verification code", id: .verificationCode) {
                                TextField("123456", text: $verificationCode)
                                    .keyboardType(.numberPad)
                            }

                            Button {
                                Task { await verifyEmail() }
                            } label: {
                                if isVerifyingEmail {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Verify email", systemImage: "checkmark.shield")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                            .disabled(isVerifyingEmail || verificationCode.count < 6)

                            Button("Send a new code") {
                                Task { await resendCode() }
                            }
                            .font(.tbBodyStrong)
                            .foregroundStyle(TBTheme.deepSky)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(focusedField == nil)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(field, anchor: setupFieldScrollAnchor(for: field))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
            #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
        .background(TBFrostBackground())
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

    private func setupField<Content: View>(
        title: String,
        id: BuyerSetupFieldFocus,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
            content()
                .focused($focusedField, equals: id)
                .padding(12)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .id(id)
    }

    private func setupFieldScrollAnchor(for field: BuyerSetupFieldFocus) -> UnitPoint {
        switch field {
        case .verificationCode, .password:
            return UnitPoint(x: 0.5, y: 0.82)
        case .email:
            return UnitPoint(x: 0.5, y: 0.62)
        case .name:
            return UnitPoint(x: 0.5, y: 0.48)
        }
    }

    private func saveAccount() async {
        let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPassword = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter your name."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        guard trimmedPassword.count >= 8 else {
            errorMessage = "Use at least 8 characters for your password."
            return
        }

        guard AppConstants.isBackendConfigured else {
            errorMessage = "TenBelow could not reach the server. Check your connection and try again."
            return
        }

        errorMessage = nil
        isCreatingAccount = true

        do {
            let response = try await BuyerAccountAPI.createAccount(
                fullName: trimmedName,
                email: trimmedEmail,
                password: trimmedPassword
            )

            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif

            buyerFullName = trimmedName
            buyerEmail = trimmedEmail
            buyerCheckoutPreference = "account"
            isCreatingAccount = false

            if response.emailVerified == true {
                buyerAccountCreated = true
                await MarketplaceAuthSession.syncAfterIdentityChange()
                await PushDeviceRegistration.syncAfterIdentityChange()
                dismiss()
            } else if let verification = response.verification {
                verificationChallengeId = verification.challengeId
                verificationDeliveryTarget = verification.deliveryTarget
                errorMessage = "Enter the code sent to \(verification.deliveryTarget)."
            }
        } catch {
            isCreatingAccount = false
            errorMessage = error.localizedDescription
        }
    }

    private func resendCode() async {
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let response = try await BuyerAccountAPI.requestEmailVerification(email: trimmedEmail)
            verificationChallengeId = response.challengeId ?? ""
            verificationDeliveryTarget = response.deliveryTarget ?? verificationDeliveryTarget
            verificationCode = ""
            errorMessage = "New code sent to \(verificationDeliveryTarget)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyEmail() async {
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isVerifyingEmail = true
        defer { isVerifyingEmail = false }

        do {
            let response = try await BuyerAccountAPI.verifyEmail(
                email: trimmedEmail,
                challengeId: verificationChallengeId,
                code: verificationCode
            )
            if let token = response.token, !token.isEmpty {
                MarketplaceAuthSession.storeBuyerSessionToken(token)
            }
            buyerFullName = response.fullName ?? nameInput
            buyerEmail = response.buyerEmail ?? trimmedEmail
            buyerAccountCreated = true
            buyerCheckoutPreference = "account"
            await PushDeviceRegistration.syncAfterIdentityChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private enum BuyerSetupFieldFocus: Hashable {
    case name
    case email
    case password
    case verificationCode
}
