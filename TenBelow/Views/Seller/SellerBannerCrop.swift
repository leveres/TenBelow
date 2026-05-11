//
//  SellerBannerCrop.swift
//  TenBelow
//

import SwiftUI
import UIKit

// MARK: - Edit preview (pinch + pan)

struct SellerBannerEditSlot: View {
    let image: UIImage
    let slotHeight: CGFloat
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize
    @Binding var reportedPreviewWidth: CGFloat

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var pinchAnchorZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let livePan = CGSize(
                width: pan.width + dragTranslation.width,
                height: pan.height + dragTranslation.height
            )
            let clampedLive = Self.clampPan(livePan, zoom: zoom, container: container, image: image)

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(zoom)
                .offset(x: clampedLive.width, y: clampedLive.height)
                .frame(width: container.width, height: container.height)
                .clipped()
                .contentShape(Rectangle())
                .accessibilityLabel("Banner preview")
                .accessibilityHint("Pinch to zoom and drag to choose which part of the photo is visible.")
                .gesture(magnificationGesture(container: container))
                .simultaneousGesture(dragGesture(container: container))
                .onAppear {
                    reportedPreviewWidth = container.width
                }
                .onChange(of: container.width) { _, w in
                    reportedPreviewWidth = w
                }
        }
        .frame(height: slotHeight)
    }

    private func magnificationGesture(container: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newZoom = min(max(pinchAnchorZoom * value, 1), 4)
                zoom = newZoom
                pan = Self.clampPan(pan, zoom: newZoom, container: container, image: image)
            }
            .onEnded { _ in
                pinchAnchorZoom = zoom
            }
    }

    private func dragGesture(container: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let proposed = CGSize(
                    width: pan.width + value.translation.width,
                    height: pan.height + value.translation.height
                )
                pan = Self.clampPan(proposed, zoom: zoom, container: container, image: image)
            }
    }

    static func clampPan(_ proposed: CGSize, zoom: CGFloat, container: CGSize, image: UIImage) -> CGSize {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0, container.width > 0, container.height > 0 else { return .zero }

        let fill = max(container.width / iw, container.height / ih)
        let scaledW = iw * fill * zoom
        let scaledH = ih * fill * zoom
        let maxX = max(0, (scaledW - container.width) / 2)
        let maxY = max(0, (scaledH - container.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

// MARK: - Export for upload (matches on-screen framing)

enum SellerBannerCropExporter {
    /// Renders the same aspect-fill + zoom + pan framing as `SellerBannerEditSlot`, at a fixed pixel width for uploads.
    static func renderForUpload(
        image: UIImage,
        previewContainerPoints: CGSize,
        zoom: CGFloat,
        panPoints: CGSize,
        outputPixelWidth: CGFloat = 1600
    ) -> UIImage {
        guard previewContainerPoints.width > 1, previewContainerPoints.height > 1 else {
            return image
        }

        let aspect = previewContainerPoints.height / previewContainerPoints.width
        let ow = outputPixelWidth
        let oh = max(1, (ow * aspect).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let outSize = CGSize(width: ow, height: oh)
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)

        return renderer.image { _ in
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else {
                image.draw(in: CGRect(origin: .zero, size: outSize))
                return
            }

            let baseFill = max(outSize.width / imageSize.width, outSize.height / imageSize.height)
            let scale = baseFill * zoom
            let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

            let panScaleX = outSize.width / previewContainerPoints.width
            let panScaleY = outSize.height / previewContainerPoints.height
            let panX = panPoints.width * panScaleX
            let panY = panPoints.height * panScaleY

            let origin = CGPoint(
                x: (outSize.width - scaledSize.width) / 2 + panX,
                y: (outSize.height - scaledSize.height) / 2 + panY
            )

            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}
