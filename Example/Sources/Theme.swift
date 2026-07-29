// Light/dark palette for the example app chrome (panels, tab bar, sheet).
//
// The values are the web console's design tokens (`web/src/index.css`)
// converted from oklch to hex — same palette on all clients. Ported from
// `react-native/example/src/theme.ts` (`flutter/example/lib/src/theme.dart`
// is the same port for Flutter). Two roles per status color:
// `success`/`warning`/`danger` are FILLS, meant to carry a contrasting
// foreground; `*Text` are the readable inks for type on
// `background`/`surface`. In dark they coincide; in light the fill stays
// bright and the ink is the same hue darkened to clear 4.5:1.
//
// Map-overlay colors (geofence actions, track polyline, breadcrumb dots) are
// NOT theme-scoped — the web console keeps them fixed too.

import SwiftUI

public enum Scheme: String {
    case light, dark
}

/// What the user picked; `.system` follows the OS (same contract as the web
/// console and the other two clients).
public enum ThemeMode: String, CaseIterable {
    case system, light, dark
}

public struct ThemeColors {
    /// Screen background.
    public let background: Color
    /// Cards and raised chrome.
    public let surface: Color
    /// Buttons, toggles, chips.
    public let surfaceRaised: Color
    /// Text inputs and the log/terminal viewport.
    public let field: Color
    public let border: Color
    public let separator: Color
    /// Floating panels over the map — translucent over `surface`.
    public let panel: Color
    /// Bottom-sheet drag handle.
    public let handle: Color

    public let text: Color
    /// Secondary type (labels, values).
    public let text2: Color
    /// Dimmed type (metadata, table gutters).
    public let textDim: Color
    public let placeholder: Color

    public let accent: Color
    /// Accent as type — darkened in light so it clears 4.5:1.
    public let accentText: Color
    /// Tinted accent background (badges).
    public let accentSoft: Color
    /// Type on an `accent`/`danger` fill.
    public let onAccent: Color

    public let success: Color
    public let warning: Color
    public let danger: Color
    public let successText: Color
    public let warningText: Color
    public let dangerText: Color
    /// Row tint for geofence events.
    public let warningSoft: Color

    public let tabBar: Color
    public let tabBarBorder: Color
}

private func rgb(_ r: Double, _ g: Double, _ b: Double, _ opacity: Double = 1) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255, opacity: opacity)
}

public let lightColors = ThemeColors(
    background: rgb(245, 245, 246),
    surface: rgb(255, 255, 255),
    surfaceRaised: rgb(239, 239, 240),
    field: rgb(255, 255, 255),
    border: rgb(221, 222, 223),
    separator: rgb(228, 228, 229),
    panel: rgb(255, 255, 255, 0.94),
    handle: rgb(207, 208, 210),
    text: rgb(24, 24, 25),
    text2: rgb(82, 88, 100),
    textDim: rgb(113, 114, 115),
    placeholder: rgb(129, 134, 143),
    accent: rgb(58, 111, 240),
    accentText: rgb(50, 101, 229),
    accentSoft: rgb(58, 111, 240, 0.12),
    onAccent: rgb(255, 255, 255),
    success: rgb(0, 201, 103),
    warning: rgb(244, 166, 32),
    danger: rgb(255, 56, 54),
    successText: rgb(2, 136, 69),
    warningText: rgb(161, 107, 8),
    dangerText: rgb(232, 20, 32),
    warningSoft: rgb(244, 166, 32, 0.14),
    tabBar: rgb(255, 255, 255),
    tabBarBorder: rgb(221, 222, 223)
)

public let darkColors = ThemeColors(
    background: rgb(6, 8, 13),
    surface: rgb(24, 24, 25),
    surfaceRaised: rgb(35, 35, 36),
    field: rgb(0, 0, 0),
    border: rgb(41, 41, 41),
    separator: rgb(33, 34, 34),
    panel: rgb(24, 24, 25, 0.94),
    handle: rgb(63, 64, 69),
    text: rgb(252, 252, 253),
    text2: rgb(156, 165, 177),
    textDim: rgb(159, 160, 161),
    placeholder: rgb(109, 117, 128),
    accent: rgb(58, 111, 240),
    accentText: rgb(104, 149, 244),
    accentSoft: rgb(58, 111, 240, 0.28),
    onAccent: rgb(255, 255, 255),
    success: rgb(0, 201, 103),
    warning: rgb(246, 184, 79),
    danger: rgb(219, 59, 58),
    successText: rgb(0, 201, 103),
    warningText: rgb(246, 184, 79),
    dangerText: rgb(219, 59, 58),
    warningSoft: rgb(246, 184, 79, 0.10),
    tabBar: rgb(15, 15, 20),
    tabBarBorder: rgb(41, 41, 41)
)

public let palette: [Scheme: ThemeColors] = [.light: lightColors, .dark: darkColors]

public let mono = "Menlo"

// --- theme mode store -------------------------------------------------------

/// Persisted mode choice, mirroring `themeStore` in `theme.ts` /
/// `ThemeController` in `theme.dart`. `UserDefaults` reads are synchronous,
/// so unlike the RN/Flutter stores (`AsyncStorage`/`SharedPreferences`, both
/// async) this hydrates in `init` rather than needing a separate
/// `hydrate()` step.
@MainActor
public final class ThemeStore: ObservableObject {
    private static let key = "bgeo:themeMode"

    @Published public private(set) var mode: ThemeMode

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.key), let restored = ThemeMode(rawValue: raw) {
            mode = restored
        } else {
            mode = .system
        }
    }

    public func setMode(_ next: ThemeMode) {
        mode = next
        userDefaults.set(next.rawValue, forKey: Self.key)
    }
}
