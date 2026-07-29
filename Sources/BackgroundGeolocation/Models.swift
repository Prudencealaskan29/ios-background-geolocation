import Foundation

/// Typed models decoded from the engine's `[String: Any]` dictionary payloads.
///
/// Field names and optionality follow `react-native/src/types.ts` (the
/// cross-SDK source of truth). Failable initialisers return `nil` when a
/// REQUIRED field is missing or the wrong type; optional fields simply stay
/// `nil`. Nothing here force-unwraps — this decoder runs on data from a
/// background service in a shipped app and must never crash on a malformed
/// payload.

public struct Coords {
    public let latitude: Double
    public let longitude: Double
    public let accuracy: Double
    public let altitude: Double?
    public let altitudeAccuracy: Double?
    public let speed: Double?
    public let speedAccuracy: Double?
    public let heading: Double?
    public let headingAccuracy: Double?
    public let ellipsoidalAltitude: Double?

    public init?(dictionary: [String: Any]) {
        guard let latitude = dictionary.double("latitude"),
              let longitude = dictionary.double("longitude"),
              let accuracy = dictionary.double("accuracy") else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.altitude = dictionary.double("altitude")
        self.altitudeAccuracy = dictionary.double("altitude_accuracy")
        self.speed = dictionary.double("speed")
        self.speedAccuracy = dictionary.double("speed_accuracy")
        self.heading = dictionary.double("heading")
        self.headingAccuracy = dictionary.double("heading_accuracy")
        self.ellipsoidalAltitude = dictionary.double("ellipsoidal_altitude")
    }
}

public struct MotionActivity {
    public let type: ActivityType
    public let confidence: Int

    public init?(dictionary: [String: Any]) {
        guard let typeString = dictionary.string("type"),
              let confidence = dictionary.int("confidence") else {
            return nil
        }
        // Unknown/future activity names fall back to `.unknown` rather than
        // failing the whole decode — the engine may add activity types.
        self.type = ActivityType(rawValue: typeString) ?? .unknown
        self.confidence = confidence
    }
}

public struct Battery {
    public let level: Double
    public let isCharging: Bool

    public init?(dictionary: [String: Any]) {
        guard let level = dictionary.double("level"),
              let isCharging = dictionary.bool("is_charging") else {
            return nil
        }
        self.level = level
        self.isCharging = isCharging
    }
}

public struct Location {
    public let uuid: String
    public let timestamp: String
    public let age: Double?
    public let odometer: Double
    public let coords: Coords
    public let activity: MotionActivity
    public let battery: Battery
    public let isMoving: Bool
    public let sample: Bool?
    public let event: String?
    public let extras: [String: Any]?

    public init?(dictionary: [String: Any]) {
        guard let uuid = dictionary.string("uuid"),
              let timestamp = dictionary.string("timestamp"),
              let odometer = dictionary.double("odometer"),
              let coordsDictionary = dictionary.dictionary("coords"),
              let coords = Coords(dictionary: coordsDictionary),
              let activityDictionary = dictionary.dictionary("activity"),
              let activity = MotionActivity(dictionary: activityDictionary),
              let batteryDictionary = dictionary.dictionary("battery"),
              let battery = Battery(dictionary: batteryDictionary),
              let isMoving = dictionary.bool("is_moving") else {
            return nil
        }
        self.uuid = uuid
        self.timestamp = timestamp
        self.age = dictionary.double("age")
        self.odometer = odometer
        self.coords = coords
        self.activity = activity
        self.battery = battery
        self.isMoving = isMoving
        self.sample = dictionary.bool("sample")
        self.event = dictionary.string("event")
        self.extras = dictionary.dictionary("extras")
    }
}

public struct Geofence {
    public let identifier: String
    public let radius: Double
    public let latitude: Double
    public let longitude: Double
    public let notifyOnEntry: Bool?
    public let notifyOnExit: Bool?
    public let notifyOnDwell: Bool?
    public let loiteringDelay: Double?
    public let extras: [String: Any]?

    public init(
        identifier: String,
        radius: Double,
        latitude: Double,
        longitude: Double,
        notifyOnEntry: Bool? = nil,
        notifyOnExit: Bool? = nil,
        notifyOnDwell: Bool? = nil,
        loiteringDelay: Double? = nil,
        extras: [String: Any]? = nil
    ) {
        self.identifier = identifier
        self.radius = radius
        self.latitude = latitude
        self.longitude = longitude
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.notifyOnDwell = notifyOnDwell
        self.loiteringDelay = loiteringDelay
        self.extras = extras
    }

    public init?(dictionary: [String: Any]) {
        guard let identifier = dictionary.string("identifier"),
              let radius = dictionary.double("radius"),
              let latitude = dictionary.double("latitude"),
              let longitude = dictionary.double("longitude") else {
            return nil
        }
        self.identifier = identifier
        self.radius = radius
        self.latitude = latitude
        self.longitude = longitude
        self.notifyOnEntry = dictionary.bool("notifyOnEntry")
        self.notifyOnExit = dictionary.bool("notifyOnExit")
        self.notifyOnDwell = dictionary.bool("notifyOnDwell")
        self.loiteringDelay = dictionary.double("loiteringDelay")
        self.extras = dictionary.dictionary("extras")
    }

