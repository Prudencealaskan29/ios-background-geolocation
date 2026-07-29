import Foundation

/// The persisted log store. Method names and semantics mirror
/// `react-native/src/index.ts:280-309`.
extension BackgroundGeolocation {

    /// App-facing log writer — see `Logger`'s doc comment for the `src`
    /// divergence from the RN surface.
    public static var logger: Logger { Logger() }

    /// Newest-first persisted log entries, capped to `1...5000`
    /// (`RNBackgroundGeolocation.mm:316-320`).
    public static func getLog(limit: Int = 500) async -> [LogEntry] {
        let capped = min(max(limit, 1), 5000)
        return engine.logEntries(capped).compactMap(LogEntry.init(dictionary:))
    }

    public static func destroyLog() async -> Int {
        engine.destroyLogs()
    }

    /// Reads `pendingLogCount()` BEFORE `flushLogs()` and returns that count
    /// — draining first would always report zero
    /// (`RNBackgroundGeolocation.mm:327-332`).
    public static func uploadLog() async -> Int {
        let pending = engine.pendingLogCount()
        engine.flushLogs()
        return pending
    }
}

/// App-facing log writer. Every call rides the same persisted log store
/// (`bgeo.db`) and uploader as the engine's own diagnostic lines.
///
/// **Divergence from `react-native/src/index.ts`:** RN writes `src: "js"`;
/// this writes **`src: "native"`**. This IS a native app — there is no JS
/// layer to distinguish from — and `src` is the field the bgeo.dev web
/// console uses to separate engine-authored log lines from app-authored
/// ones in the log stream, so it must name what actually wrote the line.
///
/// **Omitted from this API:** RN's `tag` parameter is the Android logcat
/// category; the iOS bridge already ignores it entirely
/// (`RNBackgroundGeolocation.mm:304-307`). Since it does nothing on this
/// platform, this API doesn't accept it at all rather than accepting a
/// parameter with no effect.
@MainActor
public struct Logger {
    public func error(_ message: String, data: [String: Any]? = nil) {
        write(level: .error, message: message, data: data)
    }

    public func warn(_ message: String, data: [String: Any]? = nil) {
        write(level: .warning, message: message, data: data)
    }

    public func info(_ message: String, data: [String: Any]? = nil) {
        write(level: .info, message: message, data: data)
    }

    public func debug(_ message: String, data: [String: Any]? = nil) {
        write(level: .debug, message: message, data: data)
    }

    public func verbose(_ message: String, data: [String: Any]? = nil) {
        write(level: .verbose, message: message, data: data)
    }

    private func write(level: LogLevel, message: String, data: [String: Any]?) {
        let dataJSON = data.flatMap { dictionary -> String? in
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
            return String(data: jsonData, encoding: .utf8)
        }
        BackgroundGeolocation.engine.log(level: level.rawValue, event: "app", message: message, data: dataJSON, src: "native")
    }
}
