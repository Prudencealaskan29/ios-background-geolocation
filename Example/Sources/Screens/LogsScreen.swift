// Logs screen — the same event stream and formatting as the web console's
// LogStream (ts / [LEVEL] / event / message / data, same colors), with a
// level filter, follow-tail and clear.
//
// Swift port of `react-native/example/src/screens/LogsScreen.tsx` (175
// lines); `flutter/example/lib/src/screens/logs_screen.dart` is the same
// port for Flutter.
//
// Logs come from two sources, merged and sorted by `ts`: the app store's
// live buffer (`AppStore.logs`, fed by `LogUploader.logEvent` from every
// screen's actions — `MapScreen`'s start/stop/getPosition,
// `SettingsScreen`'s config changes and engine actions,
// `GeofenceFormScreen`'s add/remove) and the SDK's own persisted engine
// diagnostics, polled via `getLog()`.
//
// **`event == "app"` is this platform's `src` filter.** `LogsScreen.tsx`
// polls `getLog()` and filters down to `src === 'native'`, because
// `logUploader.ts` ALSO writes every JS-authored line into that same native
// queue tagged `src:"js"` — without the filter, a line already streaming
// live via `appStore` would double-count once the poll catches up to it.
// This SDK collapses `src` to `"native"` for every app-facing write (see
// `LogUploader.swift`'s header), but `Logger.write`
// (`BackgroundGeolocation+Logger.swift:80`) hard-codes every one of those
// writes to `event: "app"` — the real event name and payload travel inside
// `data` instead. The engine's OWN diagnostic lines are always
// dot-namespaced (`track.start`, `wake.rearm`, `motion.stop_countdown`,
// per `core/ios/Sources/BGGeoEngine.mm`) and never `"app"`. So
// `event == "app"` distinguishes exactly the same two sources RN's `src`
// does, just keyed on a different field — `nativeLogEntries(from:)` below
// drops them from the poll before the merge, mirroring RN's filter.
//
// **`LogLevel` collision**: `AppStore.LogLevel` (this module) and
// `BackgroundGeolocation.LogLevel` (the SDK) share a name once both are
// imported. Unqualified `LogLevel` resolves to this module's own type
// (same-module lookup wins, as Task 4/5 found for `SettingsScreen.swift`/
// `MapScreen.swift`) — used throughout this file for the UI-facing level.
// Worse than a same-name collision: `BackgroundGeolocation.LogLevel`
// (explicitly qualified) does NOT resolve to the SDK's top-level enum
// either — `import BackgroundGeolocation` also brings in the SDK facade
// *type* named `BackgroundGeolocation`, so `BackgroundGeolocation.LogLevel`
// is read as "nested member of that enum", which doesn't exist, and fails
// to compile (the exact trap `SettingsScreen.swift`'s `StateSection`
// comment documents for `BackgroundGeolocation.State`). Rather than fight
// that ambiguity, `logLine(from:)` below sidesteps it entirely: it switches
// on `LogEntry.level`'s raw `Int` (1=ERROR...5=VERBOSE) directly, which is
// also a more faithful port of `LogsScreen.tsx`'s own `LEVEL_NAMES`, itself
// a plain `Record<number, ...>` with no reference to the SDK's enum type.

import SwiftUI
import BackgroundGeolocation

// MARK: - Pure logic (tested — see the task report)

/// `LogsScreen.tsx`'s `LEVELS` chip row — a superset of `LogLevel` with an
/// `.all` option for the filter UI (log lines themselves are never `.all`).
public enum LogLevelFilter: String, CaseIterable {
    case all, verbose, debug, info, warn, error
}

/// Drops `LogUploader`-authored entries (`event == "app"`, see the file
/// header) from a raw `getLog()` poll before it's mapped/merged — this
/// platform's equivalent of `LogsScreen.tsx`'s `entries.filter(e => e.src
/// === 'native')`. Genuine engine diagnostics (`track.*`/`wake.*`/`motion.*`)
/// pass through unchanged.
public func nativeLogEntries(from entries: [LogEntry]) -> [LogEntry] {
    entries.filter { $0.event != "app" }
}

/// `LogsScreen.tsx`'s `LEVEL_NAMES` map: the native numeric Transistor scale
/// (`LogEntry.level`, 1=ERROR..5=VERBOSE) -> this app's `LogLevel` name,
/// falling back to `.info` for anything unrecognised (0/`off`, or an
/// out-of-range value) — same fallback RN's `?? 'info'` uses. See the file
/// header for why this switches on the raw `Int` rather than the SDK's
/// `LogLevel` enum.
public func logLine(from entry: LogEntry) -> LogLine {
    let level: LogLevel
    switch entry.level {
    case 1: level = .error
    case 2: level = .warn
    case 3: level = .info
    case 4: level = .debug
    case 5: level = .verbose
    default: level = .info
    }
    return LogLine(ts: entry.ts, level: level, event: entry.event, message: entry.message, data: entry.data)
}

/// `LogsScreen.tsx`'s `merged` + `filtered` memos: sort by `ts`
/// (ISO8601 strings compare lexicographically, same as RN's
/// `localeCompare`), then apply the level filter (`.all` = no filter).
public func mergeAndFilterLogs(appLogs: [LogLine], nativeLines: [LogLine], level: LogLevelFilter) -> [LogLine] {
    let merged = (appLogs + nativeLines).sorted { $0.ts < $1.ts }
    guard level != .all else { return merged }
    return merged.filter { $0.level.rawValue == level.rawValue }
}

