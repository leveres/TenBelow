import SwiftUI

/// Seller dashboard: list and manage buyer-submitted custom order requests.
struct SellerCustomRequestsView: View {
    let seller: SellerProfile

    @State private var requests: [SellerCustomOrderRequest] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedRequest: SellerCustomOrderRequest?

    var body: some View {
        Group {
            if isLoading && requests.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if requests.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(requests) { req in
                            Button {
                                selectedRequest = req
                            } label: {
                                SellerCustomRequestRow(request: req)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBFrostBackground())
        .navigationTitle("Custom requests")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedRequest) { req in
            SellerCustomRequestDetailView(
                seller: seller,
                request: req,
                onUpdated: { updated in
                    replaceRequest(updated)
                    selectedRequest = updated
                }
            )
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 36))
                .foregroundStyle(TBTheme.skyBlue.opacity(0.55))
            Text("No custom requests yet")
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)
            Text("When buyers submit a request from your storefront, it will appear here with their notes and reference photos.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func replaceRequest(_ updated: SellerCustomOrderRequest) {
        if let idx = requests.firstIndex(where: { $0.id == updated.id }) {
            requests[idx] = updated
        }
    }

    private func load() async {
        if requests.isEmpty { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            let next = try await CustomOrderAPI.fetchSellerRequests(sellerId: seller.id)
            await MainActor.run {
                requests = next
            }
        } catch {
            await MainActor.run {
                loadError = (error as NSError).localizedDescription
            }
        }
    }
}

// MARK: - Row

private struct SellerCustomRequestRow: View {
    let request: SellerCustomOrderRequest

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: 28, height: 28)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? request.buyerEmail : request.buyerName)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                    .lineLimit(1)

                Text(request.buyerEmail)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    statusPill
                    if !request.referenceImageURLs.isEmpty {
                        Label("\(request.referenceImageURLs.count)", systemImage: "photo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.035), radius: 8, y: 4)
    }

    private var statusPill: some View {
        Text(request.status.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(request.status.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(request.status.background, in: Capsule())
    }
}

// MARK: - Detail

struct SellerCustomRequestDetailView: View {
    let seller: SellerProfile
    @State private var request: SellerCustomOrderRequest
    let onUpdated: (SellerCustomOrderRequest) -> Void

    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @State private var isUpdating = false
    @State private var actionError: String?
    @State private var confirmDecline = false
    @State private var showBuyerShopChat = false

    init(seller: SellerProfile, request: SellerCustomOrderRequest, onUpdated: @escaping (SellerCustomOrderRequest) -> Void) {
        self.seller = seller
        _request = State(initialValue: request)
        self.onUpdated = onUpdated
    }

    private var buyerDisplayName: String {
        let name = request.buyerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? request.buyerEmail : name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection

                VStack(alignment: .leading, spacing: 8) {
                    Text("Buyer")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                    Text(request.buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : request.buyerName)
                        .font(.tbBodyStrong)
                    Text(request.buyerEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Request")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                    Text(request.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(cardBackground)

                if !request.referenceImageURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reference images")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(request.referenceImageURLs, id: \.self) { ref in
                                    referenceThumb(reference: ref)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(cardBackground)
                }

                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if request.status == .pending {
                    actionButtons
                } else {
                    Text("Status: \(request.status.label). You can still message the buyer below.")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showBuyerShopChat = true
                } label: {
                    Label("Message buyer", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.tbBodyStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [TBTheme.accent, TBTheme.deepSky],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.vertical, 16)
        }
        .background(TBFrostBackground())
        .navigationTitle("Request")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showBuyerShopChat) {
            OrderSupportThreadView(
                sellerId: seller.id,
                sellerName: seller.displayName,
                viewerRole: .seller,
                inquiryBuyerEmail: request.buyerEmail
            )
            .environmentObject(orderStore)
            .environmentObject(inquiryStore)
        }
        .confirmationDialog(
            "Decline this request?",
            isPresented: $confirmDecline,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                Task { await setStatus(.declined) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The buyer won’t be notified automatically. You can still message them to explain.")
        }
    }

    private var statusSection: some View {
        HStack {
            Text(formattedDate(request.createdAt))
                .font(.tbCaption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(request.status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(request.status.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(request.status.background, in: Capsule())
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await setStatus(.accepted) }
            } label: {
                Label("Accept", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.24, green: 0.47, blue: 0.78))
            .disabled(isUpdating)

            Button {
                confirmDecline = true
            } label: {
                Label("Decline", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(isUpdating)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.84))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
            )
    }

    private func referenceThumb(reference: String) -> some View {
        StorefrontImageView(reference: reference, contentMode: .fill) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TBTheme.skyLight.opacity(0.5))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func formattedDate(_ iso: String) -> String {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private func setStatus(_ status: SellerCustomOrderRequest.Status) async {
        actionError = nil
        isUpdating = true
        defer { isUpdating = false }
        do {
            let updated = try await CustomOrderAPI.updateSellerRequestStatus(requestId: request.id, status: status)
            await MainActor.run {
                request = updated
                onUpdated(updated)
            }
        } catch {
            await MainActor.run {
                actionError = (error as NSError).localizedDescription
            }
        }
    }

}

// MARK: - Status styling

private extension SellerCustomOrderRequest.Status {
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }

    var foreground: Color {
        switch self {
        case .pending: return Color.orange.opacity(0.95)
        case .accepted: return Color.green.opacity(0.95)
        case .declined: return Color.secondary
        }
    }

    var background: Color {
        switch self {
        case .pending: return Color.orange.opacity(0.14)
        case .accepted: return Color.green.opacity(0.14)
        case .declined: return Color.gray.opacity(0.12)
        }
    }
}
