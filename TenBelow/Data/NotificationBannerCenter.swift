//
//  NotificationBannerCenter.swift
//  TenBelow
//
//  Owns transient in-app banner *delivery*, which is a different concept from the
//  notification inbox in `NotificationStore`.
//
//  A row can stay unread, live in history, and drive the badge forever without ever
//  being eligible for a banner again. A banner represents the moment an event was
//  delivered, so it is offered exactly once per event and never replayed by app
//  launch, tab switches, `onAppear`, refreshes, or history decoding.
//

import Foundation
import Combine
import os
#if os(iOS)
import UserNotifications
#endif

private let bannerLogger = Logger(
    subsystem: "com.innovativecodeworks.com.TenBelow",
    category: "NotificationBanner"
)

/// Custom APNs payload key for the stable marketplace event identity.
/// Must stay aligned with `tb.eventId` in `tenbelow-backend/apnsSend.js`.
enum NotificationPushPayload {
    static let eventIdKey = "tb.eventId"
}

@MainActor
final class NotificationBannerCenter: ObservableObject {
    /// Where a delivery came from. Used only to coalesce a foreground push against the
    /// local event that describes the same thing when no shared event id is present.
    enum Source {
        case localEvent
        case remotePush
    }

    /// One transient presentation. `presentationKey` is the *delivery* identity and is
    /// deliberately not the inbox row id, which is a fresh UUID per stored row.
    struct Request: Identifiable, Equatable {
        let presentationKey: String
        let notification: AppNotification

        var id: String { presentationKey }
    }

    static let shared = NotificationBannerCenter()

    @Published private(set) var current: Request?

    private let deliveredKeysStorageKey = "notificationBanner.deliveredPresentationKeys"
    private let maxPersistedDeliveredKeys = 400
    private let userDefaults: UserDefaults
    /// Fallback only: push and local twin without a shared `tb.eventId` are coalesced on
    /// normalized title+body within this window.
    private let crossSourceCoalesceWindow: TimeInterval
    private let queueTransitionNanoseconds: UInt64