/// `LogsScreen.tsx`'s `levelColor` — sourced from the palette so both themes
/// stay readable; `info` takes the accent (not the web console's green) so
/// level and event ink stay distinguishable, matching the RN comment.
public func logLevelColor(_ level: LogLevel, _ colors: ThemeColors) -> Color {
    switch level {
    case .verbose: return colors.placeholder
    case .debug: return colors.textDim
    case .info: return colors.accentText
    case .warn: return colors.warningText
    case .error: return colors.dangerText
    }
}

/// `line.ts.slice(11, 23)` — the `HH:mm:ss.SSS` slice of an ISO timestamp,
/// safely bounded for a shorter-than-expected string instead of trapping.
func logTimeSlice(_ ts: String) -> String {
    guard ts.count > 11 else { return ts }
    let start = ts.index(ts.startIndex, offsetBy: 11)
    let end = ts.index(start, offsetBy: min(12, ts.distance(from: start, to: ts.endIndex)))
    return String(ts[start..<end])
}

/// `JSON.stringify(line.data)` — falls back to `String(describing:)` for a
/// value `JSONSerialization` can't encode (e.g. non-JSON-safe types that
/// nonetheless reached `LogLine.data: Any?`).
func logDataDescription(_ data: Any?) -> String? {
    guard let data else { return nil }
    if JSONSerialization.isValidJSONObject(data),
       let json = try? JSONSerialization.data(withJSONObject: data),
       let string = String(data: json, encoding: .utf8) {
        return string
    }
    return String(describing: data)
}

// MARK: - Screen

public struct LogsScreen: View {
    @ObservedObject private var appStore: AppStore
    @ObservedObject private var themeStore: ThemeStore

    @Environment(\.colorScheme) private var systemColorScheme

    public init(appStore: AppStore, themeStore: ThemeStore) {
        self.appStore = appStore
        self.themeStore = themeStore
    }

    /// `LogsScreen.tsx`'s `NATIVE_POLL_MS`.
    private static let nativePollNanoseconds: UInt64 = 3_000_000_000
    /// `LogsScreen.tsx`'s `NATIVE_FETCH_LIMIT`.
    private static let nativeFetchLimit = 300

    @SwiftUI.State private var level: LogLevelFilter = .all
    @SwiftUI.State private var follow = true
    @SwiftUI.State private var nativeLines: [LogLine] = []

    private var scheme: Scheme {
        switch themeStore.mode {
        case .system: return systemColorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var colors: ThemeColors { palette[scheme] ?? lightColors }

    private var filtered: [LogLine] {
        mergeAndFilterLogs(appLogs: appStore.logs, nativeLines: nativeLines, level: level)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .background(colors.background)
        .task { await pollNativeLogs() }
    }

    // MARK: - native polling

    /// `LogsScreen.tsx`'s `useEffect` poll loop. `.task` cancels this
    /// automatically when the view disappears (the `Task.isCancelled` check
    /// plus a cancelling `Task.sleep` is the SwiftUI equivalent of RN's
    /// `clearInterval` cleanup) — not a test synchronisation device, this
    /// only ever runs in the live view.
    private func pollNativeLogs() async {
        while !Task.isCancelled {
            let entries = await BackgroundGeolocation.getLog(limit: Self.nativeFetchLimit)
            if Task.isCancelled { return }
            nativeLines = nativeLogEntries(from: entries).map(logLine(from:))
            try? await Task.sleep(nanoseconds: Self.nativePollNanoseconds)
        }
    }

    // MARK: - subviews

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(LogLevelFilter.allCases, id: \.self) { option in
                chip(option.rawValue, active: level == option) { level = option }
            }
            Spacer()
            chip("follow", active: follow) { follow.toggle() }
            chip("clear", active: false) { appStore.clearLogs() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 5)
        }
        .foregroundColor(active ? colors.onAccent : colors.textDim)
        .background(active ? colors.accent : colors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text("waiting for events…")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(colors.placeholder)
                            .padding(8)
                    } else {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { index, line in
                            LogRow(line: line, colors: colors).id(index)
                        }
                    }
                }
                .padding(8)
            }
            .background(colors.field)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .onChange(of: filtered.count) { _ in
                guard follow, let last = filtered.indices.last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
        .accessibilityIdentifier("logs.list")
    }
}

private struct LogRow: View {
    let line: LogLine
    let colors: ThemeColors

    var body: some View {
        var text = Text(logTimeSlice(line.ts) + " ").foregroundColor(colors.textDim)
        text = text + Text("[\(line.level.rawValue.uppercased())] ").foregroundColor(logLevelColor(line.level, colors))
        text = text + Text(line.event).foregroundColor(colors.successText)
        if let message = line.message {
            text = text + Text(" " + message).foregroundColor(colors.text2)
        }
        if let dataDescription = logDataDescription(line.data) {
            text = text + Text(" " + dataDescription).foregroundColor(colors.textDim)
        }
        return text
            .font(.system(size: 12, design: .monospaced))
            .lineSpacing(3)
    }
}
