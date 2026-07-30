// Modal form for geofence CRUD. New fence: long-press on the map (Task 5's
// `onGeofenceRequest` seam, `identifier: nil`). Edit/delete: tap an existing
// fence's pin (`identifier` set). Every change goes to the SDK, then the
// snapshot is mirrored to the console via `Geofences`.
//
// Swift port of `react-native/example/src/screens/GeofenceFormScreen.tsx`;
// `flutter/example/lib/src/screens/geofence_form_screen.dart` is the same
// port for Flutter and agrees with every decision made here.
//
// **`Int(...)` trap**: `radius`/`loiteringDelay` are free-text numeric
// fields. Both underlying `Geofence` fields are `Double`, so parsing
// (`Double(text)`) can't trap the way an `Int(_:)` conversion would — but the
// display/log paths still route through `ConfigCoerce.displayString`/
// `numberFromText` (the same `Int(exactly:)`-guarded helpers `SettingsScreen`
// uses) rather than a raw `Int(...)`, so a huge pasted magnitude can't trap
// there either.

import SwiftUI
import BackgroundGeolocation

public struct GeofenceFormScreen: View {
    @ObservedObject private var appStore: AppStore
    @ObservedObject private var themeStore: ThemeStore
    private let geofences: Geofences
    private let request: GeofenceRequest
    private let existing: Geofence?

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var identifier: String
    @SwiftUI.State private var radiusText: String
    @SwiftUI.State private var notifyOnEntry: Bool
    @SwiftUI.State private var notifyOnExit: Bool
    @SwiftUI.State private var notifyOnDwell: Bool
    @SwiftUI.State private var loiteringDelayText: String
    @SwiftUI.State private var busy = false
    @SwiftUI.State private var error: String?

    public init(appStore: AppStore, themeStore: ThemeStore, geofences: Geofences, request: GeofenceRequest) {
        self.appStore = appStore
        self.themeStore = themeStore
        self.geofences = geofences
        self.request = request

        let existing = request.identifier.flatMap { id in appStore.geofences.first { $0.identifier == id } }
        self.existing = existing
        _identifier = SwiftUI.State(initialValue: existing?.identifier ?? "")
        _radiusText = SwiftUI.State(initialValue: ConfigCoerce.displayString(for: existing?.radius ?? 200))
        _notifyOnEntry = SwiftUI.State(initialValue: existing?.notifyOnEntry ?? true)
        _notifyOnExit = SwiftUI.State(initialValue: existing?.notifyOnExit ?? true)
        _notifyOnDwell = SwiftUI.State(initialValue: existing?.notifyOnDwell ?? false)
        _loiteringDelayText = SwiftUI.State(initialValue: existing?.loiteringDelay.map { ConfigCoerce.displayString(for: $0) } ?? "")
    }

    private var scheme: Scheme {
        switch themeStore.mode {
        case .system: return systemColorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var colors: ThemeColors { palette[scheme] ?? lightColors }

    private var latitude: Double { existing?.latitude ?? request.latitude }
    private var longitude: Double { existing?.longitude ?? request.longitude }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(existing != nil ? "Edit geofence" : "New geofence")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colors.text)

                Text(String(format: "%.6f, %.6f", latitude, longitude))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.textDim)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                label("Identifier")
                TextField("home", text: $identifier)
                    .disabled(existing != nil)
                    .opacity(existing != nil ? 0.5 : 1)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .fieldStyle(colors: colors)

                label("Radius (m)")
                TextField("", text: $radiusText)
                    .keyboardType(.numbersAndPunctuation)
                    .fieldStyle(colors: colors)

                toggleRow("Notify on ENTER", isOn: $notifyOnEntry)
                toggleRow("Notify on EXIT", isOn: $notifyOnExit)
                toggleRow("Notify on DWELL", isOn: $notifyOnDwell)

                if notifyOnDwell {
                    label("Loitering delay (ms)")
                    TextField("30000", text: $loiteringDelayText)
                        .keyboardType(.numbersAndPunctuation)
                        .fieldStyle(colors: colors)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(colors.dangerText)
                        .padding(.top, 12)
                }

                Button(busy ? "Saving…" : "Save") { Task { await onSave() } }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                    .filledButtonStyle(background: colors.accent, foreground: colors.onAccent)
                    .padding(.top, 16)

                if existing != nil {
                    Button("Delete") { Task { await onDelete() } }
                        .disabled(busy)
                        .opacity(busy ? 0.5 : 1)
                        .filledButtonStyle(background: colors.danger, foreground: colors.onAccent)
                        .padding(.top, 16)
                }
            }
            .padding(16)
        }
        .background(colors.background)
    }

    // MARK: - actions

    private func onSave() async {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let radius = parseDouble(radiusText), radius.isFinite, radius > 0, !trimmedIdentifier.isEmpty else {
            error = "identifier and a positive radius are required"
            return
        }
        busy = true
        error = nil

        let trimmedLoitering = loiteringDelayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loiteringDelay = trimmedLoitering.isEmpty ? nil : parseDouble(trimmedLoitering)

        let geofence = Geofence(
            identifier: trimmedIdentifier,
            radius: radius,
            latitude: latitude,
            longitude: longitude,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit,
            notifyOnDwell: notifyOnDwell,
            loiteringDelay: loiteringDelay
        )
        do {
            try await geofences.add(geofence)
            appStore.appendLog(LogLine(
                ts: isoTimestamp(),
                level: .info,
                event: "addGeofence",
                message: "\(trimmedIdentifier) r=\(ConfigCoerce.displayString(for: radius))m"
            ))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func onDelete() async {
        guard let existing else { return }
        busy = true
        do {
            try await geofences.remove(identifier: existing.identifier)
            appStore.appendLog(LogLine(ts: isoTimestamp(), level: .info, event: "removeGeofence", message: existing.identifier))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func parseDouble(_ text: String) -> Double? {
        ConfigCoerce.numberFromText(text, matching: .double(0)) as? Double
    }

    // MARK: - subviews

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(colors.textDim)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundColor(colors.text2)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .padding(.top, 14)
    }
}

private extension View {
    func fieldStyle(colors: ThemeColors) -> some View {
        self
            .padding(12)
            .foregroundColor(colors.text2)
            .background(colors.field)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func filledButtonStyle(background: Color, foreground: Color) -> some View {
        self
            .font(.system(size: 15, weight: .semibold))
            .padding(14)
            .frame(maxWidth: .infinity)
            .foregroundColor(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}
