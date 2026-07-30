// Single log pipeline: `LogUploader.logEvent()` writes the structured line
// into the app store (Logs screen) AND into the SDK's own persisted log
// queue via `BackgroundGeolocation.logger`, which survives app kills and
// uploads batches to `/device/logs` with the engine's own auth — unlike an
// app-only buffer that dies with the process.
//
// Swift port of `react-native/example/src/logUploader.ts`; `flutter/example/
// lib/src/log_uploader.dart` is the same port for Flutter. This is the
// app's ONLY logging entry point — `MapScreen`, `SettingsScreen` and
// `GeofenceFormScreen` all call `LogUploader.logEvent` (directly or through
// a thin per-screen wrapper), never `AppStore.appendLog` directly, mirroring
// `logUploader.ts` being RN's sole `logEvent()` call path.
//
// **Platform divergence, discriminator not lost.** `logUploader.ts` writes
// every JS line through the module's native queue tagged `src:"js"`, and
// `LogsScreen.tsx` filters `getLog()`'s poll results back down to
// `src === 'native'` so those JS lines (already streaming live via the app
// store) aren't double-counted. This SDK's own `BackgroundGeolocation.Logger`
// documents that it has no `src` distinction on iOS — every app-facing write
// is tagged `src:"native"` (see `BackgroundGeolocation+Logger.swift`'s doc
// comment: "there is no JS layer to distinguish from"), the same tag genuine
// engine-internal diagnostic lines (track.*/wake.*/motion.*) carry. But
// `Logger.write` (`BackgroundGeolocation+Logger.swift:80`) hard-codes every
// one of those writes to `event: "app"` (the real event name/payload travel
// inside `data` instead), while the engine's own diagnostic lines are always
// dot-namespaced and never `"app"` (`core/ios/Sources/BGGeoEngine.mm`). So
// `event == "app"` is the functional equivalent of RN's `src === 'js'`
// filter, just keyed on a different field — `LogsScreen.swift`'s
// `nativeLogEntries(from:)` uses it to drop these lines from the native
// poll before the merge, the same way RN's filter does.
import Foundation
import BackgroundGeolocation

@MainActor
public enum LogUploader {
    /// Test seam: `BackgroundGeolocation.logger` is a `@MainActor` value type
    /// with no protocol to substitute (same reasoning as `DeviceLink.applyConfig`
    /// and `Geofences`'s `*Call` properties) — tests inject a stub through
    /// this closure instead of touching the real SDK/engine.
    static var write: (LogLevel, String, [String: Any]) -> Void = { level, message, data in
        let logger = BackgroundGeolocation.logger
        switch level {
        case .error: logger.error(message, data: data)
        case .warn: logger.warn(message, data: data)
        case .info: logger.info(message, data: data)
        case .debug: logger.debug(message, data: data)
        case .verbose: logger.verbose(message, data: data)
        }
    }

    /// `logUploader.ts`'s `logEvent`: append the structured line to the app
    /// store's log buffer (Logs screen), then hand the same event to the
    /// SDK's persisted/uploaded log queue with the shape RN sends —
    /// `write(message ?? event, {event, ...(data != nil ? {data} : {})})`.
    public static func logEvent(_ event: String, message: String? = nil, data: Any? = nil, level: LogLevel, store: AppStore) {
        store.appendLog(LogLine(ts: isoTimestamp(), level: level, event: event, message: message, data: data))
        var payload: [String: Any] = ["event": event]
        if let data { payload["data"] = data }
        write(level, message ?? event, payload)
    }
}

private func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}
