// Declarative schema of the SDK's working Config keys — single source for the
// Settings screen UI and for reset-to-defaults.
//
// Swift port of `react-native/example/src/configSchema.ts`
// (`flutter/example/lib/src/config_schema.dart` is the same port for
// Flutter). Ported field-for-field, WITH ONE CORRECTION per this task's
// brief: `stationaryDesiredAccuracy` is the STRING enum HIGH/BALANCED/LOW
// (matching `Config.stationaryDesiredAccuracy: String?`) — RN's original
// offered the numeric `desiredAccuracy` scale for this field, which the
// engine silently dropped (`as? String` failure); that bug was fixed in
// phase 0 and this schema takes the corrected version directly.
//
// Documented no-op keys (`foregroundService`, `backgroundPermissionRationale`
// — both marked `@unsupported` on `Config` itself) are excluded, same as the
// RN/Flutter schemas.
//
// SCHEMA-VS-CONFIG DIFF (the app-side twin of `ConfigDriftTests`, run by hand
// against `Config`'s 57 properties per this task's brief, and asserted by
// `ConfigStoreTests.testEveryConfigPropertyIsInTheSchemaOrDocumentedAsExcluded`
// in both directions): RN/Flutter's own schema covers 40 of the 57 `Config`
// properties (39 scalar keys + `notification`, which fans out to 7 UI
// fields). This port ADDS 8 more properties RN/Flutter leave unschema'd,
// rather than silently carrying the same gap forward (see each field's
// "ADDED" comment below for its source default): `locationAuthorizationRequest`,
// `disableLocationAuthorizationAlert` (new "Permissions" section),
// `stationaryLocationUpdateInterval`, `triggerActivities`,
// `activityRecognitionInterval` (Motion/Activity — Android-only ones tagged
// `.android`), `logMaxDays` (Diagnostics/Engine), `httpRootProperty`,
// `method` (HTTP/Sync). That leaves 9 `Config` properties with no schema
// entry, all deliberately excluded — not oversights:
//   - `foregroundService`, `backgroundPermissionRationale`: documented no-ops.
//   - `locationAuthorizationAlert`, `headers`, `params`, `extras`: nested
//     `[String: Any]`/`[String: String]` dictionaries — `ConfigField.type` is
//     bool/number/enumeration/string only; a raw dictionary editor is a
//     different kind of UI this schema's type system doesn't (and, per
//     RN/Flutter precedent, isn't meant to) express.
//   - `url`, `logUrl`, `authorization`: the upload endpoint's identity and
//     credentials. These are exclusively owned by `DeviceLink` (the Settings
//     screen's "Debug console" link section) — editing them independently
//     here would desync the device link (e.g. changing `url` without
//     rotating `authorization` breaks the linked server relationship).
//     RN/Flutter draw the same line for the same reason. `method` does NOT
//     belong on this list — `DeviceLink` never sets `Config.method` (its
//     `deviceFetch`'s `method` parameter is a distinct, local thing) — so
//     `method` is schema'd normally below, not excluded.

import Foundation
import BackgroundGeolocation

// MARK: - Schema types

public enum ConfigFieldType {
    case bool
    case number
    /// Named to avoid escaping the `enum` keyword; matches
    /// `flutter/example/lib/src/config_schema.dart`'s `FieldType.enumeration`.
    case enumeration
    case string
}

public enum ConfigPlatform: String {
    case ios, android
}

/// A schema value: mirrors what `ConfigField.defaultValue`/`ConfigFieldOption.value`
/// can hold (`boolean | number | string` in the TS/Dart originals), typed so
/// `ConfigStore` can route each field straight onto the right `Config` property.
public enum ConfigValue: Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    /// Unwrapped for `Config` property assignment / display.
    public var any: Any {
        switch self {
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        }
    }
}

public struct ConfigFieldOption {
    public let label: String
    public let value: ConfigValue

    public init(_ label: String, _ value: ConfigValue) {
        self.label = label
        self.value = value
    }
}

