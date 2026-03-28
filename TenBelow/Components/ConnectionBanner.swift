import SwiftUI

struct ConnectionBanner: View {
    @ObservedObject private var network = NetworkMonitor.shared
    var staleDataMessage: String?
    var onRetry: (() async -> Void)?

    @State private var isRetrying = false

    private var shouldShow: Bool {
        !network.isConnected || staleDataMessage != nil
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if let onRetry, network.isConnected {
                    Button {
                        guard !isRetrying else { return }
                        isRetrying = true
                        Task {
                            await onRetry()
                            isRetrying = false
                        }
                    } label: {
                        Group {
                            if isRetrying {
                                ProgressView()
                                    .tint(TBTheme.deepSky)
                                    .scaleEffect(0.72)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(TBTheme.deepSky)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetrying)
                    .accessibilityLabel(isRetrying ? "Retrying connection" : "Retry")
                    .accessibilityHint("Refresh with the latest data.")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.28), value: shouldShow)
        }
    }

    private var icon: String {
        network.isConnected ? "exclamationmark.icloud" : "wifi.slash"
    }

    private var iconColor: Color {
        network.isConnected ? .orange : .red.opacity(0.8)
    }

    private var title: String {
        if !network.isConnected {
            return "You're offline"
        }
        return "Couldn't refresh"
    }

    private var subtitle: String {
        if !network.isConnected {
            return "Showing saved data. Connect to get the latest."
        }
        return staleDataMessage ?? "Tap retry or check back soon."
    }

    private var backgroundColor: Color {
        network.isConnected
            ? Color.orange.opacity(0.06)
            : Color.red.opacity(0.05)
    }

    private var borderColor: Color {
        network.isConnected
            ? Color.orange.opacity(0.14)
            : Color.red.opacity(0.12)
    }
}
