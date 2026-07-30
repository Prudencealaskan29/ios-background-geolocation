// Single log pipeline: `LogUploader.logEvent()` writes the structured line
// into the app store (Logs screen) AND into the SDK's own persisted log
// queue via `BackgroundGeolocation.logger`, which survives app kills and
// uploads batches to `/device/logs` with the engine's own auth — unlike an
// app-only buffer that dies with the process.
//
// Swift port of `react-native/example/src/logUploader.ts`; `flutter/example/
// lib/src/log_uploader.dart` is the same port for Flutter.
//
// **One deliberate platform divergence.** `logUploader.ts` writes every JS
// line through the module's native queue tagged `src:"js"`, and
// `LogsScreen.tsx` filters `getLog()`'s poll results back down to
// `src === 'native'` so those JS lines (already streaming live via the app
// store) aren't double-counted. This SDK's own `BackgroundGeolocation.Logger`
// documents that it has no such distinction on iOS — every app-facing write
// is tagged `src:"native"` (see `BackgroundGeolocation+Logger.swift`'s doc
// comment: "there is no JS layer to distinguish from"), the same tag genuine
// engine-internal diagnostic lines (track.*/wake.*/motion.*) carry. Routing
// every `AppStore.appendLog` call site in this app through `LogUploader`
// would therefore make every UI-triggered log line reappear a poll cycle
// later in `LogsScreen`'s native merge with no `src` field left to
// distinguish it from a genuine engine line — RN's dedup key doesn't exist
// here. Rather than invent a replacement dedup mechanism with no reference
// counterpart, this app's existing screens (`MapScreen`, `SettingsScreen`,
// `GeofenceFormScreen`) keep writing directly to `AppStore.appendLog` only,
// same as before this task. `LogUploader` stands as the tested, reusable
// single-pipeline primitive the brief asks for, ready for a call site that
// actually wants a UI action persisted/uploaded through the engine's own
// queue — see the task report for the full reasoning.
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
