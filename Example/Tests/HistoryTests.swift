import XCTest
@testable import BGeoExample

/// Covers `HistoryLoader` (`Sources/History.swift`, promoted out of
/// `MapScreen.swift` by Task 7 — see that file's header). Moved here
/// verbatim from `MapScreenLogicTests.swift` (which still covers the rest of
/// that screen's pure logic) plus two additions this task's brief calls out
/// explicitly: a malformed record inside an otherwise well-formed response
/// must be skipped rather than sinking the whole call, and an unlinked
/// state (no stored link at all) must return the empty local buffer rather
/// than throwing.
@MainActor
final class HistoryTests: XCTestCase {

    private func point(_ iso: String) -> Point {
        Point(latitude: 1, longitude: 2, timestamp: iso)
    }

    // MARK: - filterPointsByRange (pure)

    func testFilterPointsByRangeKeepsPointsInsideBothBounds() {
        let points = [point("2026-07-01T00:00:00Z"), point("2026-07-15T00:00:00Z"), point("2026-08-01T00:00:00Z")]
        let from = parseISODate("2026-07-10T00:00:00Z")
        let to = parseISODate("2026-07-20T00:00:00Z")
        let result = HistoryLoader.filterPointsByRange(points, from: from, to: to)
        XCTAssertEqual(result.map(\.timestamp), ["2026-07-15T00:00:00Z"])
    }

    func testFilterPointsByRangeWithNilBoundsIsUnbounded() {
        let points = [point("2026-07-01T00:00:00Z"), point("2026-08-01T00:00:00Z")]
        let result = HistoryLoader.filterPointsByRange(points, from: nil, to: nil)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterPointsByRangeDropsUnparsableTimestamps() {
        let points = [point("not-a-date")]
        let result = HistoryLoader.filterPointsByRange(points, from: nil, to: parseISODate("2026-01-01T00:00:00Z"))
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - point(fromServerJSON:) (pure)

    func testServerJSONDecodesTheConsoleCamelCaseShape() throws {
        let json: [String: Any] = [
            "uuid": "u-1",
            "recordedAt": "2026-07-01T12:00:00Z",
            "lat": 52.5,
            "lng": 13.4,
            "accuracy": 5.5,
            "speed": 2.1,
            "heading": 90.0,
            "odometer": 1000.0,
            "activityType": "walking",
            "isMoving": true,
            "event": "motionchange",
        ]
        let point = try XCTUnwrap(HistoryLoader.point(fromServerJSON: json))
        XCTAssertEqual(point.uuid, "u-1")
        XCTAssertEqual(point.timestamp, "2026-07-01T12:00:00Z")
        XCTAssertEqual(point.latitude, 52.5)
        XCTAssertEqual(point.longitude, 13.4)
        XCTAssertEqual(point.accuracy, 5.5)
        XCTAssertEqual(point.speed, 2.1)
        XCTAssertEqual(point.heading, 90.0)
        XCTAssertEqual(point.odometer, 1000.0)
        XCTAssertEqual(point.activity, "walking")
        XCTAssertEqual(point.isMoving, true)
        XCTAssertEqual(point.event, "motionchange")
    }

    func testServerJSONFallsBackToActivityFieldWhenActivityTypeMissing() throws {
        let json: [String: Any] = ["recordedAt": "2026-07-01T12:00:00Z", "lat": 1.0, "lng": 2.0, "activity": "still"]
        let point = try XCTUnwrap(HistoryLoader.point(fromServerJSON: json))
        XCTAssertEqual(point.activity, "still")
    }

    func testServerJSONReturnsNilWhenARequiredFieldIsMissing() {
        XCTAssertNil(HistoryLoader.point(fromServerJSON: ["recordedAt": "2026-07-01T12:00:00Z", "lat": 1.0]))
        XCTAssertNil(HistoryLoader.point(fromServerJSON: ["lat": 1.0, "lng": 2.0]))
    }

    // MARK: - load (linked vs. unlinked source switch)

    private func makeDeviceLink() -> (DeviceLink, String) {
        let suiteName = "HistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = AppStore()
        let link = DeviceLink(store: store, session: session, defaults: defaults)
        let storedLink = StoredLink(serverUrl: "https://test.bgeo.dev", deviceId: "dev-1", accessToken: "tok", refreshToken: "rtok", installUuid: "uuid-1")
        defaults.set(try! JSONEncoder().encode(storedLink), forKey: "bgeo:link")
        return (link, suiteName)
    }

    func testLoadWhenLinkedUsesServerHistoryReversedToOldestFirst() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub("GET", "/device/locations", status: 200, json: [
            "locations": [
                ["uuid": "b", "recordedAt": "2026-07-02T00:00:00Z", "lat": 2.0, "lng": 2.0],
                ["uuid": "a", "recordedAt": "2026-07-01T00:00:00Z", "lat": 1.0, "lng": 1.0],
            ],
        ])
        let (link, suiteName) = makeDeviceLink()
        defer { UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName) }

        let result = await HistoryLoader.load(from: nil, to: nil, linked: true, localPoints: [], deviceLink: link)

        // Server returns newest-first ("b" then "a"); `load` reverses to oldest-first.
        XCTAssertEqual(result.map(\.uuid), ["a", "b"])
    }

