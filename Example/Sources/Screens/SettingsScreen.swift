// Settings — device link (registration code), every working SDK config key
// (applied immediately via ConfigStore, persisted as overrides), engine
// state/diagnostic actions and the upload-queue tools.
//
// Swift port of `react-native/example/src/screens/SettingsScreen.tsx`
// (`flutter/example/lib/src/screens/settings_screen.dart` is the same port
// for Flutter). RN's actual Settings screen: `destroyLocations`, `getCount`,
// `getLog`, `getState`, `resetOdometer`, `sync`, `uploadLog`, link/unlink —
// `requestPermission`/`getCurrentPosition`/`start`/`stop` live on RN's Map
// screen instead (Task 5 owns those, for parity with exactly one button per
// call across the app). Coordinator-confirmed ruling on the brief's original
// (misdescribed) action list: `requestTemporaryFullAccuracy`/`changePace`/
// `destroyLog` are kept here even though neither RN nor Flutter wires them
// into any example screen — they have no RN counterpart, so keeping them
// cannot create a parity conflict the way duplicating requestPermission/
// getCurrentPosition would have.
//
// Wiring note (Task 8's job, not this one — see that task's brief): this
// view takes its `AppStore`/`ConfigStore`/`ThemeStore`/`DeviceLink`
// dependencies through its initializer, the same explicit-injection pattern
// `DeviceLink` itself uses; nothing here assumes an `@EnvironmentObject`.
// `ContentView`/`BGeoExampleApp` don't construct or present this screen yet.

import SwiftUI
import BackgroundGeolocation

private let stateFields = [
    "enabled", "trackingActive", "isMoving", "odometer", "geofenceCount",
    "authorization", "lastRawFixAge", "lastAcceptedFixAge",
    "watchdogRecoveryCount", "sessionEngineActive", "serviceSessionActive",
]

/// The purpose key requested at `requestTemporaryFullAccuracy` — must match
/// `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist (added in
/// Task 1, per that task's report).
private let temporaryFullAccuracyPurpose = "DeliverFullAccuracy"

public struct SettingsScreen: View {
    @ObservedObject private var appStore: AppStore
    @ObservedObject private var configStore: ConfigStore
    @ObservedObject private var themeStore: ThemeStore
    private let deviceLink: DeviceLink

    @Environment(\.colorScheme) private var systemColorScheme

    public init(appStore: AppStore, configStore: ConfigStore, themeStore: ThemeStore, deviceLink: DeviceLink) {
        self.appStore = appStore
        self.configStore = configStore
        self.themeStore = themeStore
        self.deviceLink = deviceLink
    }

    private var scheme: Scheme {
        switch themeStore.mode {
        case .system: return systemColorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var colors: ThemeColors { palette[scheme] ?? lightColors }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LinkSection(appStore: appStore, deviceLink: deviceLink, colors: colors)
                AppearanceSection(themeStore: themeStore, colors: colors, schemeLabel: scheme.rawValue)

                ForEach(configSections, id: \.title) { section in
                    let fields = section.fields.filter { $0.platform == nil || $0.platform == .ios }
                    if !fields.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(colors.text)
                                .padding(.bottom, 6)
                            ForEach(fields, id: \.key) { field in
                                ConfigFieldRow(
                                    field: field,
                                    value: currentValue(for: field),
                                    overridden: configStore.overrides[field.key] != nil,
                                    colors: colors,
                                    onChange: { setValue(field, $0) }
                                )
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }

                Button("Reset config to defaults") {
                    Task {
                        await configStore.reset()
                        logEvent("setConfig", "reset to defaults", level: .info)
                    }
                }
                .buttonStyle(FilledButtonStyle(kind: .neutral, colors: colors))
                .padding(.bottom, 24)

                StateSection(appStore: appStore, colors: colors, log: logEvent)
            }
            .padding(16)
        }
        .background(colors.background)
    }

    private func currentValue(for field: ConfigField) -> Any {
        configStore.overrides[field.key] ?? field.defaultValue.any
    }

    private func setValue(_ field: ConfigField, _ raw: Any) {
        Task {
            await configStore.setOverride(field.key, raw)
            logEvent("setConfig", "\(field.key)=\(raw)", level: .info)
        }
    }

    private func logEvent(_ event: String, _ message: String, level: LogLevel) {
        appStore.appendLog(LogLine(ts: isoTimestamp(), level: level, event: event, message: message))
    }
}

// MARK: - appearance

