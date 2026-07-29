import XCTest
@testable import BackgroundGeolocation

@MainActor
final class EventHubTests: XCTestCase {

    func testFansOneEngineEventOutToEverySubscriber() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        var first: [[String: Any]] = []
        var second: [[String: Any]] = []
        _ = hub.subscribe("location") { first.append($0) }
        _ = hub.subscribe("location") { second.append($0) }

        engine.emit("location", ["uuid": "a"])

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first.first?["uuid"] as? String, "a")
    }

    func testSubscribersOnlyReceiveTheirOwnEventName() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        var locations = 0
        var heartbeats = 0
        _ = hub.subscribe("location") { _ in locations += 1 }
        _ = hub.subscribe("heartbeat") { _ in heartbeats += 1 }

        engine.emit("heartbeat", [:])

        XCTAssertEqual(locations, 0)
        XCTAssertEqual(heartbeats, 1)
    }

    func testEventsEmittedBeforeAnySubscriberAreBufferedAndReplayedInOrder() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        engine.emit("location", ["uuid": "first"])
        engine.emit("location", ["uuid": "second"])

        var received: [String] = []
        _ = hub.subscribe("location") { received.append($0["uuid"] as? String ?? "") }

        XCTAssertEqual(received, ["first", "second"])
    }

    func testBufferIsCappedAtSixtyFourAndKeepsTheOldest() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        for index in 0..<100 { engine.emit("location", ["i": index]) }

        var received: [Int] = []
        _ = hub.subscribe("location") { received.append($0["i"] as? Int ?? -1) }

        XCTAssertEqual(received.count, 64)
        XCTAssertEqual(received.first, 0)
        XCTAssertEqual(received.last, 63)
    }

    func testBufferIsDrainedSoASecondSubscriberDoesNotReplayIt() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)
        engine.emit("location", ["uuid": "buffered"])

        var firstReceived = 0
        var secondReceived = 0
        _ = hub.subscribe("location") { _ in firstReceived += 1 }
        _ = hub.subscribe("location") { _ in secondReceived += 1 }

        XCTAssertEqual(firstReceived, 1)
        XCTAssertEqual(secondReceived, 0, "the buffer must be consumed once, not replayed per subscriber")
    }

    func testRemovingASubscriptionStopsDelivery() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        var count = 0
        let subscription = hub.subscribe("location") { _ in count += 1 }
        engine.emit("location", [:])
        subscription.remove()
        engine.emit("location", [:])

        XCTAssertEqual(count, 1)
    }

    func testRemovingTwiceIsHarmless() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)
        let subscription = hub.subscribe("location") { _ in }
        subscription.remove()
        subscription.remove()
        engine.emit("location", [:])
    }

    func testRemoveAllDetachesEverySubscriber() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)
        var count = 0
        _ = hub.subscribe("location") { _ in count += 1 }
        _ = hub.subscribe("heartbeat") { _ in count += 1 }
        hub.removeAll()
        engine.emit("location", [:])
        engine.emit("heartbeat", [:])
        XCTAssertEqual(count, 0)
    }

    func testStreamDeliversEventsToAnAsyncConsumer() async {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        let stream = hub.stream("location")
        let task = Task { () -> String? in
            for await event in stream { return event["uuid"] as? String }
            return nil
        }
        // Give the consumer a turn to start iterating before emitting.
        await Task.yield()
        engine.emit("location", ["uuid": "streamed"])

        let received = await task.value
        XCTAssertEqual(received, "streamed")
    }

    func testCancellingAStreamsTaskUnsubscribes() async {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        let stream = hub.stream("location")
        let task = Task { for await _ in stream {} }
        await Task.yield()
        task.cancel()
        await Task.yield()

        engine.emit("location", [:])
        XCTAssertEqual(hub.subscriberCount(for: "location"), 0)
    }

    func testRemoveAllDoesNotDiscardTheBufferForANameThatWasNeverSubscribedTo() {
        // Regression: `removeAll()` used to clear `buffers` unconditionally,
        // so an app calling `removeListeners()` before its first subscribe
        // discarded the launch-time buffer the latch exists to protect.
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        engine.emit("location", ["uuid": "buffered-before-removeAll"])
        hub.removeAll()

        var received: [String] = []
        _ = hub.subscribe("location") { received.append($0["uuid"] as? String ?? "") }

        XCTAssertEqual(received, ["buffered-before-removeAll"])
    }

    func testBufferDoesNotReArmOnceLatchedEvenAfterEverySubscriberIsRemoved() {
        let engine = FakeEngine()
        let hub = EventHub()
        hub.attach(to: engine)

        var firstReceived = 0
        let subscription = hub.subscribe("location") { _ in firstReceived += 1 }
        subscription.remove()

        engine.emit("location", ["uuid": "late"])

        var secondReceived = 0
        _ = hub.subscribe("location") { _ in secondReceived += 1 }

        XCTAssertEqual(firstReceived, 0)
        XCTAssertEqual(secondReceived, 0, "the buffer must not re-arm once it has latched, even with zero current subscribers")
    }
}
