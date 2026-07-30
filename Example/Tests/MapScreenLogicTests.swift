import XCTest
@testable import BGeoExample

/// Covers the pure logic pulled out of `MapScreen.swift`/`CoordinatesSheet.swift`
/// — the screens themselves are view code with no unit tests (per the task
/// brief, verified instead by a simulator run; see the task report). This
/// file is the "test the logic instead" half of that rule: track paging,
/// the history-source switch, geofence action coloring, and coordinate/time
/// formatting.
@MainActor
final class MapScreenLogicTests: XCTestCase {

    // MARK: - MapPaging.window

    func testWindowUnderOnePageIsTheWholeRangeOnNewestPage() {
        let window = MapPaging.window(totalCount: 5, page: 0, pageSize: 10)
        XCTAssertEqual(window, MapWindow(effPage: 0, pageCount: 1, windowStart: 0, windowEnd: 5, onNewestPage: true))
    }

    func testWindowExactMultipleOfPageSizeSplitsCleanly() {
        // 2500 points, page size 1000 -> 3 pages (1000, 1000, 500).
        let page0 = MapPaging.window(totalCount: 2500, page: 0, pageSize: 1000)
        XCTAssertEqual(page0, MapWindow(effPage: 0, pageCount: 3, windowStart: 1500, windowEnd: 2500, onNewestPage: true))

        let page1 = MapPaging.window(totalCount: 2500, page: 1, pageSize: 1000)
        XCTAssertEqual(page1, MapWindow(effPage: 1, pageCount: 3, windowStart: 500, windowEnd: 1500, onNewestPage: false))

        let page2 = MapPaging.window(totalCount: 2500, page: 2, pageSize: 1000)
        XCTAssertEqual(page2, MapWindow(effPage: 2, pageCount: 3, windowStart: 0, windowEnd: 500, onNewestPage: false))
    }

    func testWindowClampsAPageRequestPastTheOldestPage() {
        // Only 2 pages exist (1500 points / 1000) — requesting page 9 clamps to page 1 (the oldest).
        let window = MapPaging.window(totalCount: 1500, page: 9, pageSize: 1000)
        XCTAssertEqual(window.effPage, 1)
        XCTAssertEqual(window.windowStart, 0)
        XCTAssertEqual(window.windowEnd, 500)
    }

    func testWindowWithZeroPointsStaysOnASinglePage() {
        let window = MapPaging.window(totalCount: 0, page: 0, pageSize: 1000)
        XCTAssertEqual(window, MapWindow(effPage: 0, pageCount: 1, windowStart: 0, windowEnd: 0, onNewestPage: true))
    }

    func testWindowNegativePageClampsToZero() {
        let window = MapPaging.window(totalCount: 50, page: -3, pageSize: 10)
        XCTAssertEqual(window.effPage, 0)
    }

    // MARK: - GeofenceColors

    func testGeofenceColorsMapEachActionCaseInsensitively() {
        XCTAssertEqual(GeofenceColors.hex(forAction: "ENTER"), GeofenceColors.enter)
        XCTAssertEqual(GeofenceColors.hex(forAction: "enter"), GeofenceColors.enter)
        XCTAssertEqual(GeofenceColors.hex(forAction: "Exit"), GeofenceColors.exit)
        XCTAssertEqual(GeofenceColors.hex(forAction: "dwell"), GeofenceColors.dwell)
    }

    func testGeofenceColorsFallsBackForUnknownOrMissingAction() {
        XCTAssertEqual(GeofenceColors.hex(forAction: "SOMETHING_ELSE"), GeofenceColors.fallback)
        XCTAssertEqual(GeofenceColors.hex(forAction: nil), GeofenceColors.fallback)
    }

    // MARK: - HistoryLoader.filterPointsByRange (pure)

    private func point(_ iso: String) -> Point {
        Point(latitude: 1, longitude: 2, timestamp: iso)
    }

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

    // MARK: - HistoryLoader.point(fromServerJSON:) (pure)

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

