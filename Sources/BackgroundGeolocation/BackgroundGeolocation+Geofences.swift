import Foundation

/// App-facing geofences. Method and event names mirror
/// `react-native/src/index.ts:370-399`.
extension BackgroundGeolocation {

    /// Delegates to `addGeofences` with a one-element array rather than
    /// duplicating the license-gated add logic
    /// (`RNBackgroundGeolocation.mm:336-345`).
    public static func addGeofence(_ geofence: Geofence) async throws {
        try await addGeofences([geofence])
    }

    /// The engine gates the license here: a non-nil return can be a
    /// `LICENSE_*` code as well as `INVALID_GEOFENCE`
    /// (`RNBackgroundGeolocation.mm:347-365`) — surfaced verbatim.
    public static func addGeofences(_ geofences: [Geofence]) async throws {
        if let code = engine.addGeofences(geofences.map { $0.toDictionary() }) {
            throw BGeoError(code: code, message: "geofence request rejected (\(code))")
        }
    }

    public static func removeGeofence(identifier: String) async {
        engine.removeGeofence(identifier)
    }

    public static func removeGeofences() async {
        engine.removeAllGeofences()
    }

    /// `engine.geofences()` already returns a bare array — unlike the RN
    /// bridge, which wraps it in `{"geofences": [...]}` only because its
    /// codegen boundary needed an envelope (`RNBackgroundGeolocation.mm:381-384`).
    /// A malformed record is skipped rather than failing the whole call.
    public static func getGeofences() async -> [Geofence] {
        engine.geofences().compactMap(Geofence.init(dictionary:))
    }

    public static func geofenceExists(identifier: String) async -> Bool {
        engine.geofenceExists(identifier)
    }

    @discardableResult
    public static func onGeofence(_ handler: @escaping (GeofenceEvent) -> Void) -> Subscription {
        hub.subscribe("geofence") { dictionary in
            if let event = GeofenceEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    @discardableResult
    public static func onGeofencesChange(_ handler: @escaping (GeofencesChangeEvent) -> Void) -> Subscription {
        hub.subscribe("geofenceschange") { dictionary in
            if let event = GeofencesChangeEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    public static var geofenceEvents: AsyncStream<GeofenceEvent> {
        typedStream("geofence", decode: GeofenceEvent.init(dictionary:))
    }

    public static var geofenceChanges: AsyncStream<GeofencesChangeEvent> {
        typedStream("geofenceschange", decode: GeofencesChangeEvent.init(dictionary:))
    }
}
