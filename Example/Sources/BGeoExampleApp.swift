// App entry point: wires the SDK end to end before any screen renders.
//
// Ordering mirrors `react-native/example/App.tsx`'s `useEffect` line for
// line: event subscriptions are opened FIRST, then the persisted device link
// is restored, then `ready(config)` brings the engine up. This order matters:
// `EventHub` buffers up to 64 events per event name until a subscriber
// attaches, then LATCHES for that name — one buffered replay, delivered to
// whichever subscriber attaches first, never re-armed. Subscribing after
// `ready()`/`restore()`'s `setConfig` risks losing launch-time events
// (CoreLocation's initial `didChangeAuthorization`, an early
// `providerchange`) if more than 64 arrive first; subscribing before costs
// nothing, since the hub simply queues events for a name with no subscriber
// yet.

import SwiftUI
import BackgroundGeolocation

/// The base config passed to `ready()`, before the user's Settings overrides
/// (`ConfigStore.merged(into:)`) are layered on top. Swift port of
/// `react-native/example/src/configSchema.ts`'s `BASE_CONFIG` — same five
/// keys, same values.
private let baseConfig = Config(
    distanceFilter: 10,
    stopTimeout: 5,
    stopOnTerminate: true,
    startOnBoot: false,
    debug: true,
    // Native logger at INFO for the example app; upload starts once a device
    // link supplies `logUrl` (`DeviceLink`'s `applySdkConfig`).
    logLevel: 3
)

@main
struct BGeoExampleApp: App {
    @StateObject private var appStore: AppStore
    @StateObject private var themeStore: ThemeStore
    @StateObject private var configStore: ConfigStore
    private let deviceLink: DeviceLink
    private let geofences: Geofences

    /// Guards `bootstrap()` against running twice. Unreachable today (one
    /// `WindowGroup`), but `TARGETED_DEVICE_FAMILY: "1,2"` invites iPad, and a
    /// second scene's `.task` re-running `bootstrap()` would re-subscribe
    /// every event (doubling delivery, since `subscribeToEvents()`'s
    /// `Subscription`s are never removed) and call `ready()`/`restore()`
    /// again. `static` so it survives across scenes, which are separate
    /// `WindowGroup` instances within the same process, not separate apps.
    @MainActor private static var hasBootstrapped = false

    init() {
        // `DeviceLink`/`Geofences` need the SAME `AppStore` instance the view
        // hierarchy observes, so it's built here (not via `AppStore()` a
        // second time) and handed to `_appStore`'s `StateObject` wrapper.
        let appStore = AppStore()
        let deviceLink = DeviceLink(store: appStore)
        _appStore = StateObject(wrappedValue: appStore)
        _themeStore = StateObject(wrappedValue: ThemeStore())
        _configStore = StateObject(wrappedValue: ConfigStore())
        self.deviceLink = deviceLink
        self.geofences = Geofences(store: appStore, deviceLink: deviceLink)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appStore: appStore,
                themeStore: themeStore,
                configStore: configStore,
                deviceLink: deviceLink,
                geofences: geofences
            )
            .task { await bootstrap() }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        guard !Self.hasBootstrapped else { return }
        Self.hasBootstrapped = true

        subscribeToEvents()
        _ = await deviceLink.restore()