    // MARK: - HistoryLoader.load (linked vs. unlinked source switch)

    private func makeDeviceLink() -> (DeviceLink, String) {
        let suiteName = "MapScreenLogicTests-\(UUID().uuidString)"
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

    // MARK: - parseISODate

    func testParseISODateAcceptsFractionalAndPlainSeconds() {
        XCTAssertNotNil(parseISODate("2026-07-01T12:00:00.123Z"))
        XCTAssertNotNil(parseISODate("2026-07-01T12:00:00Z"))
        XCTAssertNil(parseISODate("not-a-date"))
    }

    // MARK: - PointFormat

    func testPointFormatTimeFormatsLocalWallClock() {
        // Fixed instant so the test is deterministic regardless of the CI
        // machine's timezone: format, then re-derive expected H:M:S the same
        // way the formatter does (local `Calendar.current`), rather than
        // hardcoding a specific timezone's clock time.
        let iso = "2026-07-01T12:34:56Z"
        let date = parseISODate(iso)!
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let expected = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        XCTAssertEqual(PointFormat.time(fromISO: iso), expected)
    }

    func testPointFormatTimeFallsBackOnUnparsableTimestamp() {
        XCTAssertEqual(PointFormat.time(fromISO: "garbage"), "--:--:--")
    }

    func testPointFormatCoordinateFixedDigits() {
        XCTAssertEqual(PointFormat.coordinate(52.123456789), "52.12346")
    }

    func testPointFormatNonNegativeDashesOutMissingOrNegative() {
        XCTAssertEqual(PointFormat.nonNegative(nil, digits: 1), "–")
        XCTAssertEqual(PointFormat.nonNegative(-1, digits: 1), "–")
        XCTAssertEqual(PointFormat.nonNegative(3.14, digits: 1), "3.1")
    }

    func testPointFormatRoundedOrDashHandlesNilAndNormalValues() {
        XCTAssertEqual(PointFormat.roundedOrDash(nil), "–")
        XCTAssertEqual(PointFormat.roundedOrDash(4.6), "5")
    }

    /// The exact crash class this repo hit three times: `Int(_:)` on an
    /// out-of-range `Double` traps. `roundedOrDash` must degrade instead.
    func testPointFormatRoundedOrDashDoesNotTrapOnHugeMagnitude() {
        let huge = 1.0e21
        XCTAssertNoThrow(_ = PointFormat.roundedOrDash(huge))
        XCTAssertEqual(PointFormat.roundedOrDash(huge), String(format: "%.0f", huge))
    }

    func testPointFormatHeadingDashesOutNegativeOrMissing() {
        XCTAssertEqual(PointFormat.heading(nil), "–")
        XCTAssertEqual(PointFormat.heading(-1), "–")
        XCTAssertEqual(PointFormat.heading(270.4), "270°")
    }

    func testPointFormatIsMovingTristate() {
        XCTAssertEqual(PointFormat.isMoving(nil), "–")
        XCTAssertEqual(PointFormat.isMoving(true), "yes")
        XCTAssertEqual(PointFormat.isMoving(false), "no")
    }

    func testPointFormatEventLabelForGeofencePoint() {
        let point = Point(
            latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z",
            event: "geofence", geofence: PointGeofence(identifier: "home", action: "enter")
        )
        XCTAssertEqual(PointFormat.eventLabel(point), "home · ENTER")
    }

    func testPointFormatEventLabelForGeofencePointWithoutAction() {
        let point = Point(
            latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z",
            event: "geofence", geofence: PointGeofence(identifier: "home")
        )
        XCTAssertEqual(PointFormat.eventLabel(point), "home")
    }

    func testPointFormatEventLabelForNonGeofencePoint() {
        let point = Point(latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z", event: "motionchange")
        XCTAssertEqual(PointFormat.eventLabel(point), "motionchange")

        let noEvent = Point(latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")
        XCTAssertEqual(PointFormat.eventLabel(noEvent), "-")
    }
}
