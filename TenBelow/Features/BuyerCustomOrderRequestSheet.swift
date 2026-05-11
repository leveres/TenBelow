import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Buyer flow: describe a custom project, attach reference photos, submit to the backend (email + JSON log when configured).
struct BuyerCustomOrderRequestSheet: View {
    let seller: SellerProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var buyerName = ""
    @State private var buyerEmail = ""
    @State private var descriptionText = ""
#if canImport(PhotosUI)
    @State private var selectedItems: [PhotosPickerItem] = []
#endif
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private let maxReferenceImages = 5
    private let maxDescriptionLength = 8000

    var body: some View {
        NavigationStack {
            Form {
                if let infoURL = seller.customOrderInfoURL {
                    Section {
                        Button {
                            openURL(infoURL)
                        } label: {
                            Label("Open seller’s custom-order info", systemImage: "link")
                        }
                    }
                }

                Section("Contact") {
                    TextField("Your name (optional)", text: $buyerName)
                        .textContentType(.name)
                    TextField("Email", text: $buyerEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Request") {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 120)
                    Text("\(descriptionText.count) / \(maxDescriptionLength)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

#if canImport(PhotosUI)
                Section("Reference images (optional, up to \(maxReferenceImages))") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: maxReferenceImages,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            selectedItems.isEmpty ? "Add photos" : "\(selectedItems.count) selected — tap to change",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .onChange(of: selectedItems) { _, newItems in
                        if newItems.count > maxReferenceImages {
                            selectedItems = Array(newItems.prefix(maxReferenceImages))
                        }
                    }
                }
#endif

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Custom order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if didSucceed {
                        Button("Done") { dismiss() }
                    } else {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .disabled(isSubmitting || !canSubmit)
                    }
                }
            }
            .disabled(isSubmitting && !didSucceed)
        }
    }

    private var canSubmit: Bool {
        let email = buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.count >= 5 else { return false }
        guard desc.count >= 10, desc.count <= maxDescriptionLength else { return false }
        return true
    }

    private func submit() async {
        errorMessage = nil
        let email = buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = buyerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard email.contains("@"), email.count >= 5 else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard desc.count >= 10 else {
            errorMessage = "Please add a bit more detail about what you’d like (at least 10 characters)."
            return
        }
        guard desc.count <= maxDescriptionLength else {
            errorMessage = "Description is too long."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        var referencePaths: [String] = []
#if canImport(PhotosUI)
        for item in selectedItems.prefix(maxReferenceImages) {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
#if canImport(UIKit)
            guard let image = UIImage(data: raw),
                  let jpeg = image.jpegData(compressionQuality: 0.82) else { continue }
            do {
                let path = try await CustomOrderAPI.uploadReferenceImage(
                    sellerId: seller.id,
                    imageData: jpeg,
                    fileExtension: "jpg",
                    contentType: "image/jpeg"
                )
                referencePaths.append(path)
            } catch {
                errorMessage = "Could not upload a reference image. Check your connection and try again."
                return
            }
#else
            continue
#endif
        }
#endif

        do {
            try await CustomOrderAPI.submitRequest(
                sellerId: seller.id,
                buyerName: name,
                buyerEmail: email,
                description: desc,
                referenceImageURLs: referencePaths
            )
            didSucceed = true
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
}