        let config = configStore.merged(into: baseConfig)
        do {
            let state = try await BackgroundGeolocation.ready(config)
            appStore.setStatus(ready: true, enabled: state.enabled)
            log("ready", "enabled=\(state.enabled) odometer=\(state["odometer"] ?? "nil")", .info)
            await geofences.refresh()
        } catch {
            log("ready", error.localizedDescription, .error)
        }
    }

    // MARK: - Event subscriptions

    private func subscribeToEvents() {
        BackgroundGeolocation.onLocation { location in
            appStore.appendPoint(Point(
                uuid: location.uuid,
                latitude: location.coords.latitude,
                longitude: location.coords.longitude,
                timestamp: location.timestamp,
                accuracy: location.coords.accuracy,
                speed: location.coords.speed,
                heading: location.coords.heading,
                odometer: location.odometer,
                activity: location.activity.type.rawValue,
                isMoving: location.isMoving,
                event: location.event
            ))
            appStore.setStatus(isMoving: location.isMoving, batteryLevel: location.battery.level)
            var data: [String: Any] = [
                "lat": location.coords.latitude,
                "lng": location.coords.longitude,
                "accuracy": location.coords.accuracy,
                "isMoving": location.isMoving,
            ]
            if let extras = location.extras { data["extras"] = extras }
            log(
                "onLocation",
                String(format: "%.6f, %.6f ±%.0fm", location.coords.latitude, location.coords.longitude, location.coords.accuracy),
                data: data,
                .debug
            )
        }

        BackgroundGeolocation.onMotionChange { event in
            appStore.setStatus(isMoving: event.isMoving)
            log("onMotionChange", "isMoving=\(event.isMoving)", .info)
        }

        BackgroundGeolocation.onHeartbeat { _ in
            log("onHeartbeat", nil, .debug)
        }

        BackgroundGeolocation.onProviderChange { event in
            var data: [String: Any] = [
                "status": event.status.rawValue,
                "enabled": event.enabled,
                "gps": event.gps,
                "network": event.network,
            ]
            if let accuracyAuthorization = event.accuracyAuthorization { data["accuracyAuthorization"] = accuracyAuthorization.rawValue }
            log("onProviderChange", "status=\(event.status)", data: data, .warn)
        }

        BackgroundGeolocation.onAuthorization { event in
            let failed = (event["success"] as? Bool) == false
            // The raw event is `{success, accessToken, refreshToken}` — live
            // JWTs. `redactedAuthorizationLogData` strips them to a
            // token-presence signal before this goes anywhere near the Logs
            // screen/`bgeo.db`/`/device/logs`; the real event (with the real
            // tokens) still goes to `persistRotatedTokens` below.
            log("onAuthorization", failed ? "failed" : "refreshed", data: redactedAuthorizationLogData(event), failed ? .error : .info)
            Task { await deviceLink.persistRotatedTokens(event) }
        }

        BackgroundGeolocation.onGeofence { event in
            var data: [String: Any] = ["identifier": event.identifier, "action": event.action.rawValue]
            if let extras = event.extras { data["extras"] = extras }
            log("onGeofence", "\(event.action.rawValue) \(event.identifier)", data: data, .info)
            // Geofence transitions don't ride `onLocation` — append the point
            // here so the map and coordinates table show them (same as
            // React Native's `App.tsx` and the web console).
            appStore.appendPoint(Point(
                uuid: event.location.uuid,
                latitude: event.location.coords.latitude,
                longitude: event.location.coords.longitude,
                timestamp: event.location.timestamp,
                accuracy: event.location.coords.accuracy,
                speed: event.location.coords.speed,
                heading: event.location.coords.heading,
                odometer: event.location.odometer,
                activity: event.location.activity.type.rawValue,
                isMoving: event.location.isMoving,
                event: "geofence",
                geofence: PointGeofence(identifier: event.identifier, action: event.action.rawValue)
            ))
        }

        BackgroundGeolocation.onGeofencesChange { event in
            log("onGeofencesChange", "on=\(event.on.count) off=\(event.off.count)", .debug)
            Task { await geofences.refresh() }
        }

        BackgroundGeolocation.onHttp { event in
            let data: [String: Any] = ["status": event.status, "success": event.success, "responseText": event.responseText]
            log("onHttp", "\(event.status) \(event.success ? "ok" : "fail")", data: data, event.success ? .debug : .warn)
        }

        BackgroundGeolocation.onConnectivityChange { event in
            log("onConnectivityChange", "connected=\(event.connected)", data: ["connected": event.connected], event.connected ? .info : .warn)
        }
    }

    private func log(_ event: String, _ message: String?, data: Any? = nil, _ level: LogLevel) {
        LogUploader.logEvent(event, message: message, data: data, level: level, store: appStore)
    }
}

/// Redacts an `onAuthorization` event (`{success, accessToken, refreshToken}`,
/// per `BGGeoEngine.mm`'s authorization body) down to `success` plus
/// token-presence booleans, for the Logs screen/`bgeo.db`/`/device/logs` —
/// none of which should ever see a live JWT. Free function (not a private
/// method) so it's reachable from tests via `@testable import`.
func redactedAuthorizationLogData(_ event: [String: Any]) -> [String: Any] {
    [
        "success": event["success"] as? Bool ?? false,
        "hasAccessToken": !((event["accessToken"] as? String)?.isEmpty ?? true),
        "hasRefreshToken": !((event["refreshToken"] as? String)?.isEmpty ?? true),
    ]
}
