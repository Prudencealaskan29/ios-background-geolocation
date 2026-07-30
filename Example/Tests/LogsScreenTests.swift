import XCTest
@testable import BGeoExample
import BackgroundGeolocation

/// Covers the pure logic pulled out of `LogsScreen.swift` — the screen
/// itself is view code with no unit tests, verified instead by a simulator
/// run (same rule `MapScreenLogicTests.swift` documents for `MapScreen`).
@MainActor
final class LogsScreenTests: XCTestCase {

    // MARK: - nativeLogEntries — the `event == "app"` dedup filter

    func testNativeLogEntriesDropsAppTaggedEntriesButKeepsEngineEntries() {
        let appTagged = entry(level: 3, event: "app")
        let engineTagged = entry(level: 3, event: "track.start")

        let result = nativeLogEntries(from: [appTagged, engineTagged])

        XCTAssertEqual(result.map(\.event), ["track.start"])
    }

    /// The exact regression the code review caught: routing every screen's
    /// logging through `LogUploader.logEvent` means the same line now lands
    /// in `AppStore.logs` (live) AND, via `Logger.write`'s hard-coded
    /// `event: "app"`, in the SDK's native queue that `getLog()` polls. If
    /// `nativeLogEntries` didn't filter that back out before the merge, an
    /// app-authored line would appear twice once the poll caught up to it.
    func testAppAuthoredLineAppearsExactlyOnceInTheMergedViewNotTwice() {
        let appLine = LogLine(ts: "2026-07-01T12:00:00.000Z", level: .info, event: "start", message: "tracking started")
        // What `getLog()` would return for that same call once `Logger.write`
        // persists it: hard-coded `event: "app"`, real event name in `data`.
        let queuedDuplicate = entry(level: 3, event: "app", ts: "2026-07-01T12:00:00.000Z")
        let genuineEngineLine = entry(level: 3, event: "track.start", ts: "2026-07-01T12:00:01.000Z")

        let nativeLines = nativeLogEntries(from: [queuedDuplicate, genuineEngineLine]).map(logLine(from:))
        let merged = mergeAndFilterLogs(appLogs: [appLine], nativeLines: nativeLines, level: .all)

        XCTAssertEqual(merged.map(\.event), ["start", "track.start"], "the app-authored line must appear exactly once, not twice")
    }

    // MARK: - logLine(from:) — numeric level -> LogLevel name

    private func entry(level: Int, event: String = "track.accept", ts: String = "2026-07-01T12:00:00.123Z") -> LogEntry {
        try! XCTUnwrap(LogEntry(dictionary: ["ts": ts, "level": level, "src": "native", "event": event]))
    }

    func testLogLineMapsEachNumericLevelToTheMatchingName() {
        XCTAssertEqual(logLine(from: entry(level: 1)).level, .error)
        XCTAssertEqual(logLine(from: entry(level: 2)).level, .warn)
        XCTAssertEqual(logLine(from: entry(level: 3)).level, .info)
        XCTAssertEqual(logLine(from: entry(level: 4)).level, .debug)
        XCTAssertEqual(logLine(from: entry(level: 5)).level, .verbose)
    }

    func testLogLineFallsBackToInfoForOffOrUnrecognisedLevel() {
        // 0 = LogLevel.off; 99 doesn't decode to any BackgroundGeolocation.LogLevel case.
        XCTAssertEqual(logLine(from: entry(level: 0)).level, .info)
        XCTAssertEqual(logLine(from: entry(level: 99)).level, .info)
    }

    func testLogLineCarriesTsEventMessageAndData() throws {
        let raw = try XCTUnwrap(LogEntry(dictionary: [
            "ts": "2026-07-01T12:00:00.000Z", "level": 3, "src": "native",
            "event": "wake.region", "message": "armed", "data": ["radius": 200],
        ]))
        let line = logLine(from: raw)
        XCTAssertEqual(line.ts, "2026-07-01T12:00:00.000Z")
        XCTAssertEqual(line.event, "wake.region")
        XCTAssertEqual(line.message, "armed")
        XCTAssertEqual(line.data as? [String: Int], ["radius": 200])
    }

    // MARK: - mergeAndFilterLogs

    // `LogLevel` collides between `BGeoExample` (via `@testable import`) and
    // `BackgroundGeolocation` in this file — qualified explicitly, see
    // `LogsScreen.swift`'s header for the full story.
    private func line(_ ts: String, _ level: BGeoExample.LogLevel = .info, event: String = "e") -> LogLine {
        LogLine(ts: ts, level: level, event: event)
    }

    func testMergeAndFilterLogsSortsBothSourcesByTimestamp() {
        let appLogs = [line("2026-07-01T12:00:02Z"), line("2026-07-01T12:00:00Z")]
        let native = [line("2026-07-01T12:00:01Z")]

        let result = mergeAndFilterLogs(appLogs: appLogs, nativeLines: native, level: .all)

        XCTAssertEqual(result.map(\.ts), ["2026-07-01T12:00:00Z", "2026-07-01T12:00:01Z", "2026-07-01T12:00:02Z"])
    }

    func testMergeAndFilterLogsAllLevelDoesNotFilter() {
        let logs = [line("t1", .error), line("t2", .verbose)]
        let result = mergeAndFilterLogs(appLogs: logs, nativeLines: [], level: .all)
        XCTAssertEqual(result.count, 2)
    }

    func testMergeAndFilterLogsFiltersToOneLevel() {
        let logs = [line("t1", .error), line("t2", .verbose), line("t3", .error)]
        let result = mergeAndFilterLogs(appLogs: logs, nativeLines: [], level: .error)
        XCTAssertEqual(result.map(\.event).count, 2)
        XCTAssertTrue(result.allSatisfy { $0.level == .error })
    }

    // MARK: - logLevelColor — faithful to LogsScreen.tsx's levelColor

    func testLogLevelColorMapsEachLevelToTheDocumentedToken() {
        let colors = lightColors
        XCTAssertEqual(logLevelColor(.verbose, colors), colors.placeholder)
        XCTAssertEqual(logLevelColor(.debug, colors), colors.textDim)
        XCTAssertEqual(logLevelColor(.info, colors), colors.accentText)
        XCTAssertEqual(logLevelColor(.warn, colors), colors.warningText)
        XCTAssertEqual(logLevelColor(.error, colors), colors.dangerText)
    }

    // MARK: - logTimeSlice

    func testLogTimeSliceExtractsHmsMillis() {
        XCTAssertEqual(logTimeSlice("2026-07-01T12:34:56.789Z"), "12:34:56.789")
    }

    func testLogTimeSliceDoesNotTrapOnAShortString() {
        XCTAssertEqual(logTimeSlice("short"), "short")
    }

    // MARK: - logDataDescription

    func testLogDataDescriptionReturnsNilForNil() {
        XCTAssertNil(logDataDescription(nil))
    }

    func testLogDataDescriptionJSONEncodesADictionary() {
        XCTAssertEqual(logDataDescription(["a": 1]), "{\"a\":1}")
    }
}
