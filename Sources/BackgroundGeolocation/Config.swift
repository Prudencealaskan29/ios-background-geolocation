import Foundation

/// Foreground-service notification (Android only). No-op on iOS.
/// `priority` is Transistor NOTIFICATION_PRIORITY_*: -2 MIN (default) .. 2 MAX —
/// it also sets the channel importance, which Android freezes per channelId
/// (change channelId to change it). `smallIcon` = "drawable/name" | "mipmap/name";
/// `color` = "#RRGGBB".
public struct NotificationConfig {
    public var title: String?
    public var text: String?
    public var channelId: String?
    public var channelName: String?
    public var smallIcon: String?
    public var color: String?
    public var priority: Int?

    public init(
        title: String? = nil,
        text: String? = nil,
        channelId: String? = nil,
        channelName: String? = nil,
        smallIcon: String? = nil,
        color: String? = nil,
        priority: Int? = nil
    ) {
        self.title = title
        self.text = text
        self.channelId = channelId
        self.channelName = channelName
        self.smallIcon = smallIcon
        self.color = color
        self.priority = priority
    }

    public func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        if let title { dictionary["title"] = title }
        if let text { dictionary["text"] = text }
        if let channelId { dictionary["channelId"] = channelId }
        if let channelName { dictionary["channelName"] = channelName }
        if let smallIcon { dictionary["smallIcon"] = smallIcon }
        if let color { dictionary["color"] = color }
        if let priority { dictionary["priority"] = priority }
        return dictionary
    }
}

/// Native token refresh: on a 401/403 the uploader exchanges `refreshToken`
/// at `refreshUrl` (headers `refreshHeaders`, body `refreshPayload` with the
/// "{refreshToken}" placeholder substituted; default { refresh_token }) so
/// killed-app uploads survive an access-token expiry without a live JS
/// context. Outcomes surface via onAuthorization.
public struct AuthorizationConfig {
    public var strategy: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var refreshUrl: String?
    public var refreshPayload: [String: Any]?
    public var refreshHeaders: [String: String]?

    public init(
        strategy: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        refreshUrl: String? = nil,
        refreshPayload: [String: Any]? = nil,
        refreshHeaders: [String: String]? = nil
    ) {
        self.strategy = strategy
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.refreshUrl = refreshUrl
        self.refreshPayload = refreshPayload
        self.refreshHeaders = refreshHeaders
    }

    public func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        if let strategy { dictionary["strategy"] = strategy }
        if let accessToken { dictionary["accessToken"] = accessToken }
        if let refreshToken { dictionary["refreshToken"] = refreshToken }
        if let refreshUrl { dictionary["refreshUrl"] = refreshUrl }
        if let refreshPayload { dictionary["refreshPayload"] = refreshPayload }
        if let refreshHeaders { dictionary["refreshHeaders"] = refreshHeaders }
        return dictionary
    }

    /// Set `Config.authorization` to this to clear the whole key — wipes
    /// stored tokens/refresh config engine-side. See `Config.clearString`;
    /// this is the same sentinel, carried on `strategy` because
    /// `AuthorizationConfig` has no single scalar of its own to compare.
    public static let clear = AuthorizationConfig(strategy: Config.clearString)
}

