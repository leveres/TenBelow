#if os(iOS)
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// PHPicker-based video selection that copies the temp file synchronously before upload.
struct SystemVideoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .videos
        configuration.preferredAssetRepresentationMode = .compatible

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: SystemVideoLibraryPicker

        init(_ parent: SystemVideoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.isPresented = false
                return
            }

            let provider = result.itemProvider
            let movieTypeIdentifiers = [
                UTType.movie.identifier,
                UTType.video.identifier,
                "public.mpeg-4",
                "com.apple.quicktime-movie",
            ]
            guard let movieTypeIdentifier = movieTypeIdentifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
                parent.onError("Please choose a video from your library.")
                parent.isPresented = false
                return
            }

            // PHPicker deletes the temporary file as soon as this completion returns.
            provider.loadFileRepresentation(forTypeIdentifier: movieTypeIdentifier) { url, error in
                if let error {
                    Task { @MainActor in
                        self.parent.onError(error.localizedDescription)
                        self.parent.isPresented = false
                    }
                    return
                }

                guard let url else {
                    Task { @MainActor in
                        self.parent.onError("We couldn't load that video.")
                        self.parent.isPresented = false
                    }
                    return
                }

                let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let destinationURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    Task { @MainActor in
                        self.parent.onPick(destinationURL)
                        self.parent.isPresented = false
                    }
                } catch {
                    Task { @MainActor in
                        self.parent.onError("We couldn't prepare that video. \(error.localizedDescription)")
                        self.parent.isPresented = false
                    }
                }
            }
        }
    }
}
#endif
