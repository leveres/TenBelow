#if os(iOS)
import SwiftUI
import UIKit

/// System share sheet — reliable alternative when `ShareLink` styling or toolbar chrome interferes.
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
