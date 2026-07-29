import Foundation

/// The durable upload queue. Method names and semantics mirror
/// `react-native/src/index.ts:234-278`.
extension BackgroundGeolocation {

    /// Manually drains the upload queue. Snapshots the queue with
    /// `queuedLocations()` FIRST, then calls `syncQueue()` — Transistor
    /// resolves `sync()` with the records that were queued, and reading the
    /// queue AFTER draining it would always return an empty list
    /// (`react-native/src/index.ts:234-240`).
    public static func sync() async throws -> [Location] {
        let snapshot = decodedLocations(engine.queuedLocations())
        engine.syncQueue()
        return snapshot
    }

    /// Records currently queued for upload, oldest-first. Unwraps
    /// `{"locations": [...]}` (`RNBackgroundGeolocation.mm:253-256`); a
    /// malformed record is skipped rather than failing the whole call.
    public static func getLocations() async -> [Location] {
        decodedLocations(engine.queuedLocations())
    }

    /// Deletes every queued record. Unwraps `{"count": n}`
    /// (`RNBackgroundGeolocation.mm:258-261`).
    public static func destroyLocations() async -> Int {
        engine.destroyQueuedLocations().int("count") ?? 0
    }

    public static func getCount() async -> Int {
        engine.pendingQueueCount()
    }

    /// Throws `.notFound` when the engine reports no such uuid was queued
    /// (`RNBackgroundGeolocation.mm:268-277`).
    public static func destroyLocation(uuid: String) async throws {
        guard engine.destroyQueuedLocation(uuid) else {
            throw BGeoError(code: "NOT_FOUND", message: "No queued location with uuid \(uuid)")
        }
    }

    public static func insertLocation(_ location: [String: Any]) async {
        engine.insertQueuedLocation(location)
    }

    /// Tokens the native uploader currently holds — it may have refreshed
    /// them while the app was killed.
    public static func getAuthState() async -> (accessToken: String?, refreshToken: String?) {
        let dictionary = engine.authStateDictionary()
        return (dictionary.string("accessToken"), dictionary.string("refreshToken"))
    }

    private static func decodedLocations(_ dictionary: [String: Any]) -> [Location] {
        let array = (dictionary["locations"] as? [[String: Any]]) ?? []
        return array.compactMap(Location.init(dictionary:))
    }
}