private struct AppearanceSection: View {
    @ObservedObject var themeStore: ThemeStore
    let colors: ThemeColors
    let schemeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance").font(.system(size: 16, weight: .bold)).foregroundColor(colors.text)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Theme").font(.system(size: 13)).foregroundColor(colors.text2)
                    Text("same palette as the web console · now: \(schemeLabel)")
                        .font(.system(size: 11)).foregroundColor(colors.placeholder)
                }
                Spacer()
                EnumButtonsRow(
                    options: ThemeMode.allCases.map { (label: label(for: $0), value: $0) },
                    isSelected: { $0 == themeStore.mode },
                    colors: colors,
                    onSelect: { themeStore.setMode($0) }
                )
            }
        }
        .padding(.bottom, 24)
    }

    private func label(for mode: ThemeMode) -> String {
        switch mode {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - device link

private struct LinkSection: View {
    @ObservedObject var appStore: AppStore
    let deviceLink: DeviceLink
    let colors: ThemeColors

    @SwiftUI.State private var serverUrl: String
    @SwiftUI.State private var code = ""
    @SwiftUI.State private var busy = false
    @SwiftUI.State private var error: String?

    init(appStore: AppStore, deviceLink: DeviceLink, colors: ThemeColors) {
        self.appStore = appStore
        self.deviceLink = deviceLink
        self.colors = colors
        _serverUrl = State(initialValue: appStore.link.serverUrl)
    }

    private var codeReady: Bool {
        code.replacingOccurrences(of: "-", with: "").count >= 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug console").font(.system(size: 16, weight: .bold)).foregroundColor(colors.text)
            Text("Create a registration code in the BGeo web console (Dashboard → Registration codes) and enter it here. Locations and SDK events then stream live to your console.")
                .font(.system(size: 13)).foregroundColor(colors.textDim)

            Text("Server").font(.system(size: 12)).foregroundColor(colors.textDim)
            TextField("", text: $serverUrl)
                .disabled(appStore.link.linked)
                .textFieldFieldStyle(colors: colors)

            if !appStore.link.linked {
                Text("Registration code").font(.system(size: 12)).foregroundColor(colors.textDim)
                TextField("XXXX-XXXX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .textFieldFieldStyle(colors: colors)

                Button(busy ? "Linking…" : "Link device") { link() }
                    .disabled(busy || !codeReady)
                    .opacity(busy || !codeReady ? 0.5 : 1)
                    .buttonStyle(FilledButtonStyle(kind: .primary, colors: colors))
            } else {
                Text("🟢 Linked — device \(String((appStore.link.deviceId ?? "").prefix(8)))")
                    .font(.system(size: 14)).foregroundColor(colors.successText)
                Button("Unlink") { unlink() }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                    .buttonStyle(FilledButtonStyle(kind: .danger, colors: colors))
            }

            if let error {
                Text(error).font(.system(size: 13)).foregroundColor(colors.dangerText)
            }
        }
        .padding(.bottom, 24)
    }

    private func link() {
        busy = true
        error = nil
        Task {
            do {
                let trimmed = serverUrl.trimmingTrailingSlashes()
                let result = try await deviceLink.link(serverUrl: trimmed, code: code)
                appStore.appendLog(LogLine(ts: isoTimestamp(), level: .info, event: "link", message: "linked to console as \(result.deviceId)"))
                code = ""
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func unlink() {
        busy = true
        Task {
            await deviceLink.unlink()
            appStore.appendLog(LogLine(ts: isoTimestamp(), level: .info, event: "link", message: "unlinked from console"))
            busy = false
        }
    }
}

// MARK: - config field row

private struct ConfigFieldRow: View {
    let field: ConfigField
    let value: Any
    let overridden: Bool
    let colors: ThemeColors
    let onChange: (Any) -> Void

    private var displayString: String {
        switch value {
        case let v as Bool: return v ? "true" : "false"
        case let v as String: return v
        case let v as Int: return String(v)
        case let v as Double: return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
        case let v as NSNumber: return v.stringValue
        default: return ""
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.unit.map { "\(field.label) (\($0))" } ?? field.label)
                    .font(.system(size: 13))
                    .foregroundColor(overridden ? colors.accentText : colors.text2)
                if let hint = field.hint {
                    Text(hint).font(.system(size: 11)).foregroundColor(colors.placeholder)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var control: some View {
        switch field.type {
        case .bool:
            Toggle("", isOn: Binding(
                get: { ConfigCoerce.bool(value) ?? false },
                set: { onChange($0) }
            ))
            .labelsHidden()
        case .number:
            CommitField(value: displayString, keyboardType: .numbersAndPunctuation, colors: colors) { text in
                guard let value = ConfigCoerce.numberFromText(text, matching: field.defaultValue) else { return }
                onChange(value)
            }
        case .string:
            CommitField(value: displayString, keyboardType: .default, colors: colors) { text in onChange(text) }
        case .enumeration:
            EnumButtonsRow(
                options: (field.options ?? []).map { (label: $0.label, value: $0.value) },
                isSelected: { matches($0, value) },
                colors: colors,
                onSelect: { onChange($0.any) }
            )
        }
    }

    private func matches(_ optionValue: ConfigValue, _ current: Any) -> Bool {
        switch optionValue {
        case .string(let v): return ConfigCoerce.string(current) == v
        case .int(let v): return ConfigCoerce.int(current) == v
        case .double(let v): return ConfigCoerce.double(current) == v
        case .bool(let v): return ConfigCoerce.bool(current) == v
        }
    }
}

/// Commits on blur / submit — never per keystroke, since a change is a round
/// trip through `ConfigStore` to the live engine. Mirrors RN's `NumberInput`/
/// `StringInput` and Flutter's `_TextValueInput`.
private struct CommitField: View {
    let value: String
    var keyboardType: UIKeyboardType = .default
    let colors: ThemeColors
    let onCommit: (String) -> Void

    @SwiftUI.State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .keyboardType(keyboardType)
            .multilineTextAlignment(.trailing)
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
            .focused($focused)
            .frame(minWidth: 90)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(colors.field)
            .foregroundColor(colors.text2)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? colors.accent : colors.border))
            .onAppear { draft = value }
            .onChange(of: value) { newValue in if !focused { draft = newValue } }
            .onChange(of: focused) { isFocused in if !isFocused { commit() } }
            .onSubmit { commit() }
    }

    private func commit() {
        guard draft != value else { return }
        onCommit(draft)
    }
}

/// Shared row of pill buttons for both config enum fields and the appearance
/// theme picker.
private struct EnumButtonsRow<Value>: View {
    let options: [(label: String, value: Value)]
    let isSelected: (Value) -> Bool
    let colors: ThemeColors
    let onSelect: (Value) -> Void

    // A plain `HStack`, not a wrapping layout: iOS 15.5 predates SwiftUI's
    // `Layout` protocol (needs iOS 16), and the option counts here (2-6)
    // never overflow a settings-row width in practice, so a real wrap
    // implementation would be unused complexity.
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = isSelected(option.value)
                Button(option.label) { onSelect(option.value) }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(selected ? colors.accent : colors.surfaceRaised)
                    .foregroundColor(selected ? colors.onAccent : colors.textDim)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - engine state + actions

private struct ActionOutcome {
    let message: String
    let isError: Bool
}

private struct StateSection: View {
    @ObservedObject var appStore: AppStore
    let colors: ThemeColors
    let log: (String, String, LogLevel) -> Void

    // Stored as the raw dictionary, not `BackgroundGeolocation.State`: that
    // type name is unresolvably ambiguous in this file (`import
    // BackgroundGeolocation` also brings in the SDK facade enum named
    // `BackgroundGeolocation`, and `BackgroundGeolocation.State` resolves as
    // "nested member of that enum" — which doesn't exist — rather than
    // falling back to the module's top-level `State` struct). `.raw` is
    // exactly `State.raw`, the same escape hatch the SDK itself documents.
    @SwiftUI.State private var engineState: [String: Any]?
    @SwiftUI.State private var queueCount: Int?
    @SwiftUI.State private var logCount: Int?
    @SwiftUI.State private var isMovingDraft = false
    @SwiftUI.State private var results: [String: ActionOutcome] = [:]
    @SwiftUI.State private var busyActions: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Engine state").font(.system(size: 16, weight: .bold)).foregroundColor(colors.text)
                Spacer()
                Button("Refresh") { Task { await refresh() } }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(colors.surfaceRaised)
                    .foregroundColor(colors.accentText)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let engineState {
                ForEach(stateFields.filter { engineState[$0] != nil }, id: \.self) { key in
                    stateRow(key, describe(engineState[key]))
                }
            }
            stateRow("upload queue", "\(queueCount.map(String.init) ?? "—") records")
            stateRow("log history", logCountLabel)

            // `requestPermission`/`getCurrentPosition` deliberately NOT here —
            // they belong on Task 5's Map screen (see file header). Kept:
            // `requestTemporaryFullAccuracy`/`changePace`/`destroyLog`, which
            // have no RN/Flutter screen home at all.
            actionButton("Request full accuracy", key: "requestTemporaryFullAccuracy") {
                let accuracy = await BackgroundGeolocation.requestTemporaryFullAccuracy(purpose: temporaryFullAccuracyPurpose)
                return accuracy == .full ? "full" : "reduced"
            }

            HStack {
                Toggle("Moving", isOn: $isMovingDraft).labelsHidden()
                Text("Moving (for Change pace)").font(.system(size: 13)).foregroundColor(colors.text2)
                Spacer()
            }
            actionButton("Change pace", key: "changePace") {
                try await BackgroundGeolocation.changePace(isMovingDraft)
                return "isMoving=\(isMovingDraft)"
            }

            HStack(spacing: 12) {
                actionButton("Sync now", key: "sync", kind: .primary, flex: true) {
                    let records = try await BackgroundGeolocation.sync()
                    return "\(records.count) records"
                }
                actionButton("Destroy queue", key: "destroyLocations", kind: .danger, flex: true) {
                    let n = await BackgroundGeolocation.destroyLocations()
                    return "\(n) records"
                }
            }

            actionButton("Upload logs", key: "uploadLog") {
                let n = await BackgroundGeolocation.uploadLog()
                return "\(n) rows handed to the flusher"
            }
            actionButton("Destroy log", key: "destroyLog", kind: .danger) {
                let n = await BackgroundGeolocation.destroyLog()
                return "\(n) rows"
            }
            actionButton("Reset odometer", key: "resetOdometer") {
                _ = try await BackgroundGeolocation.resetOdometer()
                return "odometer=0"
            }

            HStack(spacing: 4) {
                Text("Track buffer: \(appStore.points.count) pts ·").font(.system(size: 13)).foregroundColor(colors.textDim)
                Button("clear track") { appStore.clearTrack() }
                    .font(.system(size: 13)).foregroundColor(colors.dangerText)
            }
        }
        .task { await refresh() }
    }

    private var logCountLabel: String {
        guard let logCount else { return "— rows" }
        return logCount >= 5000 ? "5000+ rows" : "\(logCount) rows"
    }

    private func stateRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 12, design: .monospaced)).foregroundColor(colors.textDim)
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(colors.text2)
        }
    }

    private func describe(_ value: Any?) -> String {
        switch value {
        case let v as Bool: return v ? "true" : "false"
        case let v as NSNumber: return v.stringValue
        case let v as String: return v
        case .none: return "—"
        default: return String(describing: value!)
        }
    }

    private func refresh() async {
        async let state = BackgroundGeolocation.getState()
        async let count = BackgroundGeolocation.getCount()
        async let log = BackgroundGeolocation.getLog(limit: 5000)
        engineState = await state.raw
        queueCount = await count
        logCount = await log.count
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        key: String,
        kind: FilledButtonStyle.Kind = .primary,
        flex: Bool = false,
        action: @escaping () async throws -> String
    ) -> some View {
        let busy = busyActions.contains(key)
        VStack(alignment: .leading, spacing: 4) {
            Button(busy ? "\(title)…" : title) { run(key: key, action: action) }
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
                .buttonStyle(FilledButtonStyle(kind: kind, colors: colors))
                .frame(maxWidth: flex ? .infinity : nil)
            if let outcome = results[key] {
                Text(outcome.message)
                    .font(.system(size: 12))
                    .foregroundColor(outcome.isError ? colors.dangerText : colors.textDim)
            }
        }
        .frame(maxWidth: flex ? .infinity : nil)
    }

    private func run(key: String, action: @escaping () async throws -> String) {
        guard !busyActions.contains(key) else { return }
        busyActions.insert(key)
        Task {
            do {
                let message = try await action()
                results[key] = ActionOutcome(message: message, isError: false)
                log(key, message, .info)
            } catch {
                let message = error.localizedDescription
                results[key] = ActionOutcome(message: message, isError: true)
                log(key, message, .error)
            }
            busyActions.remove(key)
            await refresh()
        }
    }
}

// MARK: - shared button style

private struct FilledButtonStyle: ButtonStyle {
    enum Kind { case primary, danger, neutral }
    let kind: Kind
    let colors: ThemeColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(background)
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(kind == .neutral ? colors.border : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var background: Color {
        switch kind {
        case .primary: return colors.accent
        case .danger: return colors.danger
        case .neutral: return colors.surfaceRaised
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return colors.onAccent
        case .neutral: return colors.text
        }
    }
}

// MARK: - small helpers

private extension View {
    func textFieldFieldStyle(colors: ThemeColors) -> some View {
        self
            .padding(12)
            .background(colors.field)
            .foregroundColor(colors.text2)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border))
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var result = self
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

private func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}