    private var queue: [Request] = []
    private var deliveredKeys: [String]
    private var deliveredKeySet: Set<String>
    private var recentDeliveries: [(fingerprint: String, source: Source, at: Date)] = []
    private var isSceneActive = false
    private var isInteracting = false
    private var autoDismissTask: Task<Void, Never>?
    private var queueAdvanceTask: Task<Void, Never>?
    private var deliveredNotificationIngestTask: Task<Void, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        crossSourceCoalesceWindow: TimeInterval = 120,
        queueTransitionNanoseconds: UInt64 = 260_000_000
    ) {
        self.userDefaults = userDefaults
        self.crossSourceCoalesceWindow = crossSourceCoalesceWindow
        self.queueTransitionNanoseconds = queueTransitionNanoseconds

        let stored: [String] = LocalCodableStore.load(
            key: deliveredKeysStorageKey,
            default: [],
            userDefaults: userDefaults
        )
        deliveredKeys = stored
        deliveredKeySet = Set(stored)
    }

    // MARK: - Scene state

    /// Banners are only drawn while the scene is active. Events that land while the app is
    /// backgrounded are still recorded as delivered so foregrounding never replays them.
    func setSceneActive(_ isActive: Bool) {
        guard isSceneActive != isActive else { return }
        isSceneActive = isActive

        guard !isActive else {
            ingestDeliveredSystemNotifications()
            return
        }
        clearPresentationState()
    }

    /// Clears anything on screen when the signed-in buyer/seller identity changes.
    func resetForIdentityChange() {
        clearPresentationState()
    }

    /// Drops what is on screen and anything waiting. Already-delivered keys stay recorded, so
    /// nothing that is discarded here can come back later.
    private func clearPresentationState() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        queueAdvanceTask?.cancel()
        queueAdvanceTask = nil
        deliveredNotificationIngestTask?.cancel()
        deliveredNotificationIngestTask = nil
        queue.removeAll()
        isInteracting = false
        current = nil
    }

    // MARK: - Delivery

    /// Offers an event for a one-time banner. Safe to call repeatedly: only the first call
    /// for a given `presentationKey` can ever present.
    func deliver(_ notification: AppNotification, presentationKey: String, source: Source) {
        guard !deliveredKeySet.contains(presentationKey) else {
            bannerLogger.debug("skip already-delivered key=\(presentationKey, privacy: .public)")
            return
        }

        let fingerprint = Self.contentFingerprint(for: notification)
        if isCoalescedAcrossSources(fingerprint: fingerprint, source: source) {
            bannerLogger.debug("skip cross-source duplicate key=\(presentationKey, privacy: .public)")
            recordDelivered(presentationKey, fingerprint: fingerprint, source: source)
            return
        }

        recordDelivered(presentationKey, fingerprint: fingerprint, source: source)

        // Recorded but not shown: the user was not looking at TenBelow, and iOS already
        // handled the system-level alert.
        guard isSceneActive else { return }

        queue.append(Request(presentationKey: presentationKey, notification: notification))
        presentNextIfIdle()
    }

    /// Presents a foreground APNs alert.
    ///
    /// Prefers `tb.eventId` (shared with the local inbox dedupe key) so a push and its local
    /// twin suppress each other exactly. Falls back to the APNs request identifier when the
    /// payload is legacy / missing an event id.
    func deliverForegroundPush(
        requestIdentifier: String,
        title: String,
        body: String,
        userId: String,
        eventId: String? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return }

        let notification = AppNotification(
            userId: userId,
            type: Self.inferredType(title: trimmedTitle, body: trimmedBody),
            title: trimmedTitle.isEmpty ? "TenBelow" : trimmedTitle,
            message: trimmedBody,
            dedupeKey: Self.normalizedEventId(eventId)
        )

        deliver(
            notification,
            presentationKey: Self.presentationKey(
                eventId: eventId,
                fallbackRequestIdentifier: requestIdentifier
            ),
            source: .remotePush
        )
    }

    /// Marks a remote delivery as already shown by iOS (background/inactive) without drawing
    /// TenBelow's custom banner. The matching local event later will not replay.
    func acknowledgeRemoteDelivery(eventId: String?, requestIdentifier: String, title: String, body: String) {
        let key = Self.presentationKey(eventId: eventId, fallbackRequestIdentifier: requestIdentifier)
        let note = AppNotification(
            userId: "remote",
            type: Self.inferredType(title: title, body: body),
            title: title,
            message: body,
            dedupeKey: Self.normalizedEventId(eventId)
        )
        recordDelivered(key, fingerprint: Self.contentFingerprint(for: note), source: .remotePush)
        // Alias the inbox key explicitly when present so local `inbox:<eventId>` matches even if
        // presentationKey already used that form (recordDelivered is idempotent on the set).
        if let eventId = Self.normalizedEventId(eventId) {
            recordDelivered(
                "inbox:\(eventId)",
                fingerprint: Self.contentFingerprint(for: note),
                source: .remotePush
            )
        }
    }

    // MARK: - Presentation lifecycle

    func dismissCurrent() {
        guard current != nil else { return }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isInteracting = false
        current = nil
        scheduleQueueAdvance()
    }

    /// Holds the auto-dismiss timer while a finger is down so a banner is never yanked
    /// out from under an in-progress tap.
    func setInteracting(_ isInteracting: Bool) {
        guard self.isInteracting != isInteracting else { return }
        self.isInteracting = isInteracting

        guard let current else { return }
        if isInteracting {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        } else {
            scheduleAutoDismiss(for: current)
        }
    }

    private func presentNextIfIdle() {
        guard isSceneActive, current == nil, queueAdvanceTask == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        scheduleAutoDismiss(for: next)
    }

    private func scheduleAutoDismiss(for request: Request) {
        autoDismissTask?.cancel()
        let delay = NotificationBannerPresentation.dismissDelay(for: request.notification)
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard let self, self.current?.presentationKey == request.presentationKey else { return }
            self.dismissCurrent()
        }
    }

    /// Brief gap between banners so the exit and the next entrance stay legible.
    private func scheduleQueueAdvance() {
        guard !queue.isEmpty else { return }
        queueAdvanceTask?.cancel()
        queueAdvanceTask = Task { [weak self] in
            let gap = self?.queueTransitionNanoseconds ?? 0
            try? await Task.sleep(nanoseconds: gap)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.queueAdvanceTask = nil
            self.presentNextIfIdle()
        }
    }

    // MARK: - System delivered-notification harvest

    /// Reads Notification Center for alerts iOS already showed while TenBelow was away, and
    /// marks their `tb.eventId` values delivered so the post-open refresh cannot banner them.
    private func ingestDeliveredSystemNotifications() {
        #if os(iOS)
        deliveredNotificationIngestTask?.cancel()
        deliveredNotificationIngestTask = Task { [weak self] in
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            guard !Task.isCancelled, let self else { return }
            for notification in delivered {
                let content = notification.request.content
                let eventId = content.userInfo[NotificationPushPayload.eventIdKey] as? String
                self.acknowledgeRemoteDelivery(
                    eventId: eventId,
                    requestIdentifier: notification.request.identifier,
                    title: content.title,
                    body: content.body
                )
            }
        }
        #endif
    }

    // MARK: - Dedupe bookkeeping

    private func recordDelivered(_ key: String, fingerprint: String, source: Source) {
        if !deliveredKeySet.contains(key) {
            deliveredKeySet.insert(key)
            deliveredKeys.append(key)
            if deliveredKeys.count > maxPersistedDeliveredKeys {
                let overflow = deliveredKeys.count - maxPersistedDeliveredKeys
                deliveredKeys.removeFirst(overflow)
                deliveredKeySet = Set(deliveredKeys)
                bannerLogger.debug("trimmed delivered keys overflow=\(overflow, privacy: .public)")
            }
            LocalCodableStore.save(deliveredKeys, key: deliveredKeysStorageKey, userDefaults: userDefaults)
        }

        let now = Date.now
        recentDeliveries.removeAll { now.timeIntervalSince($0.at) > crossSourceCoalesceWindow }
        recentDeliveries.append((fingerprint: fingerprint, source: source, at: now))
    }

    private func isCoalescedAcrossSources(fingerprint: String, source: Source) -> Bool {
        let now = Date.now
        return recentDeliveries.contains { entry in
            entry.source != source
                && entry.fingerprint == fingerprint
                && now.timeIntervalSince(entry.at) <= crossSourceCoalesceWindow
        }
    }

    static func presentationKey(eventId: String?, fallbackRequestIdentifier: String) -> String {
        if let eventId = normalizedEventId(eventId) {
            return "inbox:\(eventId)"
        }
        return "push:\(fallbackRequestIdentifier)"
    }

    static func normalizedEventId(_ eventId: String?) -> String? {
        let trimmed = eventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalized title + message opening, used only across sources when no event id exists.
    private static func contentFingerprint(for notification: AppNotification) -> String {
        "\(normalized(notification.title))|\(normalized(notification.message).prefix(48))"
    }

    private static func normalized(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " "
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
    }

    /// Presentation-only mapping for push payloads, which carry no type. This picks an
    /// icon and accent; it never records anything or changes inbox behavior.
    private static func inferredType(title: String, body: String) -> NotificationType {
        let haystack = "\(title) \(body)".lowercased()

        if haystack.contains("message") || haystack.contains("replied") {
            return .orderSupportUpdate
        }
        if haystack.contains("exchange") || haystack.contains("replacement") {
            return .exchangeUpdate
        }
        if haystack.contains("new order") {
            return .orderReceived
        }
        if haystack.contains("price drop") {
            return .priceDrop
        }
        if haystack.contains("flagged") || haystack.contains("frozen") || haystack.contains("account") {
            return .system
        }
        return .orderStatusUpdate
    }
}
