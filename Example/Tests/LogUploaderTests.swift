import XCTest
@testable import BGeoExample

/// Covers `LogUploader.logEvent` (`Sources/LogUploader.swift`) — the
/// dual-write behaviour ported from `logUploader.ts`: append to the app
/// store's log buffer AND hand the same event to the SDK's log queue via the
/// injectable `write` seam (real `BackgroundGeolocation.logger` calls are
/// never exercised in a unit test — same reasoning as `DeviceLink.applyConfig`).
@MainActor
final class LogUploaderTests: XCTestCase {
    private var originalWrite: ((LogLevel, String, [String: Any]) -> Void)!

    override func setUp() {
        super.setUp()
        originalWrite = LogUploader.write
    }

    override func tearDown() {
        LogUploader.write = originalWrite
        super.tearDown()
    }

    func testLogEventAppendsToStoreWithGivenFields() {
        let store = AppStore()

        LogUploader.logEvent("start", message: "tracking started", level: .info, store: store)

        let line = try! XCTUnwrap(store.logs.last)
        XCTAssertEqual(line.event, "start")
        XCTAssertEqual(line.message, "tracking started")
        XCTAssertEqual(line.level, .info)
        XCTAssertFalse(line.ts.isEmpty)
    }

    func testLogEventForwardsToTheSdkLogQueueWithEventAndDataWrapped() {
        let store = AppStore()
        var captured: (level: LogLevel, message: String, data: [String: Any])?
        LogUploader.write = { level, message, data in captured = (level, message, data) }

        LogUploader.logEvent("setConfig", message: "distanceFilter=30", data: ["distanceFilter": 30], level: .warn, store: store)

        let result = try! XCTUnwrap(captured)
        XCTAssertEqual(result.level, .warn)
        XCTAssertEqual(result.message, "distanceFilter=30")
        XCTAssertEqual(result.data["event"] as? String, "setConfig")
        XCTAssertEqual(result.data["data"] as? [String: Int], ["distanceFilter": 30])
    }

    /// `logUploader.ts`: `write(message ?? event, {event, ...})` — no message
    /// falls back to the event name, and no `data` key is sent at all (not
    /// `data: nil`) when `data` wasn't provided, mirroring the JS spread.
    func testLogEventFallsBackToEventNameAndOmitsAbsentData() {
        let store = AppStore()
        var captured: (level: LogLevel, message: String, data: [String: Any])?
        LogUploader.write = { level, message, data in captured = (level, message, data) }

        LogUploader.logEvent("heartbeat", level: .debug, store: store)

        let result = try! XCTUnwrap(captured)
        XCTAssertEqual(result.message, "heartbeat")
        XCTAssertEqual(result.data.count, 1, "only 'event' should be present, no 'data' key")
        XCTAssertEqual(result.data["event"] as? String, "heartbeat")
    }

    func testLogEventDispatchesEachLevelToTheMatchingWriteCall() {
        let store = AppStore()
        var seenLevels: [LogLevel] = []
        LogUploader.write = { level, _, _ in seenLevels.append(level) }

        for level in [LogLevel.verbose, .debug, .info, .warn, .error] {
            LogUploader.logEvent("x", level: level, store: store)
        }

        XCTAssertEqual(seenLevels, [.verbose, .debug, .info, .warn, .error])
    }
}