/// Mirrors `interface Config` in `react-native/src/types.ts` (the cross-SDK
/// source of truth for all four front-ends) property-for-property. Guarded
/// against drift by `ConfigDriftTests`.
///
/// `setConfig` is a PATCH, not a replacement: the engine merges whatever it
/// receives into live config. `toDictionary()` therefore OMITS every `nil`
/// property — an untouched `Config()` produces an empty dictionary and
/// changes nothing. To express "unset this key" instead, set the property to
/// its `clear*` sentinel (see `clearString`).
///
/// The license key is NOT a config option — set it in the app's Info.plist
/// (`BGeoLicense`), read at launch before this API is used. In a RELEASE
/// build a bad key makes `ready()`/`start()` reject with a `LICENSE_*` code;
/// debuggable builds / the iOS simulator always run unlicensed (evaluation),
/// whatever the key state.
public struct Config {
    public var locationAuthorizationRequest: String?
    public var locationAuthorizationAlert: [String: String]?
    /// Suppress the Settings-nudge alert driven by `locationAuthorizationAlert`. Default false.
    public var disableLocationAuthorizationAlert: Bool?
    /// @unsupported No-op on iOS; Android uses the OS permission rationale flow.
    public var backgroundPermissionRationale: [String: String]?
    public var desiredAccuracy: Int?
    public var distanceFilter: Double?
    /// Bypass the Kalman/accuracy/teleport filter entirely. Default false.
    public var disableLocationFilter: Bool?
    /// Reject fixes with accuracy worse than this (metres). Default 100.
    public var locationFilterMaxAccuracy: Double?
    /// Teleport rejection: max implied speed between fixes (m/s). Default 60.
    public var locationFilterMaxSpeed: Double?
    /// Filter decision phase: 'Conservative' (default — reject teleport fixes) |
    /// 'Adjust' (cap teleports to the kinematic limit instead of dropping) |
    /// 'PassThrough' (accuracy gate only; no teleport rejection, no Kalman
    /// smoothing). Case-insensitive. Applied when the filter is (re)built at
    /// tracking start/stop — not live on setConfig.
    public var locationFilterPolicy: String?
    /// Kalman tuning preset: 'DEFAULT' | 'AGGRESSIVE' (faster response, less lag)
    /// | 'CONSERVATIVE' (maximum smoothing). Case-insensitive. Applied when the
    /// filter is (re)built at tracking start/stop — not live on setConfig.
    public var kalmanProfile: String?
    /// Fixes with accuracy worse than this (metres) don't advance the odometer.
    /// 0 = off (default; tracking/upload unaffected — odometer only).
    public var odometerAccuracyThreshold: Double?
    /// Pin distanceFilter to its base value (no speed-elastic scaling). Default false.
    public var disableElasticity: Bool?
    /// Speed-elastic distanceFilter scaling intensity. Default 1.0.
    public var elasticityMultiplier: Double?
    /// Accuracy tier for the stationary keep-alive stream: HIGH | BALANCED | LOW. Default BALANCED.
    public var stationaryDesiredAccuracy: String?
    /// @platform android Stationary fused request interval (ms). Default 30000. No-op on iOS.
    public var stationaryLocationUpdateInterval: Int?
    /// CSV of activity names that count as "moving" (e.g. "in_vehicle,on_bicycle,walking,running,on_foot").
    public var triggerActivities: String?
    /// Min activity-recognition confidence 0-100. Default 75 Android; 50 iOS (coarse 33/66/100 scale).
    public var minimumActivityRecognitionConfidence: Int?
    /// @platform android Activity-recognition poll interval (ms). Default 10000. No-op on iOS.
    public var activityRecognitionInterval: Int?
    /// Ignore motion-activity updates (motion machine falls back to speed + stationary geofence). Default false.
    public var disableMotionActivityUpdates: Bool?
    public var stopTimeout: Int?
    /// @platform ios Show the blue background-location indicator. No-op on Android.
    public var showsBackgroundLocationIndicator: Bool?
    public var stationaryRadius: Double?
    /// @platform ios Low-power continuous wake distance; independent of the larger region radius. No-op on Android.
    public var stationaryDistanceFilter: Double?
    /// @platform ios Hold a background task while backgrounded+stationary. No-op on Android.
    public var preventSuspend: Bool?
    public var heartbeatInterval: Int?
    public var motionTriggerDelay: Int?
    /// @platform android Fused moving-request interval (ms). Default 1000. No-op on iOS.
    public var locationUpdateInterval: Int?
    /// @unsupported No-op. The Android foreground service is always on while tracking.
    public var foregroundService: Bool?
    /// @platform android Foreground-service notification. No-op on iOS. See `NotificationConfig`.
    public var notification: NotificationConfig?
    public var stopOnTerminate: Bool?
    public var startOnBoot: Bool?
    /// Plays a one-shot debug sound cue per event (Android/iOS). Does NOT affect tracking.
    public var debug: Bool?
    /// Native log persistence gate: 0=OFF (default) .. 5=VERBOSE (LOG_LEVEL_* constants).
    public var logLevel: Int?
    /// Days to retain native log rows. Default 3.
    public var logMaxDays: Int?
    /// Absolute URL for native log batch upload ({events:[...]}); unset = local-only.
    public var logUrl: String?
    public var maxDaysToPersist: Int?
    public var url: String?
    /// HTTP verb for uploads: POST (default) | PUT | PATCH.
    public var method: String?
    public var headers: [String: String]?
    /// Merged into the request body root alongside the location payload.
    public var params: [String: Any]?
    /// Merged into every uploaded record's `extras` (per-call extras win).
    public var extras: [String: Any]?
    /// Body key carrying the location(s); default "location". "." merges a single record into the root.
    public var httpRootProperty: String?
    /// Default true.
    public var autoSync: Bool?
    /// Defer AUTO-sync while on cellular (queue drains on Wi-Fi/ethernet arrival).
    /// Explicit sync() always uploads. Default false.
    public var disableAutoSyncOnCellular: Bool?
    public var autoSyncThreshold: Int?
    public var batchSync: Bool?
    public var maxBatchSize: Int?
    public var httpTimeoutMs: Int?
    public var maxRecordsToPersist: Int?
    /// Native token refresh — see `AuthorizationConfig`.
    public var authorization: AuthorizationConfig?
    /// Keep a low-power location request alive while stationary (fast wake source
    /// on trip start). Default true; false restores fully-sleep-GPS (slower wake).
    public var stationaryKeepAlive: Bool?
    /// Upload a compact native diagnostic snapshot in every point's `extras`
    /// (counters, app/motion state, manager config) — test devices only.
    public var diagnosticExtras: Bool?
    /// Session engine (iOS 17+): deliver via CLLocationUpdate.liveUpdates +
    /// CLBackgroundActivitySession while moving instead of legacy
    /// startUpdatingLocation (which iOS suspends between significant-change wakes).
    /// Default true (since 2026-07-23); kept as a remote-config kill-switch.
    /// iOS < 17 always uses the legacy path regardless of this flag.
    /// Android: silently ignored (stored but unread) — iOS-only key.
    public var useSessionEngine: Bool?
    /// Proximity slicing for app-facing geofences: only the nearest N within this
    /// radius (metres) of the last fix are registered with the OS. Default 1000.
    public var geofenceProximityRadius: Double?
    /// Cap on OS-registered geofences after proximity filtering (platform budget:
    /// 19 iOS / 99 Android). <=0 uses the platform budget as-is. Default -1.
    public var maxMonitoredGeofences: Int?
    /// Requests a synthetic ENTER for geofences already-inside on registration
    /// (iOS requestStateForRegion / Android INITIAL_TRIGGER_ENTER). Default true.
    public var geofenceInitialTriggerEntry: Bool?

