//
//  InAppPolicyBrowser.swift
//  TenBelow
//

import SwiftUI

#if os(iOS) || os(visionOS)
import SafariServices

struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

#if os(macOS)
import WebKit

struct InAppSafariView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

/// Presents policy pages inside the app (in-app browser on iOS; embedded web view on macOS).
struct InAppPolicyBrowser: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS) || os(visionOS)
        InAppSafariView(url: url)
            .ignoresSafeArea()
        #elseif os(macOS)
        NavigationStack {
            InAppSafariView(url: url)
                .navigationTitle("Policy")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }
}