public struct ConfigField {
    public let key: String
    public let label: String
    public let type: ConfigFieldType
    /// enum choices
    public let options: [ConfigFieldOption]?
    /// The effective engine/app default shown when no override is set.
    public let defaultValue: ConfigValue
    public let unit: String?
    /// nil = works on both platforms.
    public let platform: ConfigPlatform?
    public let hint: String?

    public init(
        key: String,
        label: String,
        type: ConfigFieldType,
        options: [ConfigFieldOption]? = nil,
        defaultValue: ConfigValue,
        unit: String? = nil,
        platform: ConfigPlatform? = nil,
        hint: String? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.options = options
        self.defaultValue = defaultValue
        self.unit = unit
        self.platform = platform
        self.hint = hint
    }
}

public struct ConfigSection {
    public let title: String
    public let fields: [ConfigField]

    public init(_ title: String, _ fields: [ConfigField]) {
        self.title = title
        self.fields = fields
    }
}

// MARK: - Coercion

/// Robustly reads an `Any` that may be a native Swift literal (values coming
/// straight from a SwiftUI control) or an `NSNumber`/`NSString` (values
/// round-tripped through `JSONSerialization`/`UserDefaults`) — the same
/// dual-shape hazard `DictionaryDecoding.swift` documents for engine
/// payloads. Shared by `ConfigStore` (building `Config` patches) and
/// `SettingsScreen` (displaying the current value of a field).
public enum ConfigCoerce {
    public static func bool(_ value: Any) -> Bool? {
        if let v = value as? Bool { return v }
        if let v = value as? NSNumber { return v.boolValue }
        return nil
    }

    public static func int(_ value: Any) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? NSNumber { return v.intValue }
        if let v = value as? Double { return Int(v) }
        return nil
    }

    public static func double(_ value: Any) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? NSNumber { return v.doubleValue }
        if let v = value as? Int { return Double(v) }
        return nil
    }

    public static func string(_ value: Any) -> String? {
        value as? String
    }

    /// Parses a settings-field text draft into the numeric type matching
    /// `kindOf`'s case (`Int` or `Double`). Returns nil — never traps — for
    /// unparsable text OR a value `Int(exactly:)` can't represent (e.g. a
    /// 22-digit string typed into "Max batch size": `Double(text)` parses
    /// fine to `~1.1e21`, but `Int(1.1e21)` crashes the process). The digits
    /// keyboard makes an arbitrarily long numeric string trivially reachable
    /// from a normal settings edit, so this must not use the trapping
    /// initializer.
    public static func numberFromText(_ text: String, matching kindOf: ConfigValue) -> Any? {
        guard let parsed = Double(text) else { return nil }
        if case .double = kindOf {
            return parsed
        }
        return Int(exactly: parsed.rounded())
    }
}

// MARK: - Schema

private let accuracyOptions: [ConfigFieldOption] = [
    ConfigFieldOption("NAV", .int(DesiredAccuracy.navigation.rawValue)),
    ConfigFieldOption("HIGH", .int(DesiredAccuracy.high.rawValue)),
    ConfigFieldOption("MED", .int(DesiredAccuracy.medium.rawValue)),
    ConfigFieldOption("LOW", .int(DesiredAccuracy.low.rawValue)),
    ConfigFieldOption("V.LOW", .int(DesiredAccuracy.veryLow.rawValue)),
]

/// The corrected version (see file header): a STRING enum, not
/// `accuracyOptions`'s numeric scale.
private let stationaryAccuracyOptions: [ConfigFieldOption] = [
    ConfigFieldOption("HIGH", .string("HIGH")),
    ConfigFieldOption("BAL", .string("BALANCED")),
    ConfigFieldOption("LOW", .string("LOW")),
]

