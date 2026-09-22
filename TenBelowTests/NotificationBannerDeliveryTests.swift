import XCTest
@testable import TenBelow

/// Covers the delivery semantics that keep a banner tied to a *new event* rather than to
/// "the latest unread notification".
@MainActor
final class NotificationBannerDeliveryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NotificationBannerDeliveryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// No queue gap, so presentation is synchronous and deterministic.
    private func makeCenter() -> NotificationBannerCenter {
        let center = NotificationBannerCenter(
            userDefaults: defaults,
            crossSourceCoalesceWindow: 120,
            queueTransitionNanoseconds: 0
        )
        center.setSceneActive(true)
        return center
    }

    /// Waits for the queued advance task to promote the next banner.
    @discardableResult
    private func nextBannerKey(
        _ center: NotificationBannerCenter,
        timeout: TimeInterval = 2
    ) async -> String? {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if let current = center.current { return current.presentationKey }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return nil
    }

    /// Gives the advance task a chance to run when nothing is expected to appear.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    private func notification(
        title: String = "Seller message",
        message: String = "Prepp",
        userId: String = "buyer:test@example.com"
    ) -> AppNotification {
        AppNotification(userId: userId, type: .orderSupportUpdate, title: title, message: message)
    }

    func testNewEventPresentsExactlyOnce() {
        let center = makeCenter()
        let note = notification()

        center.deliver(note, presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        XCTAssertEqual(center.current?.notification.title, "Seller message")

        center.dismissCurrent()
        XCTAssertNil(center.current)

        for _ in 0..<5 {
            center.deliver(note, presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        }
        XCTAssertNil(center.current, "A redelivered event must never replay its banner")
    }

    func testRepeatedOfferWhileVisibleDoesNotQueueDuplicate() {
        let center = makeCenter()
        let note = notification()

        center.deliver(note, presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        center.deliver(note, presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        center.dismissCurrent()

        XCTAssertNil(center.current)
    }

    func testTwoMessagesWithIdenticalTextEachPresent() async {
        let center = makeCenter()

        center.deliver(
            notification(message: "Hello"),
            presentationKey: "inbox:supportMessage.buyer.msg-1",
            source: .localEvent
        )
        center.deliver(
            notification(message: "Hello"),
            presentationKey: "inbox:supportMessage.buyer.msg-2",
            source: .localEvent
        )

        XCTAssertEqual(center.current?.presentationKey, "inbox:supportMessage.buyer.msg-1")
        center.dismissCurrent()

        let second = await nextBannerKey(center)
        XCTAssertEqual(
            second,
            "inbox:supportMessage.buyer.msg-2",
            "Identical text from two different messages is two notifications"
        )
    }

    func testQueueDrainsInOrderWithoutOverlapOrLoss() async {
        let center = makeCenter()
        let keys = [
            "inbox:shipmentStatus.o1.s1.shipped",
            "inbox:supportMessage.buyer.msg-9",
            "inbox:exchangeStatus.x1.approved"
        ]

        for key in keys {
            center.deliver(notification(message: key), presentationKey: key, source: .localEvent)
        }

        var presented: [String] = []
        for _ in keys {
            guard let key = await nextBannerKey(center) else { break }
            presented.append(key)
            center.dismissCurrent()
        }

        XCTAssertEqual(presented, keys)

        await settle()
        XCTAssertNil(center.current, "The queue must not replay once drained")
    }

    func testEventsArrivingWhileInactiveAreNotReplayedOnReturn() {
        let center = makeCenter()
        center.setSceneActive(false)

        center.deliver(notification(), presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        XCTAssertNil(center.current)

        center.setSceneActive(true)
        XCTAssertNil(center.current, "Returning from background must not present a past event")
    }

    func testDeliveredEventsDoNotReplayAfterRelaunch() {
        let center = makeCenter()
        center.deliver(notification(), presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        XCTAssertNotNil(center.current)

        let relaunched = makeCenter()
        relaunched.deliver(notification(), presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)

        XCTAssertNil(relaunched.current, "A new launch must not replay an already delivered event")
    }

    func testForegroundPushAndItsLocalTwinPresentOnceViaContentFallback() {
        let center = makeCenter()

        center.deliverForegroundPush(
            requestIdentifier: "apns-1",
            title: "Order shipped",
            body: "Frost Knit Beanie is on the way.",
            userId: "buyer:test@example.com"
        )
        XCTAssertEqual(center.current?.notification.title, "Order shipped")
        center.dismissCurrent()

        center.deliver(
            notification(title: "Order shipped", message: "Frost Knit Beanie is on the way."),
            presentationKey: "inbox:shipmentStatus.o1.s1.shipped",
            source: .localEvent
        )

        XCTAssertNil(center.current, "Legacy push without event id still coalesces on content")
    }

    func testPushEventIdMatchesLocalTwinExactly() {
        let center = makeCenter()
        let eventId = "supportMessage.buyer.msg-42"

        center.deliverForegroundPush(
            requestIdentifier: "apns-1",
            title: "Seller message",
            body: "Hello",
            userId: "buyer:test@example.com",
            eventId: eventId
        )
        XCTAssertEqual(center.current?.presentationKey, "inbox:\(eventId)")
        center.dismissCurrent()

        center.deliver(
            notification(title: "Seller message", message: "Different body is fine"),
            presentationKey: "inbox:\(eventId)",
            source: .localEvent
        )
        XCTAssertNil(center.current, "Shared event id must suppress the local twin exactly")
    }

    func testBackgroundAcknowledgeSuppressesLaterLocalTwin() {
        let center = makeCenter()
        center.setSceneActive(false)

        center.acknowledgeRemoteDelivery(
            eventId: "shipmentStatus.o1.s1.delivered",
            requestIdentifier: "apns-bg-1",
            title: "Order delivered",
            body: "Frost Knit Beanie has been delivered."
        )

        center.setSceneActive(true)
        center.deliver(
            notification(title: "Order delivered", message: "Frost Knit Beanie has been delivered."),
            presentationKey: "inbox:shipmentStatus.o1.s1.delivered",
            source: .localEvent
        )

        XCTAssertNil(center.current, "Background push acknowledgment must block catch-up banners")

        center.deliverForegroundPush(
            requestIdentifier: "apns-live",
            title: "Seller message",
            body: "Running late",
            userId: "buyer:test@example.com",
            eventId: "supportMessage.buyer.live-1"
        )
        XCTAssertEqual(
            center.current?.presentationKey,
            "inbox:supportMessage.buyer.live-1",
            "A genuinely new event after open must still banner"
        )
    }

    func testTwoIdenticalPushesStillPresentTwice() async {
        let center = makeCenter()

        center.deliverForegroundPush(
            requestIdentifier: "apns-1",
            title: "Seller message",
            body: "Hello",
            userId: "buyer:test@example.com"
        )
        center.deliverForegroundPush(
            requestIdentifier: "apns-2",
            title: "Seller message",
            body: "Hello",
            userId: "buyer:test@example.com"
        )

        XCTAssertEqual(center.current?.presentationKey, "push:apns-1")
        center.dismissCurrent()

        let second = await nextBannerKey(center)
        XCTAssertEqual(second, "push:apns-2")
    }

    func testIdentityChangeClearsVisibleBanner() {
        let center = makeCenter()
        center.deliver(notification(), presentationKey: "inbox:supportMessage.buyer.msg-1", source: .localEvent)
        XCTAssertNotNil(center.current)

        center.resetForIdentityChange()
        XCTAssertNil(center.current)
    }
}
