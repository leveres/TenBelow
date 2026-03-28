//
//  ReportListingFallbackSheet.swift
//  TenBelow
//
//  Shown when Mail can’t handle a listing report (Simulator, no mail account, etc.).
//

import SwiftUI
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReportListingFallbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    let product: Product

    @State private var didCopy = false

    private var reportBody: String { ReportListingMail.body(for: product) }
    private var mailURL: URL? { ReportListingMail.mailtoURL(for: product) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mail is unavailable. You can still report this listing by copying the details below and emailing \(AppConstants.reportListingEmail), or sharing them in another app.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Report details")
                        .font(.tbHeadline)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.92))

                    ScrollView {
                        Text(reportBody)
                            .font(.body)
                            .monospaced()
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(spacing: 12) {
                    if let mailURL {
                        Button {
                            PlatformURLOpener.open(mailURL, onSuccess: { dismiss() }, onFailure: { })
                        } label: {
                            Label("Open Mail", systemImage: "envelope.open.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TBTheme.deepSky)
                    }

                    Button {
                        copyToPasteboard(reportBody)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy report details", systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: reportBody) {
                        Label("Share details", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Report listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
