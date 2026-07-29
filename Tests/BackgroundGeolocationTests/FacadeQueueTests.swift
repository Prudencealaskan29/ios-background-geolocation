import XCTest
@testable import BackgroundGeolocation

@MainActor
final class FacadeQueueTests: XCTestCase {

    private var engine: FakeEngine!

    override func setUp() async throws {
        engine = FakeEngine()
        BackgroundGeolocation.engine = engine
        BackgroundGeolocation.hub = EventHub()
        BackgroundGeolocation.hub.attach(to: engine)
    }

    // MARK: - sync

    func testSyncReturnsThePreSyncSnapshotAndCallsSyncQueueOnce() async throws {
        engine.stubbedQueuedLocations = ["locations": [FakeEngine.sampleLocationDictionary]]
        // Simulate the queue draining the instant `syncQueue()` is called —
        // if the facade read the snapshot AFTER this, it would see the
        // now-empty queue instead of the pre-sync records.
        engine.onSyncQueue = { [engine] in
            engine?.stubbedQueuedLocations = ["locations": []]
        }

        let result = try await BackgroundGeolocation.sync()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.uuid, "sample-uuid")
        XCTAssertEqual(engine.syncQueueCallCount, 1)
    }

    // MARK: - getLocations

    func testGetLocationsUnwrapsAndDecodes() async {
        engine.stubbedQueuedLocations = ["locations": [FakeEngine.sampleLocationDictionary]]
        let locations = await BackgroundGeolocation.getLocations()
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations.first?.uuid, "sample-uuid")
    }

    func testGetLocationsSkipsAMalformedRecordRatherThanFailing() async {
        let malformed: [String: Any] = ["uuid": "broken"] // missing required fields
        engine.stubbedQueuedLocations = ["locations": [FakeEngine.sampleLocationDictionary, malformed]]
        let locations = await BackgroundGeolocation.getLocations()
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations.first?.uuid, "sample-uuid")
    }

    // MARK: - destroyLocations

    func testDestroyLocationsReturnsTheCount() async {
        engine.stubbedDestroyQueuedLocations = ["count": 3]
        let count = await BackgroundGeolocation.destroyLocations()
        XCTAssertEqual(count, 3)
    }

    // MARK: - destroyLocation

    func testDestroyLocationThrowsNotFoundOnFalse() async {
        engine.stubbedDestroyQueuedLocation = false
        do {
            try await BackgroundGeolocation.destroyLocation(uuid: "missing-uuid")
            XCTFail("expected NOT_FOUND")
        } catch let error as BGeoError {
            XCTAssertEqual(error.code, "NOT_FOUND")
        } catch {
            XCTFail("expected BGeoError, got \(error)")
        }
        XCTAssertEqual(engine.destroyQueuedLocationUuids, ["missing-uuid"])
    }

    func testDestroyLocationSucceedsOnTrue() async throws {
        engine.stubbedDestroyQueuedLocation = true
        try await BackgroundGeolocation.destroyLocation(uuid: "present-uuid")
        XCTAssertEqual(engine.destroyQueuedLocationUuids, ["present-uuid"])
    }

    // MARK: - insertLocation

    func testInsertLocationForwardsTheDictionary() async {
        await BackgroundGeolocation.insertLocation(["uuid": "inserted"])
        XCTAssertEqual(engine.insertedQueuedLocations.count, 1)
        XCTAssertEqual(engine.insertedQueuedLocations.first?["uuid"] as? String, "inserted")
    }

    // MARK: - getCount

    func testGetCountPassesThrough() async {
        engine.stubbedPendingQueueCount = 7
        let count = await BackgroundGeolocation.getCount()
        XCTAssertEqual(count, 7)
    }

    // MARK: - getAuthState

    func testGetAuthStateMapsBothTokens() async {
        engine.stubbedAuthState = ["accessToken": "at-1", "refreshToken": "rt-1"]
        let state = await BackgroundGeolocation.getAuthState()
        XCTAssertEqual(state.accessToken, "at-1")
        XCTAssertEqual(state.refreshToken, "rt-1")
    }

    func testGetAuthStateMapsNilsWhenTokensAreAbsent() async {
        engine.stubbedAuthState = [:]
        let state = await BackgroundGeolocation.getAuthState()
        XCTAssertNil(state.accessToken)
        XCTAssertNil(state.refreshToken)
    }

    // MARK: - getLog

    func testGetLogCapsTheLimitAt5000() async {
        _ = await BackgroundGeolocation.getLog(limit: 999_999)
        XCTAssertEqual(engine.logEntriesLimits, [5000])
    }

    func testGetLogFloorsTheLimitAt1() async {
        _ = await BackgroundGeolocation.getLog(limit: 0)
        XCTAssertEqual(engine.logEntriesLimits, [1])
    }

    func testGetLogPassesThroughAnInRangeLimit() async {
        _ = await BackgroundGeolocation.getLog(limit: 250)
        XCTAssertEqual(engine.logEntriesLimits, [250])
    }

    func testGetLogDecodesEntries() async {
        engine.stubbedLogEntries = [
            ["ts": "2026-01-01T00:00:00.000Z", "level": 3, "src": "native", "event": "app"],
        ]
        let entries = await BackgroundGeolocation.getLog()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.src, "native")
    }

    // MARK: - destroyLog

    func testDestroyLogReturnsTheCount() async {
        engine.stubbedDestroyLogs = 42
        let count = await BackgroundGeolocation.destroyLog()
        XCTAssertEqual(count, 42)
    }

    // MARK: - uploadLog

    func testUploadLogReturnsThePreFlushPendingCountAndCallsFlushLogsOnce() async {
        engine.stubbedPendingLogCount = 5
        // Simulate the log store draining the instant `flushLogs()` is
        // called — if the facade read the pending count AFTER this, it
        // would report zero instead of the pre-flush count.
        engine.onFlushLogs = { [engine] in
            engine?.stubbedPendingLogCount = 0
        }

        let count = await BackgroundGeolocation.uploadLog()

        XCTAssertEqual(count, 5)
        XCTAssertEqual(engine.flushLogsCallCount, 1)
    }

    // MARK: - logger

    func testLoggerWritesEachLevelWithTheRightNumberAndNativeSrc() {
        BackgroundGeolocation.logger.error("e")
        BackgroundGeolocation.logger.warn("w")
        BackgroundGeolocation.logger.info("i")
        BackgroundGeolocation.logger.debug("d")
        BackgroundGeolocation.logger.verbose("v")

        XCTAssertEqual(engine.logCalls.map(\.level), [1, 2, 3, 4, 5])
        XCTAssertEqual(engine.logCalls.map(\.src), Array(repeating: "native", count: 5))
        XCTAssertEqual(engine.logCalls.map(\.event), Array(repeating: "app", count: 5))
        XCTAssertEqual(engine.logCalls.map(\.message), ["e", "w", "i", "d", "v"])
    }

    func testLoggerOmitsDataWhenNotProvided() {
        BackgroundGeolocation.logger.info("no data")
        XCTAssertNil(engine.logCalls.last?.data)
    }

    func testLoggerEncodesDataAsAJSONString() {
        BackgroundGeolocation.logger.info("with data", data: ["a": 1])
        XCTAssertEqual(engine.logCalls.last?.data, "{\"a\":1}")
    }
}
