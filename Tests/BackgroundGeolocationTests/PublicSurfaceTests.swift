import XCTest
import BackgroundGeolocation

/// A compile-time guard over the published API surface.
///
/// Deliberately **not** `@testable import` — every other test file in this
/// target uses `@testable import BackgroundGeolocation` to reach `Engine`,
/// `FakeEngine`, and the `BackgroundGeolocation.engine`/`.hub` seams. This
/// file imports the package the way a consuming app would, so if a later
/// change accidentally demotes a public initialiser or property to
/// `internal`, this file stops COMPILING rather than merely failing an
/// assertion. It intentionally does not construct `Subscription` directly —
/// its initialiser is internal on purpose (see `EventHub.swift`), so there
/// is no public way to do that, and that absence is itself part of what this
/// file proves by continuing to compile without it.
///
/// Mechanical by design: every public model and options/config struct is
/// built through its public initialiser and every public stored/computed
/// property is read. Nothing here talks to the engine, so there is no
/// `@MainActor` hop and no risk of touching the real `BGGeoCore` singleton.
final class PublicSurfaceTests: XCTestCase {

    // MARK: - Constants

    func testConstantsExposeExpectedRawValues() {
        XCTAssertEqual(DesiredAccuracy.navigation.rawValue, -2)
        XCTAssertEqual(DesiredAccuracy.high.rawValue, -1)
        XCTAssertEqual(DesiredAccuracy.medium.rawValue, 10)
        XCTAssertEqual(DesiredAccuracy.low.rawValue, 100)
        XCTAssertEqual(DesiredAccuracy.veryLow.rawValue, 1000)
        XCTAssertEqual(DesiredAccuracy.lowest.rawValue, 3000)

        XCTAssertEqual(LogLevel.off.rawValue, 0)
        XCTAssertEqual(LogLevel.error.rawValue, 1)
        XCTAssertEqual(LogLevel.warning.rawValue, 2)
        XCTAssertEqual(LogLevel.info.rawValue, 3)
        XCTAssertEqual(LogLevel.debug.rawValue, 4)
        XCTAssertEqual(LogLevel.verbose.rawValue, 5)

        XCTAssertEqual(AuthorizationStatus.notDetermined.rawValue, 0)
        XCTAssertEqual(AuthorizationStatus.restricted.rawValue, 1)
        XCTAssertEqual(AuthorizationStatus.denied.rawValue, 2)
        XCTAssertEqual(AuthorizationStatus.always.rawValue, 3)
        XCTAssertEqual(AuthorizationStatus.whenInUse.rawValue, 4)

        XCTAssertEqual(AccuracyAuthorization.full.rawValue, 0)
        XCTAssertEqual(AccuracyAuthorization.reduced.rawValue, 1)

        XCTAssertEqual(ActivityType.still.rawValue, "still")
        XCTAssertEqual(ActivityType.onFoot.rawValue, "on_foot")
        XCTAssertEqual(ActivityType.walking.rawValue, "walking")
        XCTAssertEqual(ActivityType.running.rawValue, "running")
        XCTAssertEqual(ActivityType.onBicycle.rawValue, "on_bicycle")
        XCTAssertEqual(ActivityType.inVehicle.rawValue, "in_vehicle")
        XCTAssertEqual(ActivityType.unknown.rawValue, "unknown")

        XCTAssertEqual(GeofenceAction.enter.rawValue, "ENTER")
        XCTAssertEqual(GeofenceAction.exit.rawValue, "EXIT")
        XCTAssertEqual(GeofenceAction.dwell.rawValue, "DWELL")
    }

    // MARK: - BGeoError