    public init(
        locationAuthorizationRequest: String? = nil,
        locationAuthorizationAlert: [String: String]? = nil,
        disableLocationAuthorizationAlert: Bool? = nil,
        backgroundPermissionRationale: [String: String]? = nil,
        desiredAccuracy: Int? = nil,
        distanceFilter: Double? = nil,
        disableLocationFilter: Bool? = nil,
        locationFilterMaxAccuracy: Double? = nil,
        locationFilterMaxSpeed: Double? = nil,
        locationFilterPolicy: String? = nil,
        kalmanProfile: String? = nil,
        odometerAccuracyThreshold: Double? = nil,
        disableElasticity: Bool? = nil,
        elasticityMultiplier: Double? = nil,
        stationaryDesiredAccuracy: String? = nil,
        stationaryLocationUpdateInterval: Int? = nil,
        triggerActivities: String? = nil,
        minimumActivityRecognitionConfidence: Int? = nil,
        activityRecognitionInterval: Int? = nil,
        disableMotionActivityUpdates: Bool? = nil,
        stopTimeout: Int? = nil,
        showsBackgroundLocationIndicator: Bool? = nil,
        stationaryRadius: Double? = nil,
        stationaryDistanceFilter: Double? = nil,
        preventSuspend: Bool? = nil,
        heartbeatInterval: Int? = nil,
        motionTriggerDelay: Int? = nil,
        locationUpdateInterval: Int? = nil,
        foregroundService: Bool? = nil,
        notification: NotificationConfig? = nil,
        stopOnTerminate: Bool? = nil,
        startOnBoot: Bool? = nil,
        debug: Bool? = nil,
        logLevel: Int? = nil,
        logMaxDays: Int? = nil,
        logUrl: String? = nil,
        maxDaysToPersist: Int? = nil,
        url: String? = nil,
        method: String? = nil,
        headers: [String: String]? = nil,
        params: [String: Any]? = nil,
        extras: [String: Any]? = nil,
        httpRootProperty: String? = nil,
        autoSync: Bool? = nil,
        disableAutoSyncOnCellular: Bool? = nil,
        autoSyncThreshold: Int? = nil,
        batchSync: Bool? = nil,
        maxBatchSize: Int? = nil,
        httpTimeoutMs: Int? = nil,
        maxRecordsToPersist: Int? = nil,
        authorization: AuthorizationConfig? = nil,
        stationaryKeepAlive: Bool? = nil,
        diagnosticExtras: Bool? = nil,
        useSessionEngine: Bool? = nil,
        geofenceProximityRadius: Double? = nil,
        maxMonitoredGeofences: Int? = nil,
        geofenceInitialTriggerEntry: Bool? = nil
    ) {
        self.locationAuthorizationRequest = locationAuthorizationRequest
        self.locationAuthorizationAlert = locationAuthorizationAlert
        self.disableLocationAuthorizationAlert = disableLocationAuthorizationAlert
        self.backgroundPermissionRationale = backgroundPermissionRationale
        self.desiredAccuracy = desiredAccuracy
        self.distanceFilter = distanceFilter
        self.disableLocationFilter = disableLocationFilter
        self.locationFilterMaxAccuracy = locationFilterMaxAccuracy
        self.locationFilterMaxSpeed = locationFilterMaxSpeed
        self.locationFilterPolicy = locationFilterPolicy
        self.kalmanProfile = kalmanProfile
        self.odometerAccuracyThreshold = odometerAccuracyThreshold
        self.disableElasticity = disableElasticity
        self.elasticityMultiplier = elasticityMultiplier
        self.stationaryDesiredAccuracy = stationaryDesiredAccuracy
        self.stationaryLocationUpdateInterval = stationaryLocationUpdateInterval
        self.triggerActivities = triggerActivities
        self.minimumActivityRecognitionConfidence = minimumActivityRecognitionConfidence
        self.activityRecognitionInterval = activityRecognitionInterval
        self.disableMotionActivityUpdates = disableMotionActivityUpdates
        self.stopTimeout = stopTimeout
        self.showsBackgroundLocationIndicator = showsBackgroundLocationIndicator
        self.stationaryRadius = stationaryRadius
        self.stationaryDistanceFilter = stationaryDistanceFilter
        self.preventSuspend = preventSuspend
        self.heartbeatInterval = heartbeatInterval
        self.motionTriggerDelay = motionTriggerDelay
        self.locationUpdateInterval = locationUpdateInterval
        self.foregroundService = foregroundService
        self.notification = notification
        self.stopOnTerminate = stopOnTerminate
        self.startOnBoot = startOnBoot
        self.debug = debug
        self.logLevel = logLevel
        self.logMaxDays = logMaxDays
        self.logUrl = logUrl
        self.maxDaysToPersist = maxDaysToPersist
        self.url = url
        self.method = method
        self.headers = headers
        self.params = params
        self.extras = extras
        self.httpRootProperty = httpRootProperty
        self.autoSync = autoSync
        self.disableAutoSyncOnCellular = disableAutoSyncOnCellular
        self.autoSyncThreshold = autoSyncThreshold
        self.batchSync = batchSync
        self.maxBatchSize = maxBatchSize
        self.httpTimeoutMs = httpTimeoutMs
        self.maxRecordsToPersist = maxRecordsToPersist
        self.authorization = authorization
        self.stationaryKeepAlive = stationaryKeepAlive
        self.diagnosticExtras = diagnosticExtras
        self.useSessionEngine = useSessionEngine
        self.geofenceProximityRadius = geofenceProximityRadius
        self.maxMonitoredGeofences = maxMonitoredGeofences
        self.geofenceInitialTriggerEntry = geofenceInitialTriggerEntry
    }

