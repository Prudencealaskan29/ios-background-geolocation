// Persisted user overrides for the SDK config (Settings screen). Overrides
// are applied immediately via setConfig and merged over the app's base
// config at boot (`merged(into:)`, called from Task 8's wiring).
//
// Swift port of `react-native/example/src/configStore.ts`
// (`flutter/example/lib/src/config_store.dart` is the same port for
// Flutter). One structural difference from both: RN/Flutter's `Config` is a
// loose JS/Dart map, so their store builds nested PATCH dictionaries by
// stringly-typed key. Swift's `Config` is a real struct, so this store
// applies each override directly onto typed `Config` properties via
// `ConfigStore.apply(key:rawValue:into:)` — same key-set, same nested-patch
// safety rule (see below), no dictionary plumbing.

import Foundation
import BackgroundGeolocation

@MainActor
public final class ConfigStore: ObservableObject {
    private static let storageKey = "bgeo:configOverrides"

    /// Flat, dot-keyed overrides (e.g. `"notification.priority"`), exactly as
    /// the schema declares them. Persisted as JSON in `UserDefaults`.
    @Published public private(set) var overrides: [String: Any] = [:]

    private let userDefaults: UserDefaults

    /// Test seam, same shape as `DeviceLink.applyConfig` (see that file's doc
    /// comment for why a closure rather than a protocol/global swap).
    var applyConfig: (Config) async throws -> Void = { try await BackgroundGeolocation.setConfig($0) }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.overrides = Self.loadOverrides(from: userDefaults)
    }

    private static func loadOverrides(from userDefaults: UserDefaults) -> [String: Any] {
        guard let data = userDefaults.data(forKey: storageKey),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dictionary = json as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.fragmentsAllowed]) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Public API

    /// Apply one config key right away (live `setConfig`) and, ONLY once the
    /// engine has actually accepted it, persist it. Mirrors `configStore.ts`'s
    /// `applyOverride`: build the candidate patch, await `setConfig` FIRST,
    /// and commit the override (in-memory + storage) only on success. Doing
    /// it the other way around — persist, then best-effort apply — leaves a
    /// REJECTED key sitting in `overrides` forever: it gets silently
    /// re-applied to the engine on every future boot via `merged(into:)`,
    /// while the caller has no way to know it never actually took.
    public func setOverride(_ key: String, _ value: Any) async throws {
        var candidate = overrides
        candidate[key] = value
        try await applyConfig(patch(forChangedKey: key, overrides: candidate))
        overrides = candidate
        persist()
    }

    /// Drop all overrides, pushing each previously-overridden key's default
    /// back to the live engine first (mirrors `configStore.ts`'s
    /// `resetOverrides`).
    public func reset() async {
        let overriddenKeys = Array(overrides.keys)
        if !overriddenKeys.isEmpty {
            try? await applyConfig(resetPatch(for: overriddenKeys))
        }
        overrides = [:]
        userDefaults.removeObject(forKey: Self.storageKey)
    }

    /// Boot-time merge: `base` with every persisted override layered on top.
    /// Keys with no override are left exactly as `base` set them — including
    /// nested `notification.*` sub-fields `base` already set but this store
    /// has no override for (see `overlayNotificationOverrides`, which is
    /// deliberately NOT the same nested-defaults-fill function the live patch
    /// path below uses).
    public func merged(into base: Config) -> Config {
        var config = base
        for (key, value) in overrides where !key.hasPrefix("notification.") {
            Self.apply(key: key, rawValue: value, into: &config)
        }
        config.notification = overlayNotificationOverrides(onto: config.notification)
        return config
    }

    // MARK: - Patch building for live setConfig
    //
    // `setConfig` is a PATCH at the engine, but for a `"a.b"` key the engine
    // replaces the WHOLE nested object it's given — so pushing just
    // `{notification: {title: "x"}}` would silently blank every other
    // notification field the user had set in an earlier call. Rebuilding the
    // nested object from EVERY schema field of that prefix (override, else
    // its default) every time any one of them changes is the same rule
    // `configStore.ts`'s `nestedPatchFor`/`toConfigPatch` encode. This is a
    // DIFFERENT rule from `merged(into:)`'s above: that one is building a
    // whole `Config` from scratch (no existing engine state to clobber), so
    // it only needs to overlay what's actually overridden.

    /// `overrides` is passed explicitly (the CANDIDATE dictionary, not
    /// `self.overrides`) so `setOverride` can build the patch to try BEFORE
    /// committing anything to the published property — see that method's
    /// doc comment.
    private func patch(forChangedKey key: String, overrides: [String: Any]) -> Config {
        var patch = Config()
        if key.hasPrefix("notification.") {
            patch.notification = fullNotificationPatch(source: overrides)
        } else {
            Self.apply(key: key, rawValue: overrides[key] as Any, into: &patch)
        }
        return patch
    }

    private func resetPatch(for keys: [String]) -> Config {
        var patch = Config()
        var rebuiltNotification = false
        for key in keys {
            if key.hasPrefix("notification.") {
                guard !rebuiltNotification else { continue }
                rebuiltNotification = true
                patch.notification = fullNotificationPatch(source: [:])
            } else if let defaultValue = configDefault(for: key) {
                Self.apply(key: key, rawValue: defaultValue.any, into: &patch)
            }
        }
        return patch
    }

    /// `merged(into:)`'s notification handling: only touches the dot-keys
    /// this store actually has an override for, leaving every other
    /// notification field exactly as `base` set it (nil stays nil).
    private func overlayNotificationOverrides(onto base: NotificationConfig?) -> NotificationConfig? {
        let overriddenKeys = configKeys(withPrefix: "notification.").filter { overrides[$0] != nil }
        guard !overriddenKeys.isEmpty else { return base }
        var notification = base ?? NotificationConfig()
        for key in overriddenKeys {
            guard let raw = overrides[key] else { continue }
            assignNotificationField(String(key.dropFirst("notification.".count)), raw, into: &notification)
        }
        return notification
    }

    /// Live-push/reset's notification handling: rebuilds EVERY notification
    /// field from `source` (override if present, else the schema default) —
    /// see the wholesale-replace note above `patch(forChangedKey:)`.
    private func fullNotificationPatch(source: [String: Any]) -> NotificationConfig {
        var notification = NotificationConfig()
        for key in configKeys(withPrefix: "notification.") {
            guard let raw = source[key] ?? configDefault(for: key)?.any else { continue }
            assignNotificationField(String(key.dropFirst("notification.".count)), raw, into: &notification)
        }
        return notification
    }

    private func assignNotificationField(_ sub: String, _ raw: Any, into notification: inout NotificationConfig) {
        switch sub {
        case "title": Self.set(&notification.title, ConfigCoerce.string(raw))
        case "text": Self.set(&notification.text, ConfigCoerce.string(raw))
        case "channelId": Self.set(&notification.channelId, ConfigCoerce.string(raw))
        case "channelName": Self.set(&notification.channelName, ConfigCoerce.string(raw))
        case "smallIcon": Self.set(&notification.smallIcon, ConfigCoerce.string(raw))
        case "color": Self.set(&notification.color, ConfigCoerce.string(raw))
        case "priority": Self.set(&notification.priority, ConfigCoerce.int(raw))
        default: break
        }
    }

    // MARK: - Key -> Config property

    /// Only writes `property` when `coerced` succeeded. A type-mismatched
    /// override (e.g. a pre-phase-0 install with a numeric
    /// `stationaryDesiredAccuracy` still sitting in `UserDefaults` after the
    /// string-enum fix) must leave whatever `base`/`config` already had
    /// ALONE, not silently erase it to nil — the same clobber hazard
    /// `overlayNotificationOverrides` exists to avoid for `notification.*`,
    /// applied here to every scalar property too.
    private static func set<T>(_ property: inout T?, _ coerced: T?) {
        guard let coerced else { return }
        property = coerced
    }

    /// Every non-`notification.*` schema key, applied onto `config`. Shared
    /// by `merged(into:)`, the live single-key patch, and the reset patch —
    /// one switch, one place that can drift from `ConfigSchema.swift`
    /// (guarded by `ConfigStoreTests`' exhaustive round-trip test, in both
    /// directions).
    static func apply(key: String, rawValue: Any, into config: inout Config) {
        switch key {
        case "locationAuthorizationRequest": set(&config.locationAuthorizationRequest, ConfigCoerce.string(rawValue))
        case "disableLocationAuthorizationAlert": set(&config.disableLocationAuthorizationAlert, ConfigCoerce.bool(rawValue))
        case "desiredAccuracy": set(&config.desiredAccuracy, ConfigCoerce.int(rawValue))
        case "distanceFilter": set(&config.distanceFilter, ConfigCoerce.double(rawValue))
        case "disableLocationFilter": set(&config.disableLocationFilter, ConfigCoerce.bool(rawValue))
        case "locationFilterMaxAccuracy": set(&config.locationFilterMaxAccuracy, ConfigCoerce.double(rawValue))
        case "locationFilterMaxSpeed": set(&config.locationFilterMaxSpeed, ConfigCoerce.double(rawValue))
        case "locationFilterPolicy": set(&config.locationFilterPolicy, ConfigCoerce.string(rawValue))
        case "kalmanProfile": set(&config.kalmanProfile, ConfigCoerce.string(rawValue))
        case "odometerAccuracyThreshold": set(&config.odometerAccuracyThreshold, ConfigCoerce.double(rawValue))
        case "disableElasticity": set(&config.disableElasticity, ConfigCoerce.bool(rawValue))
        case "elasticityMultiplier": set(&config.elasticityMultiplier, ConfigCoerce.double(rawValue))
        case "stationaryDesiredAccuracy": set(&config.stationaryDesiredAccuracy, ConfigCoerce.string(rawValue))
        case "stationaryLocationUpdateInterval": set(&config.stationaryLocationUpdateInterval, ConfigCoerce.int(rawValue))
        case "triggerActivities": set(&config.triggerActivities, ConfigCoerce.string(rawValue))
        case "minimumActivityRecognitionConfidence": set(&config.minimumActivityRecognitionConfidence, ConfigCoerce.int(rawValue))
        case "activityRecognitionInterval": set(&config.activityRecognitionInterval, ConfigCoerce.int(rawValue))
        case "disableMotionActivityUpdates": set(&config.disableMotionActivityUpdates, ConfigCoerce.bool(rawValue))
        case "stopTimeout": set(&config.stopTimeout, ConfigCoerce.int(rawValue))
        case "showsBackgroundLocationIndicator": set(&config.showsBackgroundLocationIndicator, ConfigCoerce.bool(rawValue))
        case "stationaryRadius": set(&config.stationaryRadius, ConfigCoerce.double(rawValue))
        case "stationaryDistanceFilter": set(&config.stationaryDistanceFilter, ConfigCoerce.double(rawValue))
        case "preventSuspend": set(&config.preventSuspend, ConfigCoerce.bool(rawValue))
        case "heartbeatInterval": set(&config.heartbeatInterval, ConfigCoerce.int(rawValue))
        case "motionTriggerDelay": set(&config.motionTriggerDelay, ConfigCoerce.int(rawValue))
        case "locationUpdateInterval": set(&config.locationUpdateInterval, ConfigCoerce.int(rawValue))
        case "stopOnTerminate": set(&config.stopOnTerminate, ConfigCoerce.bool(rawValue))
        case "startOnBoot": set(&config.startOnBoot, ConfigCoerce.bool(rawValue))
        case "debug": set(&config.debug, ConfigCoerce.bool(rawValue))
        case "logLevel": set(&config.logLevel, ConfigCoerce.int(rawValue))
        case "logMaxDays": set(&config.logMaxDays, ConfigCoerce.int(rawValue))
        case "maxDaysToPersist": set(&config.maxDaysToPersist, ConfigCoerce.int(rawValue))
        case "httpRootProperty": set(&config.httpRootProperty, ConfigCoerce.string(rawValue))
        case "method": set(&config.method, ConfigCoerce.string(rawValue))
        case "autoSync": set(&config.autoSync, ConfigCoerce.bool(rawValue))
        case "disableAutoSyncOnCellular": set(&config.disableAutoSyncOnCellular, ConfigCoerce.bool(rawValue))
        case "autoSyncThreshold": set(&config.autoSyncThreshold, ConfigCoerce.int(rawValue))
        case "batchSync": set(&config.batchSync, ConfigCoerce.bool(rawValue))
        case "maxBatchSize": set(&config.maxBatchSize, ConfigCoerce.int(rawValue))
        case "httpTimeoutMs": set(&config.httpTimeoutMs, ConfigCoerce.int(rawValue))
        case "maxRecordsToPersist": set(&config.maxRecordsToPersist, ConfigCoerce.int(rawValue))
        case "stationaryKeepAlive": set(&config.stationaryKeepAlive, ConfigCoerce.bool(rawValue))
        case "diagnosticExtras": set(&config.diagnosticExtras, ConfigCoerce.bool(rawValue))
        case "useSessionEngine": set(&config.useSessionEngine, ConfigCoerce.bool(rawValue))
        case "geofenceProximityRadius": set(&config.geofenceProximityRadius, ConfigCoerce.double(rawValue))
        case "maxMonitoredGeofences": set(&config.maxMonitoredGeofences, ConfigCoerce.int(rawValue))
        case "geofenceInitialTriggerEntry": set(&config.geofenceInitialTriggerEntry, ConfigCoerce.bool(rawValue))
        default: break // notification.* is handled by the caller; unknown keys are ignored.
        }
    }
}