public let configSections: [ConfigSection] = [
    // ADDED section (not in RN/Flutter — see file header diff note).
    ConfigSection("Permissions", [
        // Default "Always" IS documented, despite `Config.swift` itself
        // being silent: the engine hard-codes the `?: @"Always"` fallback
        // (core/ios/Sources/BGGeoEngine.mm:2157,2372) and the docs table
        // states Default 'Always' — not a guess.
        ConfigField(
            key: "locationAuthorizationRequest", label: "Authorization request", type: .enumeration,
            options: [ConfigFieldOption("Always", .string("Always")), ConfigFieldOption("When In Use", .string("WhenInUse"))],
            defaultValue: .string("Always"),
            hint: "ADDED — engine default \"Always\" (BGGeoEngine.mm fallback + docs table)"
        ),
        ConfigField(
            key: "disableLocationAuthorizationAlert", label: "Disable auth alert", type: .bool,
            defaultValue: .bool(false),
            hint: "ADDED — suppresses the Settings-nudge alert"
        ),
    ]),
    ConfigSection("Geolocation", [
        ConfigField(key: "desiredAccuracy", label: "Desired accuracy", type: .enumeration, options: accuracyOptions, defaultValue: .int(DesiredAccuracy.high.rawValue)),
        ConfigField(key: "distanceFilter", label: "Distance filter", type: .number, defaultValue: .double(10), unit: "m"),
        ConfigField(key: "stationaryRadius", label: "Stationary radius", type: .number, defaultValue: .double(25), unit: "m"),
        ConfigField(key: "stationaryDistanceFilter", label: "Stationary distance filter", type: .number, defaultValue: .double(75), unit: "m"),
        ConfigField(key: "stationaryDesiredAccuracy", label: "Stationary accuracy", type: .enumeration, options: stationaryAccuracyOptions, defaultValue: .string("BALANCED")),
        ConfigField(key: "stationaryKeepAlive", label: "Stationary keep-alive", type: .bool, defaultValue: .bool(true)),
        ConfigField(
            key: "stationaryLocationUpdateInterval", label: "Stationary interval", type: .number, defaultValue: .int(30000), unit: "ms", platform: .android,
            hint: "ADDED — Config doc default 30000"
        ),
        ConfigField(key: "locationUpdateInterval", label: "Moving interval", type: .number, defaultValue: .int(1000), unit: "ms", platform: .android),
        ConfigField(key: "showsBackgroundLocationIndicator", label: "BG location indicator", type: .bool, defaultValue: .bool(false), platform: .ios),
        ConfigField(key: "disableLocationFilter", label: "Disable Kalman filter", type: .bool, defaultValue: .bool(false)),
        ConfigField(key: "locationFilterMaxAccuracy", label: "Filter max accuracy", type: .number, defaultValue: .double(100), unit: "m"),
        ConfigField(key: "locationFilterMaxSpeed", label: "Filter max speed", type: .number, defaultValue: .double(60), unit: "m/s"),
        ConfigField(key: "locationFilterPolicy", label: "Filter policy", type: .enumeration, options: [
            ConfigFieldOption("CONS", .string("Conservative")),
            ConfigFieldOption("ADJ", .string("Adjust")),
            ConfigFieldOption("PASS", .string("PassThrough")),
        ], defaultValue: .string("Conservative")),
        ConfigField(key: "kalmanProfile", label: "Kalman profile", type: .enumeration, options: [
            ConfigFieldOption("DEF", .string("DEFAULT")),
            ConfigFieldOption("AGGR", .string("AGGRESSIVE")),
            ConfigFieldOption("CONS", .string("CONSERVATIVE")),
        ], defaultValue: .string("DEFAULT")),
        ConfigField(key: "odometerAccuracyThreshold", label: "Odometer accuracy gate", type: .number, defaultValue: .double(0), unit: "m", hint: "0 = off"),
    ]),
    ConfigSection("Motion / Activity", [
        ConfigField(key: "stopTimeout", label: "Stop timeout", type: .number, defaultValue: .int(5), unit: "min"),
        ConfigField(key: "motionTriggerDelay", label: "Motion trigger delay", type: .number, defaultValue: .int(0), unit: "ms"),
        ConfigField(key: "minimumActivityRecognitionConfidence", label: "Min AR confidence", type: .number, defaultValue: .int(75), unit: "%"),
        ConfigField(key: "disableMotionActivityUpdates", label: "Disable motion updates", type: .bool, defaultValue: .bool(false)),
        ConfigField(key: "preventSuspend", label: "Prevent suspend", type: .bool, defaultValue: .bool(false), platform: .ios),
        ConfigField(
            key: "triggerActivities", label: "Trigger activities", type: .string,
            defaultValue: .string("in_vehicle,on_bicycle,walking,running,on_foot"),
            hint: "ADDED — CSV of activity names that count as \"moving\""
        ),
        ConfigField(
            key: "activityRecognitionInterval", label: "AR poll interval", type: .number, defaultValue: .int(10000), unit: "ms", platform: .android,
            hint: "ADDED — Config doc default 10000"
        ),
    ]),
    ConfigSection("Power", [
        ConfigField(key: "disableElasticity", label: "Disable elasticity", type: .bool, defaultValue: .bool(false)),
        ConfigField(key: "elasticityMultiplier", label: "Elasticity multiplier", type: .number, defaultValue: .double(1)),
    ]),
    ConfigSection("HTTP / Sync", [
        ConfigField(key: "autoSync", label: "Auto sync", type: .bool, defaultValue: .bool(true)),
        ConfigField(key: "autoSyncThreshold", label: "Auto-sync threshold", type: .number, defaultValue: .int(0)),
        ConfigField(key: "disableAutoSyncOnCellular", label: "Wi-Fi-only auto sync", type: .bool, defaultValue: .bool(false), hint: "explicit Sync still uploads on cellular"),
        ConfigField(key: "batchSync", label: "Batch sync", type: .bool, defaultValue: .bool(false)),
        ConfigField(key: "maxBatchSize", label: "Max batch size", type: .number, defaultValue: .int(50)),
        ConfigField(key: "httpTimeoutMs", label: "HTTP timeout", type: .number, defaultValue: .int(60000), unit: "ms"),
        ConfigField(
            key: "httpRootProperty", label: "HTTP root property", type: .string, defaultValue: .string("location"),
            hint: "ADDED — \".\" merges a single record into the root"
        ),
        ConfigField(
            key: "method", label: "HTTP method", type: .enumeration,
            options: [ConfigFieldOption("POST", .string("POST")), ConfigFieldOption("PUT", .string("PUT")), ConfigFieldOption("PATCH", .string("PATCH"))],
            defaultValue: .string("POST"),
            hint: "ADDED — Config doc default \"POST\""
        ),
    ]),
    ConfigSection("Persistence", [
        ConfigField(key: "maxRecordsToPersist", label: "Max records", type: .number, defaultValue: .int(-1), hint: "-1 = unlimited"),
        ConfigField(key: "maxDaysToPersist", label: "Max days", type: .number, defaultValue: .int(0), unit: "d"),
    ]),
    ConfigSection("Geofencing", [
        ConfigField(key: "geofenceProximityRadius", label: "Proximity radius", type: .number, defaultValue: .double(1000), unit: "m"),
        ConfigField(key: "maxMonitoredGeofences", label: "Max monitored", type: .number, defaultValue: .int(-1), hint: "-1 = platform budget"),
        ConfigField(key: "geofenceInitialTriggerEntry", label: "Initial ENTER trigger", type: .bool, defaultValue: .bool(true)),
    ]),
    ConfigSection("Application", [
        ConfigField(key: "heartbeatInterval", label: "Heartbeat interval", type: .number, defaultValue: .int(60), unit: "s"),
        ConfigField(key: "stopOnTerminate", label: "Stop on terminate", type: .bool, defaultValue: .bool(true)),
        ConfigField(key: "startOnBoot", label: "Start on boot", type: .bool, defaultValue: .bool(false)),
        ConfigField(key: "debug", label: "Debug sounds", type: .bool, defaultValue: .bool(true)),
    ]),
    ConfigSection("Diagnostics / Engine", [
        // Raw ints, not the SDK's `LogLevel` enum: the app's own `LogLevel`
        // (AppStore.swift, a String enum for the Logs tab) shadows the bare
        // name within this module, and `BackgroundGeolocation.LogLevel`
        // doesn't resolve either — `BackgroundGeolocation` is itself a type
        // (the SDK facade enum) in scope, so member lookup on it stops
        // there rather than falling back to the module's top-level type.
        // Values match `BackgroundGeolocation.LogLevel`'s raw values exactly
        // (off=0 .. verbose=5) — see `LogLevel.swift`/`Constants.swift`.
        ConfigField(key: "logLevel", label: "Log level", type: .enumeration, options: [
            ConfigFieldOption("OFF", .int(0)),
            ConfigFieldOption("ERR", .int(1)),
            ConfigFieldOption("WARN", .int(2)),
            ConfigFieldOption("INFO", .int(3)),
            ConfigFieldOption("DBG", .int(4)),
            ConfigFieldOption("VERB", .int(5)),
        ], defaultValue: .int(3), hint: "native log persistence (mirror to logcat/os_log is always on)"),
        ConfigField(key: "diagnosticExtras", label: "Diagnostic extras", type: .bool, defaultValue: .bool(false)),
        ConfigField(key: "useSessionEngine", label: "Session engine", type: .bool, defaultValue: .bool(true), platform: .ios, hint: "OFF = legacy CLLocationManager (SLC-burst degraded in background)"),
        ConfigField(
            key: "logMaxDays", label: "Log retention", type: .number, defaultValue: .int(3), unit: "d",
            hint: "ADDED — Config doc default 3"
        ),
    ]),
    ConfigSection("Notification", [
        ConfigField(key: "notification.title", label: "Title", type: .string, defaultValue: .string("Location"), platform: .android),
        ConfigField(key: "notification.text", label: "Text", type: .string, defaultValue: .string("Location tracking active"), platform: .android),
        ConfigField(key: "notification.channelId", label: "Channel ID", type: .string, defaultValue: .string("bgeo_location_min"), platform: .android, hint: "importance is frozen per channel — change the ID to change priority"),
        ConfigField(key: "notification.channelName", label: "Channel name", type: .string, defaultValue: .string("Location"), platform: .android),
        ConfigField(key: "notification.smallIcon", label: "Small icon", type: .string, defaultValue: .string(""), platform: .android, hint: "drawable/name or mipmap/name; empty = app icon"),
        ConfigField(key: "notification.color", label: "Accent color", type: .string, defaultValue: .string(""), platform: .android, hint: "#RRGGBB; empty = none"),
        ConfigField(key: "notification.priority", label: "Priority", type: .enumeration, options: [
            ConfigFieldOption("MIN", .int(-2)),
            ConfigFieldOption("LOW", .int(-1)),
            ConfigFieldOption("DEF", .int(0)),
            ConfigFieldOption("HIGH", .int(1)),
            ConfigFieldOption("MAX", .int(2)),
        ], defaultValue: .int(-2), platform: .android),
    ]),
]

/// The schema's declared default for `key`, or nil if `key` isn't in any
/// section (mirrors `configSchema.ts`'s `defaultFor` minus the `BASE_CONFIG`
/// layer — the app's boot-time base config is assembled elsewhere, per
/// Task 8's brief).
public func configDefault(for key: String) -> ConfigValue? {
    for section in configSections {
        if let field = section.fields.first(where: { $0.key == key }) {
            return field.defaultValue
        }
    }
    return nil
}

/// All schema keys under a dot prefix, e.g. `"notification."` -> every
/// `notification.*` field. Used by `ConfigStore` to rebuild a nested `Config`
/// sub-object wholesale (see `ConfigStore`'s doc comment on why).
func configKeys(withPrefix prefix: String) -> [String] {
    configSections.flatMap { $0.fields }.map(\.key).filter { $0.hasPrefix(prefix) }
}
