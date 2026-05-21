import SwiftUI
#if canImport(UIKit)
import Combine
import UIKit

private final class RemoteImageLoader: ObservableObject {
    static let cache = NSCache<NSURL, UIImage>()

    @Published private(set) var image: UIImage?
    private var currentURL: URL?

    func load(from url: URL) async {
        currentURL = url

        #if DEBUG
        let shouldLogProfileMedia = url.absoluteString.contains("/profile/")
        if shouldLogProfileMedia {
            print("[ProfileImage] load start url=\(url.absoluteString)")
        }
        #endif

        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            await MainActor.run {
                guard self.currentURL == url else { return }
                image = cachedImage
            }
            #if DEBUG
            if shouldLogProfileMedia {
                print("[ProfileImage] cache hit url=\(url.absoluteString)")
            }
            #endif
            return
        }

        do {
            let data = try await loadData(from: url)
            let uiImage = try await Task.detached(priority: .userInitiated) {
                guard let decodedImage = UIImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return decodedImage
            }.value
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.currentURL == url else { return }
                Self.cache.setObject(uiImage, forKey: url as NSURL)
                image = uiImage
            }
            #if DEBUG
            if shouldLogProfileMedia {
                print("[ProfileImage] load success url=\(url.absoluteString) bytes=\(data.count)")
            }
            #endif
        } catch {
            #if DEBUG
            if shouldLogProfileMedia {
                print("[ProfileImage] load failed url=\(url.absoluteString) error=\(error.localizedDescription)")
            }
            #endif
        }
    }

    private func loadData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
        }

        var lastError: Error?

        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                AppConstants.applyAppClientAuth(to: &request)
                let (remoteData, response) = try await URLSession.tenBelow.data(for: request)

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }

                return remoteData
            } catch {
                #if DEBUG
                if url.absoluteString.contains("/profile/") {
                    print("[ProfileImage] retry attempt=\(attempt + 1) url=\(url.absoluteString) error=\(error.localizedDescription)")
                }
                #endif
                lastError = error
                guard attempt < 2 else { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
#endif

struct StorefrontImageView<Placeholder: View>: View {
    let reference: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    init(
        reference: String?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.reference = reference
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        if let url = Product.previewMediaURL(for: reference) {
            remoteImage(url)
        } else {
            fallbackAssetOrPlaceholder
        }
    }

    @ViewBuilder
    private var fallbackAssetOrPlaceholder: some View {
#if canImport(UIKit)
        if let trimmedReference = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedReference.isEmpty,
           let uiImage = UIImage(named: trimmedReference),
           uiImage.size != .zero {
            configuredImage(Image(trimmedReference))
        } else {
            placeholder()
        }
#else
        placeholder()
#endif
    }

    @ViewBuilder
    private func remoteImage(_ url: URL) -> some View {
#if canImport(UIKit)
        CachedRemoteImage(url: url, contentMode: contentMode, placeholder: placeholder)
#else
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder()
            case .success(let image):
                configuredImage(image)
            case .failure:
                fallbackAssetOrPlaceholder
            @unknown default:
                placeholder()
            }
        }
#endif
    }

    private func configuredImage(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }
}

#if canImport(UIKit)
private struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loader.load(from: url)
        }
    }
}
#endif
