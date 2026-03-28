import SwiftUI
#if canImport(UIKit)
import Combine
import UIKit

@MainActor
private final class RemoteImageLoader: ObservableObject {
    static let cache = NSCache<NSURL, UIImage>()

    @Published private(set) var image: UIImage?

    func load(from url: URL) async {
        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            image = cachedImage
            return
        }

        do {
            let (data, _) = try await URLSession.tenBelow.data(from: url)
            guard !Task.isCancelled, let uiImage = UIImage(data: data) else { return }
            Self.cache.setObject(uiImage, forKey: url as NSURL)
            image = uiImage
        } catch {
            image = nil
        }
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
        if let url = Product.mediaURL(for: reference) {
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