    func testBGeoErrorPublicInitAndAccessors() {
        let error = BGeoError(code: "LICENSE_INVALID", message: "bad key")
        XCTAssertEqual(error.code, "LICENSE_INVALID")
        XCTAssertEqual(error.message, "bad key")
        XCTAssertEqual(error.errorDescription, "LICENSE_INVALID: bad key")
        XCTAssertEqual(error, BGeoError.licenseInvalid(message: "bad key"))

        let unknown = BGeoError(code: "SOMETHING_NEW", message: "m")
        XCTAssertEqual(unknown, BGeoError.unknown(code: "SOMETHING_NEW", message: "m"))
    }

    // MARK: - Models decoded from engine dictionaries

    private func sampleCoordsDictionary() -> [String: Any] {
        [
            "latitude": 52.2297, "longitude": 21.0122, "accuracy": 5.0,
            "altitude": 100.0, "altitude_accuracy": 3.0,
            "speed": 1.5, "speed_accuracy": 0.5,
            "heading": 90.0, "heading_accuracy": 2.0,
            "ellipsoidal_altitude": 110.0,
        ]
    }

    func testCoordsPublicInit() {
        let coords = Coords(dictionary: sampleCoordsDictionary())
        XCTAssertNotNil(coords)
        XCTAssertEqual(coords?.latitude, 52.2297)
        XCTAssertEqual(coords?.longitude, 21.0122)
        XCTAssertEqual(coords?.accuracy, 5.0)
        XCTAssertEqual(coords?.altitude, 100.0)
        XCTAssertEqual(coords?.altitudeAccuracy, 3.0)
        XCTAssertEqual(coords?.speed, 1.5)
        XCTAssertEqual(coords?.speedAccuracy, 0.5)
        XCTAssertEqual(coords?.heading, 90.0)
        XCTAssertEqual(coords?.headingAccuracy, 2.0)
        XCTAssertEqual(coords?.ellipsoidalAltitude, 110.0)
    }

