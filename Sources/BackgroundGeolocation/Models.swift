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
    /// The untouched native payload — permissive escape hatch for the next
    /// field that surprises us, mirroring `State.raw` and Flutter's
    /// `Location.raw` (`flutter/lib/src/models.dart:88`).
    public let raw: [String: Any]

    public init?(dictionary: [String: Any]) {
        guard let uuid = dictionary.string("uuid"),
              let timestamp = dictionary.string("timestamp"),
              let odometer = dictionary.double("odometer"),
              let coordsDictionary = dictionary.dictionary("coords"),
              let coords = Coords(dictionary: coordsDictionary),
              let activityDictionary = dictionary.dictionary("activity"),
              let activity = MotionActivity(dictionary: activityDictionary),
              let batteryDictionary = dictionary.dictionary("battery"),
              let battery = Battery(dictionary: batteryDictionary) else {
            return nil
        }
        self.uuid = uuid
        self.timestamp = timestamp
        self.age = dictionary.double("age")
        self.odometer = odometer
        self.coords = coords
        self.activity = activity
        self.battery = battery
        // The engine sends `NSNull` here — not `false` — while a cold-started
        // session's first fixes are still in the "unconfirmed MOVING" probing
        // window (`BGGeoEngine.mm:2826`, `:897`, `:1158`; up to 5 minutes by
        // default). `bool()` returns nil for both a missing key and `NSNull`,
        // so this must be coerced rather than required — Flutter does the
        // same (`flutter/lib/src/models.dart:102`). Getting this wrong drops
        // every location in that window.
        self.isMoving = dictionary.bool("is_moving") ?? false
        self.sample = dictionary.bool("sample")
        self.event = dictionary.string("event")
        self.extras = dictionary.dictionary("extras")
        self.raw = dictionary
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
    /// Whatever the caller passed to `Logger.error(_:data:)` etc. The engine
    /// parses the JSON string it was written as back into an object before
    /// returning it (`BGGeoEngine.mm:718-721`), so this is read straight off
    /// the dictionary rather than re-decoded as a string — reading it with
    /// `dictionary.string("data")` silently yields `nil` for every
    /// well-formed entry.
    public let data: Any?

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
        self.data = dictionary["data"]
    }
}

public struct ProviderState {
    public let status: AuthorizationStatus
    public let enabled: Bool
    public let gps: Bool
    public let network: Bool
    public let accuracyAuthorization: AccuracyAuthorization?

    /// Non-failable, for the same reason as `State.init(dictionary:)`: the
    /// engine always resolves, never rejects. Missing/unrecognised fields
    /// fall back to `.notDetermined`/`false` rather than fabricating a
    /// payload the engine never emitted.
    public init(dictionary: [String: Any]) {
        if let statusValue = dictionary.int("status"), let status = AuthorizationStatus(rawValue: statusValue) {
            self.status = status
        } else {
            self.status = .notDetermined
        }
        self.enabled = dictionary.bool("enabled") ?? false
        self.gps = dictionary.bool("gps") ?? false
        self.network = dictionary.bool("network") ?? false
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

/// Emitted when the engine refuses (or fails) a location fix instead of
/// resolving one — most notably `startWatch`'s only way of reporting a bad
/// license (`BGGeoEngine.mm:2653-2655`) and every failed watch tick
/// thereafter (`:2689`).
///
/// **`code` is `String`, not `Int`.** The engine emits `{code, message}`
/// where `code` is the same family of string codes this facade already
/// surfaces as `BGeoError.code` — `"LICENSE_EXPIRED"`, `"408"`, etc.
/// `react-native/src/index.ts:44-51` reduces this to `Number(error.code)` for
/// its legacy numeric-only `LocationErrorCallback` contract, but that
/// coercion is lossy (`Number("LICENSE_EXPIRED")` is `NaN`) and this facade
/// has no such legacy contract to match, so `code` stays a `String` here,
/// consistent with `BGeoError`.
public struct LocationErrorEvent {
    public let code: String
    public let message: String?

    public init?(dictionary: [String: Any]) {
        guard let code = dictionary.string("code") else { return nil }
        self.code = code
        self.message = dictionary.string("message")
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

    /// Non-failable: the engine always resolves `stateDictionary()`, never
    /// rejects (`RNBackgroundGeolocation.mm:126/135/147/154`). A missing
    /// `enabled` key defaults to `false` rather than fabricating a whole
    /// payload the engine never emitted; callers who need to distinguish
    /// "engine says false" from "key absent" can check `state["enabled"]`.
    public init(dictionary: [String: Any]) {
        self.enabled = dictionary.bool("enabled") ?? false
        self.raw = dictionary
    }

    public subscript(key: String) -> Any? {
        raw[key]
    }
}