    /// Round-trips through `init?(dictionary:)` — used both to send a
    /// geofence into the engine and to decode one back out of it.
    public func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "identifier": identifier,
            "radius": radius,
            "latitude": latitude,
            "longitude": longitude,
        ]
        if let notifyOnEntry { dictionary["notifyOnEntry"] = notifyOnEntry }
        if let notifyOnExit { dictionary["notifyOnExit"] = notifyOnExit }
        if let notifyOnDwell { dictionary["notifyOnDwell"] = notifyOnDwell }
        if let loiteringDelay { dictionary["loiteringDelay"] = loiteringDelay }
        if let extras { dictionary["extras"] = extras }
        return dictionary
    }
}

public struct LogEntry {
    public let ts: String
    public let level: Int
    public let src: String
    public let event: String
    public let message: String?
    public let data: String?

    public init?(dictionary: [String: Any]) {
        guard let ts = dictionary.string("ts"),
              let level = dictionary.int("level"),
              let src = dictionary.string("src"),
              let event = dictionary.string("event") else {
            return nil
        }
        self.ts = ts
        self.level = level
        self.src = src
        self.event = event
        self.message = dictionary.string("message")
        self.data = dictionary.string("data")
    }
}

public struct ProviderState {
    public let status: AuthorizationStatus
    public let enabled: Bool
    public let gps: Bool
    public let network: Bool
    public let accuracyAuthorization: AccuracyAuthorization?

    public init?(dictionary: [String: Any]) {
        guard let statusValue = dictionary.int("status"),
              let status = AuthorizationStatus(rawValue: statusValue),
              let enabled = dictionary.bool("enabled"),
              let gps = dictionary.bool("gps"),
              let network = dictionary.bool("network") else {
            return nil
        }
        self.status = status
        self.enabled = enabled
        self.gps = gps
        self.network = network
        if let accuracyAuthorizationValue = dictionary.int("accuracyAuthorization") {
            self.accuracyAuthorization = AccuracyAuthorization(rawValue: accuracyAuthorizationValue)
        } else {
            self.accuracyAuthorization = nil
        }
    }
}

/// `onProviderChange` fires the identical shape `getProviderState()` returns
/// (`types.ts` only names the event `ProviderChangeEvent`; the query-side
/// type doesn't have its own interface there) — same fields, same decode.
public typealias ProviderChangeEvent = ProviderState

public struct MotionChangeEvent {
    public let isMoving: Bool
    public let location: Location?

    public init?(dictionary: [String: Any]) {
        guard let isMoving = dictionary.bool("isMoving") else {
            return nil
        }
        self.isMoving = isMoving
        // `location` is absent on Android and `NSNull` on iOS for the first
        // motionchange of a tracking session. Both fail the `[String: Any]`
        // cast below and fall through to `nil` without crashing.
        if let locationDictionary = dictionary["location"] as? [String: Any] {
            self.location = Location(dictionary: locationDictionary)
        } else {
            self.location = nil
        }
    }
}

public enum GeofenceAction: String {
    case enter = "ENTER"
    case exit = "EXIT"
    case dwell = "DWELL"
}

public struct GeofenceEvent {
    public let identifier: String
    public let action: GeofenceAction
    public let location: Location
    public let extras: [String: Any]?

    public init?(dictionary: [String: Any]) {
        guard let identifier = dictionary.string("identifier"),
              let actionString = dictionary.string("action"),
              let action = GeofenceAction(rawValue: actionString),
              let locationDictionary = dictionary.dictionary("location"),
              let location = Location(dictionary: locationDictionary) else {
            return nil
        }
        self.identifier = identifier
        self.action = action
        self.location = location
        self.extras = dictionary.dictionary("extras")
    }
}

public struct GeofencesChangeEvent {
    public let on: [Geofence]
    public let off: [Geofence]

    public init?(dictionary: [String: Any]) {
        guard let onArray = dictionary["on"] as? [[String: Any]],
              let offArray = dictionary["off"] as? [[String: Any]] else {
            return nil
        }
        self.on = onArray.compactMap { Geofence(dictionary: $0) }
        self.off = offArray.compactMap { Geofence(dictionary: $0) }
    }
}

/// Fate of one location-sync HTTP request.
public struct HttpEvent {
    public let success: Bool
    public let status: Int
    public let responseText: String

    public init?(dictionary: [String: Any]) {
        guard let success = dictionary.bool("success"),
              let status = dictionary.int("status"),
              let responseText = dictionary.string("responseText") else {
            return nil
        }
        self.success = success
        self.status = status
        self.responseText = responseText
    }
}

public struct ConnectivityChangeEvent {
    public let connected: Bool

    public init?(dictionary: [String: Any]) {
        guard let connected = dictionary.bool("connected") else {
            return nil
        }
        self.connected = connected
    }
}

public struct HeartbeatEvent {
    public let raw: [String: Any]

    public init?(dictionary: [String: Any]) {
        self.raw = dictionary
    }
}

/// The engine reports ~20 diagnostic keys alongside `enabled` and they change
/// between engine versions (new counters, renamed fields). Keeping the raw
/// dictionary here — rather than a closed struct with a field per key — means
/// a new engine release can't break this facade; callers reach diagnostics
/// through the subscript.
public struct State {
    public let enabled: Bool
    public let raw: [String: Any]

    public init?(dictionary: [String: Any]) {
        guard let enabled = dictionary.bool("enabled") else {
            return nil
        }
        self.enabled = enabled
        self.raw = dictionary
    }

    public subscript(key: String) -> Any? {
        raw[key]
    }
}