    func testMotionActivityPublicInit() {
        let activity = MotionActivity(dictionary: ["type": "on_foot", "confidence": 80])
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, .onFoot)
        XCTAssertEqual(activity?.confidence, 80)
    }

    func testBatteryPublicInit() {
        let battery = Battery(dictionary: ["level": 0.75, "is_charging": true])
        XCTAssertNotNil(battery)
        XCTAssertEqual(battery?.level, 0.75)
        XCTAssertEqual(battery?.isCharging, true)
    }

    private func sampleLocationDictionary(extra: [String: Any] = [:]) -> [String: Any] {
        var dictionary: [String: Any] = [
            "uuid": "abc-123",
            "timestamp": "2026-07-29T10:00:00.000Z",
            "age": 1.0,
            "odometer": 1234.5,
            "is_moving": true,
            "sample": false,
            "event": "motionchange",
            "coords": sampleCoordsDictionary(),
            "activity": ["type": "in_vehicle", "confidence": 88],
            "battery": ["level": 0.62, "is_charging": false],
            "extras": ["watch": true],
        ]
        dictionary.merge(extra) { _, new in new }
        return dictionary
    }

    func testLocationPublicInit() {
        let location = Location(dictionary: sampleLocationDictionary())
        XCTAssertNotNil(location)
        XCTAssertEqual(location?.uuid, "abc-123")
        XCTAssertEqual(location?.timestamp, "2026-07-29T10:00:00.000Z")
        XCTAssertEqual(location?.age, 1.0)
        XCTAssertEqual(location?.odometer, 1234.5)
        XCTAssertEqual(location?.isMoving, true)
        XCTAssertEqual(location?.sample, false)
        XCTAssertEqual(location?.event, "motionchange")
        XCTAssertEqual(location?.coords.latitude, 52.2297)
        XCTAssertEqual(location?.activity.type, .inVehicle)
        XCTAssertEqual(location?.battery.level, 0.62)
        XCTAssertEqual(location?.extras?["watch"] as? Bool, true)
    }

    func testGeofencePublicInits() {
        let geofence = Geofence(
            identifier: "home",
            radius: 150,
            latitude: 52.0,
            longitude: 21.0,
            notifyOnEntry: true,
            notifyOnExit: true,
            notifyOnDwell: false,
            loiteringDelay: 30_000,
            extras: ["kind": "home"]
        )
        XCTAssertEqual(geofence.identifier, "home")
        XCTAssertEqual(geofence.radius, 150)
        XCTAssertEqual(geofence.latitude, 52.0)
        XCTAssertEqual(geofence.longitude, 21.0)
        XCTAssertEqual(geofence.notifyOnEntry, true)
        XCTAssertEqual(geofence.notifyOnExit, true)
        XCTAssertEqual(geofence.notifyOnDwell, false)
        XCTAssertEqual(geofence.loiteringDelay, 30_000)
        XCTAssertEqual(geofence.extras?["kind"] as? String, "home")

        let dictionary = geofence.toDictionary()
        let decoded = Geofence(dictionary: dictionary)
        XCTAssertEqual(decoded?.identifier, "home")
    }

    func testLogEntryPublicInit() {
        let entry = LogEntry(dictionary: [
            "ts": "2026-07-29T10:00:00.000Z",
            "level": 3,
            "src": "native",
            "event": "app",
            "message": "hello",
            "data": "{}",
        ])
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.ts, "2026-07-29T10:00:00.000Z")
        XCTAssertEqual(entry?.level, 3)
        XCTAssertEqual(entry?.src, "native")
        XCTAssertEqual(entry?.event, "app")
        XCTAssertEqual(entry?.message, "hello")
        XCTAssertEqual(entry?.data, "{}")
    }

    func testProviderStateAndItsTypealiasEventPublicInit() {
        let providerState = ProviderState(dictionary: [
            "status": 3, "enabled": true, "gps": true, "network": false,
            "accuracyAuthorization": 1,
        ])
        XCTAssertEqual(providerState.status, .always)
        XCTAssertEqual(providerState.enabled, true)
        XCTAssertEqual(providerState.gps, true)
        XCTAssertEqual(providerState.network, false)
        XCTAssertEqual(providerState.accuracyAuthorization, .reduced)

        // ProviderChangeEvent is a public typealias for ProviderState.
        let changeEvent: ProviderChangeEvent = ProviderState(dictionary: [:])
        XCTAssertEqual(changeEvent.status, .notDetermined)
    }

    func testMotionChangeEventPublicInit() {
        let withLocation = MotionChangeEvent(dictionary: [
            "isMoving": true,
            "location": sampleLocationDictionary(),
        ])
        XCTAssertEqual(withLocation?.isMoving, true)
        XCTAssertNotNil(withLocation?.location)

        let withoutLocation = MotionChangeEvent(dictionary: ["isMoving": false])
        XCTAssertEqual(withoutLocation?.isMoving, false)
        XCTAssertNil(withoutLocation?.location)
    }

    func testGeofenceEventPublicInit() {
        let event = GeofenceEvent(dictionary: [
            "identifier": "home",
            "action": "DWELL",
            "location": sampleLocationDictionary(),
            "extras": ["source": "test"],
        ])
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.identifier, "home")
        XCTAssertEqual(event?.action, .dwell)
        XCTAssertNotNil(event?.location)
        XCTAssertEqual(event?.extras?["source"] as? String, "test")
    }

    func testGeofencesChangeEventPublicInit() {
        let onGeofence = Geofence(identifier: "on", radius: 100, latitude: 1, longitude: 1)
        let offGeofence = Geofence(identifier: "off", radius: 100, latitude: 2, longitude: 2)
        let event = GeofencesChangeEvent(dictionary: [
            "on": [onGeofence.toDictionary()],
            "off": [offGeofence.toDictionary()],
        ])
        XCTAssertEqual(event?.on.map(\.identifier), ["on"])
        XCTAssertEqual(event?.off.map(\.identifier), ["off"])
    }

    func testHttpEventPublicInit() {
        let event = HttpEvent(dictionary: ["success": true, "status": 200, "responseText": "ok"])
        XCTAssertEqual(event?.success, true)
        XCTAssertEqual(event?.status, 200)
        XCTAssertEqual(event?.responseText, "ok")
    }

    func testConnectivityChangeEventPublicInit() {
        let event = ConnectivityChangeEvent(dictionary: ["connected": true])
        XCTAssertEqual(event?.connected, true)
    }

    func testHeartbeatEventPublicInit() {
        let event = HeartbeatEvent(dictionary: ["foo": "bar"])
        XCTAssertEqual(event?.raw["foo"] as? String, "bar")
    }

    func testStatePublicInitAndSubscript() {
        let state = State(dictionary: ["enabled": true, "odometer": 42.0])
        XCTAssertEqual(state.enabled, true)
        XCTAssertEqual(state.raw["odometer"] as? Double, 42.0)
        XCTAssertEqual(state["odometer"] as? Double, 42.0)
    }

    // MARK: - Config and its nested config structs

    func testNotificationConfigPublicInit() {
        let notification = NotificationConfig(
            title: "Tracking",
            text: "Recording your trip",
            channelId: "bgeo",
            channelName: "Background Geolocation",
            smallIcon: "drawable/ic_notify",
            color: "#FF0000",
            priority: 0
        )
        XCTAssertEqual(notification.title, "Tracking")
        XCTAssertEqual(notification.text, "Recording your trip")
        XCTAssertEqual(notification.channelId, "bgeo")
        XCTAssertEqual(notification.channelName, "Background Geolocation")
        XCTAssertEqual(notification.smallIcon, "drawable/ic_notify")
        XCTAssertEqual(notification.color, "#FF0000")
        XCTAssertEqual(notification.priority, 0)
        XCTAssertEqual(notification.toDictionary()["title"] as? String, "Tracking")
    }

    func testAuthorizationConfigPublicInit() {
        let authorization = AuthorizationConfig(
            strategy: "jwt",
            accessToken: "access",
            refreshToken: "refresh",
            refreshUrl: "https://example.com/refresh",
            refreshPayload: ["refresh_token": "{refreshToken}"],
            refreshHeaders: ["Content-Type": "application/json"]
        )
        XCTAssertEqual(authorization.strategy, "jwt")
        XCTAssertEqual(authorization.accessToken, "access")
        XCTAssertEqual(authorization.refreshToken, "refresh")
        XCTAssertEqual(authorization.refreshUrl, "https://example.com/refresh")
        XCTAssertEqual(authorization.refreshPayload?["refresh_token"] as? String, "{refreshToken}")
        XCTAssertEqual(authorization.refreshHeaders?["Content-Type"], "application/json")
        XCTAssertEqual(authorization.toDictionary()["strategy"] as? String, "jwt")

        // The clear-sentinel escape hatch is itself public API.
        XCTAssertEqual(AuthorizationConfig.clear.strategy, Config.clearString)
    }

    func testConfigPublicInitReadsEveryPropertyAndSerialises() {
        let config = Config(
            locationAuthorizationRequest: "Always",
            locationAuthorizationAlert: ["titleWhenNotEnabled": "Enable location"],
            disableLocationAuthorizationAlert: false,
            backgroundPermissionRationale: ["title": "Background access"],
            desiredAccuracy: DesiredAccuracy.high.rawValue,
            distanceFilter: 10,
            disableLocationFilter: false,
            locationFilterMaxAccuracy: 100,
            locationFilterMaxSpeed: 60,
            locationFilterPolicy: "Conservative",
            kalmanProfile: "DEFAULT",
            odometerAccuracyThreshold: 0,
            disableElasticity: false,
            elasticityMultiplier: 1.0,
            stationaryDesiredAccuracy: "BALANCED",
            stationaryLocationUpdateInterval: 30_000,
            triggerActivities: "in_vehicle,on_bicycle,walking,running,on_foot",
            minimumActivityRecognitionConfidence: 50,
            activityRecognitionInterval: 10_000,
            disableMotionActivityUpdates: false,
            stopTimeout: 5,
            showsBackgroundLocationIndicator: false,
            stationaryRadius: 25,
            stationaryDistanceFilter: 25,
            preventSuspend: false,
            heartbeatInterval: 60,
            motionTriggerDelay: 0,
            locationUpdateInterval: 1_000,
            foregroundService: true,
            notification: NotificationConfig(title: "Tracking"),
            stopOnTerminate: false,
            startOnBoot: true,
            debug: false,
            logLevel: LogLevel.info.rawValue,
            logMaxDays: 3,
            logUrl: "https://example.com/logs",
            maxDaysToPersist: 7,
            url: "https://example.com/locations",
            method: "POST",
            headers: ["Authorization": "Bearer token"],
            params: ["deviceId": "abc"],
            extras: ["source": "sdk"],
            httpRootProperty: "location",
            autoSync: true,
            disableAutoSyncOnCellular: false,
            autoSyncThreshold: 5,
            batchSync: false,
            maxBatchSize: 50,
            httpTimeoutMs: 60_000,
            maxRecordsToPersist: -1,
            authorization: AuthorizationConfig(strategy: "jwt"),
            stationaryKeepAlive: true,
            diagnosticExtras: false,
            useSessionEngine: true,
            geofenceProximityRadius: 1_000,
            maxMonitoredGeofences: -1,
            geofenceInitialTriggerEntry: true
        )

        XCTAssertEqual(config.locationAuthorizationRequest, "Always")
        XCTAssertEqual(config.locationAuthorizationAlert?["titleWhenNotEnabled"], "Enable location")
        XCTAssertEqual(config.disableLocationAuthorizationAlert, false)
        XCTAssertEqual(config.backgroundPermissionRationale?["title"], "Background access")
        XCTAssertEqual(config.desiredAccuracy, DesiredAccuracy.high.rawValue)
        XCTAssertEqual(config.distanceFilter, 10)
        XCTAssertEqual(config.disableLocationFilter, false)
        XCTAssertEqual(config.locationFilterMaxAccuracy, 100)
        XCTAssertEqual(config.locationFilterMaxSpeed, 60)
        XCTAssertEqual(config.locationFilterPolicy, "Conservative")
        XCTAssertEqual(config.kalmanProfile, "DEFAULT")
        XCTAssertEqual(config.odometerAccuracyThreshold, 0)
        XCTAssertEqual(config.disableElasticity, false)
        XCTAssertEqual(config.elasticityMultiplier, 1.0)
        XCTAssertEqual(config.stationaryDesiredAccuracy, "BALANCED")
        XCTAssertEqual(config.stationaryLocationUpdateInterval, 30_000)
        XCTAssertEqual(config.triggerActivities, "in_vehicle,on_bicycle,walking,running,on_foot")
        XCTAssertEqual(config.minimumActivityRecognitionConfidence, 50)
        XCTAssertEqual(config.activityRecognitionInterval, 10_000)
        XCTAssertEqual(config.disableMotionActivityUpdates, false)
        XCTAssertEqual(config.stopTimeout, 5)
        XCTAssertEqual(config.showsBackgroundLocationIndicator, false)
        XCTAssertEqual(config.stationaryRadius, 25)
        XCTAssertEqual(config.stationaryDistanceFilter, 25)
        XCTAssertEqual(config.preventSuspend, false)
        XCTAssertEqual(config.heartbeatInterval, 60)
        XCTAssertEqual(config.motionTriggerDelay, 0)
        XCTAssertEqual(config.locationUpdateInterval, 1_000)
        XCTAssertEqual(config.foregroundService, true)
        XCTAssertEqual(config.notification?.title, "Tracking")
        XCTAssertEqual(config.stopOnTerminate, false)
        XCTAssertEqual(config.startOnBoot, true)
        XCTAssertEqual(config.debug, false)
        XCTAssertEqual(config.logLevel, LogLevel.info.rawValue)
        XCTAssertEqual(config.logMaxDays, 3)
        XCTAssertEqual(config.logUrl, "https://example.com/logs")
        XCTAssertEqual(config.maxDaysToPersist, 7)
        XCTAssertEqual(config.url, "https://example.com/locations")
        XCTAssertEqual(config.method, "POST")
        XCTAssertEqual(config.headers?["Authorization"], "Bearer token")
        XCTAssertEqual(config.params?["deviceId"] as? String, "abc")
        XCTAssertEqual(config.extras?["source"] as? String, "sdk")
        XCTAssertEqual(config.httpRootProperty, "location")
        XCTAssertEqual(config.autoSync, true)
        XCTAssertEqual(config.disableAutoSyncOnCellular, false)
        XCTAssertEqual(config.autoSyncThreshold, 5)
        XCTAssertEqual(config.batchSync, false)
        XCTAssertEqual(config.maxBatchSize, 50)
        XCTAssertEqual(config.httpTimeoutMs, 60_000)
        XCTAssertEqual(config.maxRecordsToPersist, -1)
        XCTAssertEqual(config.authorization?.strategy, "jwt")
        XCTAssertEqual(config.stationaryKeepAlive, true)
        XCTAssertEqual(config.diagnosticExtras, false)
        XCTAssertEqual(config.useSessionEngine, true)
        XCTAssertEqual(config.geofenceProximityRadius, 1_000)
        XCTAssertEqual(config.maxMonitoredGeofences, -1)
        XCTAssertEqual(config.geofenceInitialTriggerEntry, true)

        let dictionary = config.toDictionary()
        XCTAssertEqual(dictionary["url"] as? String, "https://example.com/locations")
        XCTAssertEqual(dictionary["desiredAccuracy"] as? Int, DesiredAccuracy.high.rawValue)

        // An untouched Config() is the PATCH no-op contract this whole type
        // depends on: it must serialise to an empty dictionary.
        XCTAssertTrue(Config().toDictionary().isEmpty)
    }

    func testConfigClearSentinelsArePublic() {
        XCTAssertFalse(Config.clearString.isEmpty)
        XCTAssertEqual(Config.clearDictionary[Config.clearString], Config.clearString)
        XCTAssertEqual(Config.clearAnyDictionary[Config.clearString] as? String, Config.clearString)

        let cleared = Config(logUrl: Config.clearString, url: Config.clearString)
        XCTAssertTrue(cleared.toDictionary()["logUrl"] is NSNull)
        XCTAssertTrue(cleared.toDictionary()["url"] is NSNull)
    }

    // MARK: - Call options structs

    func testCurrentPositionOptionsPublicInit() {
        let options = CurrentPositionOptions(
            persist: true,
            samples: 3,
            timeout: 30,
            maximumAge: 5_000,
            desiredAccuracy: DesiredAccuracy.high.rawValue,
            extras: ["reason": "test"]
        )
        XCTAssertEqual(options.persist, true)
        XCTAssertEqual(options.samples, 3)
        XCTAssertEqual(options.timeout, 30)
        XCTAssertEqual(options.maximumAge, 5_000)
        XCTAssertEqual(options.desiredAccuracy, DesiredAccuracy.high.rawValue)
        XCTAssertEqual(options.extras?["reason"] as? String, "test")
    }

    func testWatchPositionOptionsPublicInit() {
        let options = WatchPositionOptions(
            interval: 1_000,
            desiredAccuracy: DesiredAccuracy.medium.rawValue,
            persist: false,
            extras: ["reason": "watch"]
        )
        XCTAssertEqual(options.interval, 1_000)
        XCTAssertEqual(options.desiredAccuracy, DesiredAccuracy.medium.rawValue)
        XCTAssertEqual(options.persist, false)
        XCTAssertEqual(options.extras?["reason"] as? String, "watch")
    }
}