    /// `setConfig` is a PATCH: this OMITS every `nil` property so an
    /// untouched `Config()` changes nothing. Properties equal to their
    /// `clear*` sentinel serialise as `NSNull()` instead, which is how an
    /// app expresses "unset this key" (e.g. `Config(url: Config.clearString)`
    /// on device unlink) — see `clearString`.
    public func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]

        if let locationAuthorizationRequest { dictionary["locationAuthorizationRequest"] = locationAuthorizationRequest }
        if let locationAuthorizationAlert { dictionary["locationAuthorizationAlert"] = locationAuthorizationAlert }
        if let disableLocationAuthorizationAlert { dictionary["disableLocationAuthorizationAlert"] = disableLocationAuthorizationAlert }
        if let backgroundPermissionRationale { dictionary["backgroundPermissionRationale"] = backgroundPermissionRationale }
        if let desiredAccuracy { dictionary["desiredAccuracy"] = desiredAccuracy }
        if let distanceFilter { dictionary["distanceFilter"] = distanceFilter }
        if let disableLocationFilter { dictionary["disableLocationFilter"] = disableLocationFilter }
        if let locationFilterMaxAccuracy { dictionary["locationFilterMaxAccuracy"] = locationFilterMaxAccuracy }
        if let locationFilterMaxSpeed { dictionary["locationFilterMaxSpeed"] = locationFilterMaxSpeed }
        if let locationFilterPolicy { dictionary["locationFilterPolicy"] = locationFilterPolicy }
        if let kalmanProfile { dictionary["kalmanProfile"] = kalmanProfile }
        if let odometerAccuracyThreshold { dictionary["odometerAccuracyThreshold"] = odometerAccuracyThreshold }
        if let disableElasticity { dictionary["disableElasticity"] = disableElasticity }
        if let elasticityMultiplier { dictionary["elasticityMultiplier"] = elasticityMultiplier }
        if let stationaryDesiredAccuracy { dictionary["stationaryDesiredAccuracy"] = stationaryDesiredAccuracy }
        if let stationaryLocationUpdateInterval { dictionary["stationaryLocationUpdateInterval"] = stationaryLocationUpdateInterval }
        if let triggerActivities { dictionary["triggerActivities"] = triggerActivities }
        if let minimumActivityRecognitionConfidence { dictionary["minimumActivityRecognitionConfidence"] = minimumActivityRecognitionConfidence }
        if let activityRecognitionInterval { dictionary["activityRecognitionInterval"] = activityRecognitionInterval }
        if let disableMotionActivityUpdates { dictionary["disableMotionActivityUpdates"] = disableMotionActivityUpdates }
        if let stopTimeout { dictionary["stopTimeout"] = stopTimeout }
        if let showsBackgroundLocationIndicator { dictionary["showsBackgroundLocationIndicator"] = showsBackgroundLocationIndicator }
        if let stationaryRadius { dictionary["stationaryRadius"] = stationaryRadius }
        if let stationaryDistanceFilter { dictionary["stationaryDistanceFilter"] = stationaryDistanceFilter }
        if let preventSuspend { dictionary["preventSuspend"] = preventSuspend }
        if let heartbeatInterval { dictionary["heartbeatInterval"] = heartbeatInterval }
        if let motionTriggerDelay { dictionary["motionTriggerDelay"] = motionTriggerDelay }
        if let locationUpdateInterval { dictionary["locationUpdateInterval"] = locationUpdateInterval }
        if let foregroundService { dictionary["foregroundService"] = foregroundService }
        if let notification { dictionary["notification"] = notification.toDictionary() }
        if let stopOnTerminate { dictionary["stopOnTerminate"] = stopOnTerminate }
        if let startOnBoot { dictionary["startOnBoot"] = startOnBoot }
        if let debug { dictionary["debug"] = debug }
        if let logLevel { dictionary["logLevel"] = logLevel }
        if let logMaxDays { dictionary["logMaxDays"] = logMaxDays }
        if let logUrl {
            dictionary["logUrl"] = (logUrl == Config.clearString) ? NSNull() : logUrl
        }
        if let maxDaysToPersist { dictionary["maxDaysToPersist"] = maxDaysToPersist }
        if let url {
            dictionary["url"] = (url == Config.clearString) ? NSNull() : url
        }
        if let method { dictionary["method"] = method }
        if let headers {
            dictionary["headers"] = (headers == Config.clearDictionary) ? NSNull() : headers
        }
        if let params {
            dictionary["params"] = Config.isClearAnyDictionary(params) ? NSNull() : params
        }
        if let extras {
            dictionary["extras"] = Config.isClearAnyDictionary(extras) ? NSNull() : extras
        }
        if let httpRootProperty { dictionary["httpRootProperty"] = httpRootProperty }
        if let autoSync { dictionary["autoSync"] = autoSync }
        if let disableAutoSyncOnCellular { dictionary["disableAutoSyncOnCellular"] = disableAutoSyncOnCellular }
        if let autoSyncThreshold { dictionary["autoSyncThreshold"] = autoSyncThreshold }
        if let batchSync { dictionary["batchSync"] = batchSync }
        if let maxBatchSize { dictionary["maxBatchSize"] = maxBatchSize }
        if let httpTimeoutMs { dictionary["httpTimeoutMs"] = httpTimeoutMs }
        if let maxRecordsToPersist { dictionary["maxRecordsToPersist"] = maxRecordsToPersist }
        if let authorization {
            dictionary["authorization"] = (authorization.strategy == Config.clearString) ? NSNull() : authorization.toDictionary()
        }
        if let stationaryKeepAlive { dictionary["stationaryKeepAlive"] = stationaryKeepAlive }
        if let diagnosticExtras { dictionary["diagnosticExtras"] = diagnosticExtras }
        if let useSessionEngine { dictionary["useSessionEngine"] = useSessionEngine }
        if let geofenceProximityRadius { dictionary["geofenceProximityRadius"] = geofenceProximityRadius }
        if let maxMonitoredGeofences { dictionary["maxMonitoredGeofences"] = maxMonitoredGeofences }
        if let geofenceInitialTriggerEntry { dictionary["geofenceInitialTriggerEntry"] = geofenceInitialTriggerEntry }

        return dictionary
    }
}

