// Tiny shared store for the example app: structured log lines (same shape as
// /device/logs events), breadcrumb points, the SDK geofence set, engine
// status and the device-link state. `@Published` properties so SwiftUI
// screens can bind directly via `@EnvironmentObject`/`@ObservedObject`.
//
// This is a Swift port of `react-native/example/src/appStore.ts` (the
// cross-client contract); `flutter/example/lib/src/app_store.dart` is the
// same port for Flutter and agrees with every decision made here.

import Foundation
import BackgroundGeolocation

public enum LogLevel: String {
    case verbose, debug, info, warn, error
}

/// Exactly the event shape uploaded to /device/logs — what you see in the
/// app is what the web console shows.
public struct LogLine {
    public var ts: String // ISO
    public var level: LogLevel
    public var event: String
    public var message: String?
    public var data: Any?

    public init(ts: String, level: LogLevel, event: String, message: String? = nil, data: Any? = nil) {
        self.ts = ts
        self.level = level
        self.event = event
        self.message = message
        self.data = data
    }
}

/// Which region fired on an `event:"geofence"` point, and how.
public struct PointGeofence {
    public var identifier: String
    public var action: String?

    public init(identifier: String, action: String? = nil) {
        self.identifier = identifier
        self.action = action
    }
}

public struct Point {
    public var uuid: String?
    public var latitude: Double
    public var longitude: Double
    public var timestamp: String // ISO
    public var accuracy: Double?
    public var speed: Double?
    public var heading: Double?
    public var odometer: Double? // metres
    public var activity: String?
    public var isMoving: Bool?
    public var event: String?
    public var geofence: PointGeofence?

    public init(
        uuid: String? = nil,
        latitude: Double,
        longitude: Double,
        timestamp: String,
        accuracy: Double? = nil,
        speed: Double? = nil,
        heading: Double? = nil,
        odometer: Double? = nil,
        activity: String? = nil,
        isMoving: Bool? = nil,
        event: String? = nil,
        geofence: PointGeofence? = nil
    ) {
        self.uuid = uuid
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.speed = speed
        self.heading = heading
        self.odometer = odometer
        self.activity = activity
        self.isMoving = isMoving
        self.event = event
        self.geofence = geofence
    }
}

public struct LinkState {
    public var serverUrl: String = "https://app.bgeo.dev"
    public var linked = false
    public var deviceId: String?

    public init(serverUrl: String = "https://app.bgeo.dev", linked: Bool = false, deviceId: String? = nil) {
        self.serverUrl = serverUrl
        self.linked = linked
        self.deviceId = deviceId
    }
}

public struct EngineStatus {
    public var ready = false
    public var enabled = false
    public var isMoving = false
    public var batteryLevel: Double?

    public init(ready: Bool = false, enabled: Bool = false, isMoving: Bool = false, batteryLevel: Double? = nil) {
        self.ready = ready
        self.enabled = enabled
        self.isMoving = isMoving
        self.batteryLevel = batteryLevel
    }
}

@MainActor
public final class AppStore: ObservableObject {
    /// `appStore.ts`: `logs: [...state.logs.slice(-999), line]` — 999 kept + the
    /// new one = 1000 max.
    public static let maxLogs = 1000
    /// `appStore.ts`: `points: [...state.points.slice(-1999), point]` — 1999
    /// kept + the new one = 2000 max.
    public static let maxPoints = 2000

    @Published public private(set) var logs: [LogLine] = []
    @Published public private(set) var points: [Point] = []
    @Published public private(set) var geofences: [Geofence] = []
    @Published public private(set) var link = LinkState()
    @Published public private(set) var status = EngineStatus()

    public init() {}

    public func appendLog(_ line: LogLine) {
        logs.append(line)
        if logs.count > Self.maxLogs {
            logs.removeFirst(logs.count - Self.maxLogs)
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }

    public func appendPoint(_ point: Point) {
        points.append(point)
        if points.count > Self.maxPoints {
            points.removeFirst(points.count - Self.maxPoints)
        }
    }

    /// `appStore.ts`'s `clearTrack` — not in the task brief's mutator list, but
    /// present in `appStore.ts` and used by `SettingsScreen.tsx` to clear the
    /// breadcrumb buffer. Included for RN parity; see the task report.
    public func clearTrack() {
        points.removeAll()
    }

    public func setGeofences(_ geofences: [Geofence]) {
        self.geofences = geofences
    }

    /// Partial update: only the parameters passed override the current link
    /// state (mirrors `appStore.ts`'s `setLink(link: Partial<LinkState>)`).
    /// `deviceId` needs an explicit clear flag, not a plain optional, because
    /// Swift can't distinguish "omitted" from "passed nil" through a single
    /// `String?` parameter — same reasoning as `app_store.dart`'s `LinkState.copyWith`.
    public func setLink(serverUrl: String? = nil, linked: Bool? = nil, deviceId: String? = nil, clearDeviceId: Bool = false) {
        var next = link
        if let serverUrl { next.serverUrl = serverUrl }
        if let linked { next.linked = linked }
        if clearDeviceId {
            next.deviceId = nil
        } else if let deviceId {
            next.deviceId = deviceId
        }
        link = next
    }

    /// Partial update, same shape as `setStatus(status: Partial<EngineStatus>)`.
    public func setStatus(ready: Bool? = nil, enabled: Bool? = nil, isMoving: Bool? = nil, batteryLevel: Double? = nil) {
        var next = status
        if let ready { next.ready = ready }
        if let enabled { next.enabled = enabled }
        if let isMoving { next.isMoving = isMoving }
        if let batteryLevel { next.batteryLevel = batteryLevel }
        status = next
    }
}
