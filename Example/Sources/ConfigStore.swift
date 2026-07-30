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

    /// Apply one config key right away (live `setConfig`) and persist it.
    public func setOverride(_ key: String, _ value: Any) async {
        overrides[key] = value
        persist()
        try? await applyConfig(patch(forChangedKey: key))
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

    private func patch(forChangedKey key: String) -> Config {
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
        case "title": notification.title = ConfigCoerce.string(raw)
        case "text": notification.text = ConfigCoerce.string(raw)
        case "channelId": notification.channelId = ConfigCoerce.string(raw)
        case "channelName": notification.channelName = ConfigCoerce.string(raw)
        case "smallIcon": notification.smallIcon = ConfigCoerce.string(raw)
        case "color": notification.color = ConfigCoerce.string(raw)
        case "priority": notification.priority = ConfigCoerce.int(raw)
        default: break
        }
    }

    // MARK: - Key -> Config property

    /// Every non-`notification.*` schema key, applied onto `config`. Shared
    /// by `merged(into:)`, the live single-key patch, and the reset patch —
    /// one switch, one place that can drift from `ConfigSchema.swift`
    /// (guarded by `ConfigStoreTests`' exhaustive round-trip test).
    static func apply(key: String, rawValue: Any, into config: inout Config) {
        switch key {
        case "locationAuthorizationRequest": config.locationAuthorizationRequest = ConfigCoerce.string(rawValue)
        case "disableLocationAuthorizationAlert": config.disableLocationAuthorizationAlert = ConfigCoerce.bool(rawValue)
        case "desiredAccuracy": config.desiredAccuracy = ConfigCoerce.int(rawValue)
        case "distanceFilter": config.distanceFilter = ConfigCoerce.double(rawValue)
        case "disableLocationFilter": config.disableLocationFilter = ConfigCoerce.bool(rawValue)
        case "locationFilterMaxAccuracy": config.locationFilterMaxAccuracy = ConfigCoerce.double(rawValue)
        case "locationFilterMaxSpeed": config.locationFilterMaxSpeed = ConfigCoerce.double(rawValue)
        case "locationFilterPolicy": config.locationFilterPolicy = ConfigCoerce.string(rawValue)
        case "kalmanProfile": config.kalmanProfile = ConfigCoerce.string(rawValue)
        case "odometerAccuracyThreshold": config.odometerAccuracyThreshold = ConfigCoerce.double(rawValue)
        case "disableElasticity": config.disableElasticity = ConfigCoerce.bool(rawValue)
        case "elasticityMultiplier": config.elasticityMultiplier = ConfigCoerce.double(rawValue)
        case "stationaryDesiredAccuracy": config.stationaryDesiredAccuracy = ConfigCoerce.string(rawValue)
        case "stationaryLocationUpdateInterval": config.stationaryLocationUpdateInterval = ConfigCoerce.int(rawValue)
        case "triggerActivities": config.triggerActivities = ConfigCoerce.string(rawValue)
        case "minimumActivityRecognitionConfidence": config.minimumActivityRecognitionConfidence = ConfigCoerce.int(rawValue)
        case "activityRecognitionInterval": config.activityRecognitionInterval = ConfigCoerce.int(rawValue)
        case "disableMotionActivityUpdates": config.disableMotionActivityUpdates = ConfigCoerce.bool(rawValue)
        case "stopTimeout": config.stopTimeout = ConfigCoerce.int(rawValue)
        case "showsBackgroundLocationIndicator": config.showsBackgroundLocationIndicator = ConfigCoerce.bool(rawValue)
        case "stationaryRadius": config.stationaryRadius = ConfigCoerce.double(rawValue)
        case "stationaryDistanceFilter": config.stationaryDistanceFilter = ConfigCoerce.double(rawValue)
        case "preventSuspend": config.preventSuspend = ConfigCoerce.bool(rawValue)
        case "heartbeatInterval": config.heartbeatInterval = ConfigCoerce.int(rawValue)
        case "motionTriggerDelay": config.motionTriggerDelay = ConfigCoerce.int(rawValue)
        case "locationUpdateInterval": config.locationUpdateInterval = ConfigCoerce.int(rawValue)
        case "stopOnTerminate": config.stopOnTerminate = ConfigCoerce.bool(rawValue)
        case "startOnBoot": config.startOnBoot = ConfigCoerce.bool(rawValue)
        case "debug": config.debug = ConfigCoerce.bool(rawValue)
        case "logLevel": config.logLevel = ConfigCoerce.int(rawValue)
        case "logMaxDays": config.logMaxDays = ConfigCoerce.int(rawValue)
        case "maxDaysToPersist": config.maxDaysToPersist = ConfigCoerce.int(rawValue)
        case "httpRootProperty": config.httpRootProperty = ConfigCoerce.string(rawValue)
        case "autoSync": config.autoSync = ConfigCoerce.bool(rawValue)
        case "disableAutoSyncOnCellular": config.disableAutoSyncOnCellular = ConfigCoerce.bool(rawValue)
        case "autoSyncThreshold": config.autoSyncThreshold = ConfigCoerce.int(rawValue)
        case "batchSync": config.batchSync = ConfigCoerce.bool(rawValue)
        case "maxBatchSize": config.maxBatchSize = ConfigCoerce.int(rawValue)
        case "httpTimeoutMs": config.httpTimeoutMs = ConfigCoerce.int(rawValue)
        case "maxRecordsToPersist": config.maxRecordsToPersist = ConfigCoerce.int(rawValue)
        case "stationaryKeepAlive": config.stationaryKeepAlive = ConfigCoerce.bool(rawValue)
        case "diagnosticExtras": config.diagnosticExtras = ConfigCoerce.bool(rawValue)
        case "useSessionEngine": config.useSessionEngine = ConfigCoerce.bool(rawValue)
        case "geofenceProximityRadius": config.geofenceProximityRadius = ConfigCoerce.double(rawValue)
        case "maxMonitoredGeofences": config.maxMonitoredGeofences = ConfigCoerce.int(rawValue)
        case "geofenceInitialTriggerEntry": config.geofenceInitialTriggerEntry = ConfigCoerce.bool(rawValue)
        default: break // notification.* is handled by the caller; unknown keys are ignored.
        }
    }
}