    func testLoadWhenNotLinkedFiltersTheLocalBuffer() async {
        StubURLProtocol.reset()
        let (link, suiteName) = makeDeviceLink()
        defer { UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName) }
        let local = [point("2026-07-01T00:00:00Z"), point("2026-08-01T00:00:00Z")]

        let result = await HistoryLoader.load(
            from: parseISODate("2026-07-15T00:00:00Z"),
            to: nil,
            linked: false,
            localPoints: local,
            deviceLink: link
        )

        // Never touches the network when not linked (StubURLProtocol has no stub registered).
        XCTAssertEqual(result.map(\.timestamp), ["2026-08-01T00:00:00Z"])
    }

    /// Self-review requirement: a malformed record inside the server's
    /// `locations` array (missing a required field) must be dropped by
    /// `compactMap`, not sink the whole call or crash.
    func testLoadSkipsMalformedRecordsInServerResponseWithoutFailingTheCall() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub("GET", "/device/locations", status: 200, json: [
            "locations": [
                ["uuid": "good-1", "recordedAt": "2026-07-02T00:00:00Z", "lat": 2.0, "lng": 2.0],
                ["uuid": "missing-lat", "recordedAt": "2026-07-02T00:00:00Z", "lng": 2.0],
                ["uuid": "missing-recordedAt", "lat": 1.0, "lng": 1.0],
                ["uuid": "good-2", "recordedAt": "2026-07-01T00:00:00Z", "lat": 1.0, "lng": 1.0],
            ],
        ])
        let (link, suiteName) = makeDeviceLink()
        defer { UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName) }

        let result = await HistoryLoader.load(from: nil, to: nil, linked: true, localPoints: [], deviceLink: link)

        // Only the two well-formed records survive, still reversed to oldest-first.
        XCTAssertEqual(result.map(\.uuid), ["good-2", "good-1"])
    }

    /// Self-review requirement: an unlinked state (no stored link, so
    /// `DeviceLink.deviceFetch` returns nil) returns the empty local buffer
    /// rather than throwing. `load` is non-throwing by signature, so this
    /// documents the actual empty-array outcome rather than just "didn't
    /// crash".
    func testLoadReturnsEmptyWhenUnlinkedAndNoLocalPoints() async {
        StubURLProtocol.reset()
        let suiteName = "HistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let link = DeviceLink(store: AppStore(), session: session, defaults: defaults)
        // Deliberately no seeded `StoredLink` — this is the "unlinked" case.

        let result = await HistoryLoader.load(from: nil, to: nil, linked: true, localPoints: [], deviceLink: link)

        XCTAssertTrue(result.isEmpty)
        // No network call was made at all (no stub registered, and none captured).
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }
}
