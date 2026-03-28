//
//  PlatformURLOpener.swift
//  TenBelow
//

import Foundation
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Opens external URLs (e.g. `mailto:`) with a reliable success/failure signal.
enum PlatformURLOpener {

    /// If the system cannot hand off the URL, `onFailure` runs on the main actor.
    static func open(_ url: URL, onFailure: @escaping @MainActor () -> Void) {
        #if os(iOS) || os(visionOS)
        UIApplication.shared.open(url, options: [:]) { success in
            Task { @MainActor in
                if !success {
                    onFailure()
                }
            }
        }
        #elseif os(macOS)
        DispatchQueue.main.async {
            if !NSWorkspace.shared.open(url) {
                onFailure()
            }
        }
        #else
        Task { @MainActor in
            onFailure()
        }
        #endif
    }

    /// Variant for UI that should dismiss only when Mail (or another handler) actually opens.
    static func open(_ url: URL, onSuccess: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor () -> Void) {
        #if os(iOS) || os(visionOS)
        UIApplication.shared.open(url, options: [:]) { success in
            Task { @MainActor in
                if success {
                    onSuccess()
                } else {
                    onFailure()
                }
            }
        }
        #elseif os(macOS)
        DispatchQueue.main.async {
            if NSWorkspace.shared.open(url) {
                onSuccess()
            } else {
                onFailure()
            }
        }
        #else
        Task { @MainActor in
            onFailure()
        }
        #endif
    }
}