extension Config {
    /// A property equal to this sentinel serialises as `NSNull()` in
    /// `toDictionary()` instead of being omitted — the only way to express
    /// "unset this key" given PATCH semantics (`Config()` with everything
    /// `nil` must change nothing). Wired on `url`, `logUrl`, `headers`,
    /// `params`, `extras`, and (via `AuthorizationConfig.clear`) `authorization`
    /// — the keys the Flutter SDK needed a same-shaped workaround for on
    /// device unlink (empty strings, since Dart's `Config` cannot express a
    /// true clear — see `flutter/lib/src/config.dart` `Config.toMap()`).
    ///
    /// Example: `Config(url: Config.clearString)` clears the upload `url`.
    public static let clearString = "\u{0}__BGEO_CLEAR__"

    /// Sentinel for `[String: String]?` properties (`headers`). See `clearString`.
    public static let clearDictionary: [String: String] = [clearString: clearString]

    /// Sentinel for `[String: Any]?` properties (`params`, `extras`). See `clearString`.
    public static let clearAnyDictionary: [String: Any] = [clearString: clearString]

    fileprivate static func isClearAnyDictionary(_ dictionary: [String: Any]) -> Bool {
        dictionary.count == 1 && (dictionary[clearString] as? String) == clearString
    }
}
