import Foundation
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

/// Off-main-thread prep for seller product photos and videos before upload.
enum SellerProductMediaUploader {
    nonisolated static func loadFileData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }

    nonisolated static func writeTempFile(data: Data, fileExtension: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    #if canImport(UIKit)
    nonisolated static func compressedPhotoTempURL(from pickerData: Data) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: pickerData) else { return nil }
            let scaled = downscaledImage(image, maxPixelSize: 2048)
            guard let jpgData = scaled.jpegData(compressionQuality: 0.88) else { return nil }
            return writeTempFile(data: jpgData, fileExtension: "jpg")
        }.value
    }

    nonisolated static func videoTempURL(from pickerData: Data, fileExtension: String) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            writeTempFile(data: pickerData, fileExtension: fileExtension)
        }.value
    }

    nonisolated static func decodeImage(data: Data, maxPixelSize: Int = 1024) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func downscaledImage(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let maxDimension = max(image.size.width, image.size.height)
        guard maxDimension > maxPixelSize else { return image }
        let scale = maxPixelSize / maxDimension
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
