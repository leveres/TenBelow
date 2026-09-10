import SwiftUI

enum AccountDeletionKind {
    case buyer
    case seller

    var title: String {
        switch self {
        case .buyer: return "Delete buyer account"
        case .seller: return "Delete seller account"
        }
    }

    var explanation: String {
        switch self {
        case .buyer:
            return """
            This permanently removes your buyer sign-in, favorites, and saved profile from TenBelow on our servers. \
            Order and payment records may be kept for legal, tax, and support purposes.
            """
        case .seller:
            return """
            This permanently removes your seller account and unpublishes your storefront listings. \
            Order, payout, and tax records may be kept as required by law.
            """
        }
    }

    var passwordPrompt: String {
        "Enter your account password to confirm."
    }
}

struct AccountDeletionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: AccountDeletionKind
    let onDeleted: () -> Void

    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(kind.explanation)
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(12)
                            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text("If your account has no password yet, leave this blank.")
                            .font(.tbMicro)
                            .foregroundStyle(.secondary)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.tbBody)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button(role: .destructive) {
                            Task { await deleteAccount() }
                        } label: {
                            if isDeleting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Delete my account", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isDeleting)
                    }
                }
                .padding(16)
            }
            .background(TBFrostBackground())
            .navigationTitle(kind.title)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = ""
        defer { isDeleting = false }

        do {
            switch kind {
            case .buyer:
                _ = try await BuyerAccountAPI.deleteAccount(password: password)
            case .seller:
                _ = try await SellerAPI.deleteAccount(password: password)
            }
            dismiss()
            onDeleted()
        } catch let apiError as BuyerAccountAPIError {
            errorMessage = apiError.message
        } catch let apiError as SellerAPIError {
            errorMessage = apiError.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
