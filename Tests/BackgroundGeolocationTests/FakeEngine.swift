import Foundation
@testable import BackgroundGeolocation

/// Test double for `Engine`. Records every call it receives and lets tests
/// drive `eventEmitter` directly via `emit(_:_:)`. Used by the `EventHub`
/// tests in this task, and by the facade tests in later tasks.
@MainActor
final class FakeEngine: Engine {

    // MARK: - eventEmitter

    var eventEmitter: ((String, [String: Any]) -> Void)?

    /// Calls whatever `EventHub.attach(to:)` installed, exactly as the real
    /// engine would when CoreLocation produces an event.
    func emit(_ name: String, _ body: [String: Any]) {
        eventEmitter?(name, body)
    }

    // MARK: - Simple properties

    var stubbedIsEnabled = false
    var isEnabled: Bool { stubbedIsEnabled }

    var stubbedOdometer: Double = 0
    var odometer: Double { stubbedOdometer }

    // MARK: - Config / state

    var appliedConfigs: [[String: Any]] = []
    func applyConfig(_ config: [String: Any]) {
        appliedConfigs.append(config)
    }

    var stubbedLicenseError: String?
    func licenseErrorCode() -> String? {
        stubbedLicenseError
    }

    var stubbedState: [String: Any] = [:]
    func stateDictionary() -> [String: Any] {
        stubbedState
    }

    // MARK: - Tracking

    var startTrackingCallCount = 0
    func startTracking() {
        startTrackingCallCount += 1
    }

    var stopTrackingCallCount = 0
    func stopTracking() {
        stopTrackingCallCount += 1
    }

    var stubbedChangePace = true
    var changePaceCalls: [Bool] = []
    func changePace(_ isMoving: Bool) -> Bool {
        changePaceCalls.append(isMoving)
        return stubbedChangePace
    }

    // MARK: - Single-shot / watch

    var stubbedCurrentPosition: [String: Any] = [:]
    var stubbedCurrentPositionError: (String, String)?
    var getCurrentPositionOptions: [[String: Any]] = []
    func getCurrentPosition(_ options: [String: Any],
                            resolve: @escaping ([String: Any]) -> Void,
                            reject: @escaping (String, String) -> Void) {
        getCurrentPositionOptions.append(options)
        if let error = stubbedCurrentPositionError {
            reject(error.0, error.1)
        } else {
            resolve(stubbedCurrentPosition)
        }
    }

    var startWatchOptions: [[String: Any]] = []
    func startWatch(_ options: [String: Any]) {
        startWatchOptions.append(options)
    }

    var stopWatchCallCount = 0
    func stopWatch() {
        stopWatchCallCount += 1
    }

    // MARK: - Permission / provider

    var stubbedPermissionStatus = 0
    var stubbedPermissionError: (String, String)?
    var requestPermissionCallCount = 0
    func requestPermission(resolve: @escaping (Int) -> Void,
                           reject: @escaping (String, String) -> Void) {
        requestPermissionCallCount += 1
        if let error = stubbedPermissionError {
            reject(error.0, error.1)
        } else {
            resolve(stubbedPermissionStatus)
        }
    }

    var stubbedAccuracyAuthorization = 0
    var requestTemporaryFullAccuracyPurposes: [String] = []
    func requestTemporaryFullAccuracy(_ purpose: String,
                                      completion: @escaping (Int) -> Void) {
        requestTemporaryFullAccuracyPurposes.append(purpose)
        completion(stubbedAccuracyAuthorization)
    }

    var stubbedProviderState: [String: Any] = [:]
    func providerState() -> [String: Any] {
        stubbedProviderState
    }

    var stubbedIsPowerSaveMode = false
    func isPowerSaveMode() -> Bool {
        stubbedIsPowerSaveMode
    }

    // MARK: - Odometer

    var stubbedSetOdometerResult: [String: Any] = [:]
    var stubbedSetOdometerError: (String, String)?
    var setOdometerValues: [Double] = []
    func setOdometer(_ value: Double,
                     resolve: @escaping ([String: Any]) -> Void,
                     reject: @escaping (String, String) -> Void) {
        setOdometerValues.append(value)
        if let error = stubbedSetOdometerError {
            reject(error.0, error.1)
        } else {
            resolve(stubbedSetOdometerResult)
        }
    }

    // MARK: - Upload queue

    var stubbedSyncQueue: [String: Any] = [:]
    func syncQueue() -> [String: Any] {
        stubbedSyncQueue
    }

    var stubbedQueuedLocations: [String: Any] = [:]
    func queuedLocations() -> [String: Any] {
        stubbedQueuedLocations
    }

    var stubbedDestroyQueuedLocations: [String: Any] = [:]
    func destroyQueuedLocations() -> [String: Any] {
        stubbedDestroyQueuedLocations
    }

    var stubbedPendingQueueCount = 0
    func pendingQueueCount() -> Int {
        stubbedPendingQueueCount
    }

    var stubbedDestroyQueuedLocation = true
    var destroyQueuedLocationUuids: [String] = []
    func destroyQueuedLocation(_ uuid: String) -> Bool {
        destroyQueuedLocationUuids.append(uuid)
        return stubbedDestroyQueuedLocation
    }

    var insertedQueuedLocations: [[String: Any]] = []
    func insertQueuedLocation(_ location: [String: Any]) {
        insertedQueuedLocations.append(location)
    }

    var stubbedAuthState: [String: Any] = [:]
    func authStateDictionary() -> [String: Any] {
        stubbedAuthState
    }

    // MARK: - Logger

    var stubbedLogEntries: [[String: Any]] = []
    var logEntriesLimits: [Int] = []
    func logEntries(_ limit: Int) -> [[String: Any]] {
        logEntriesLimits.append(limit)
        return stubbedLogEntries
    }

    var stubbedDestroyLogs = 0
    func destroyLogs() -> Int {
        stubbedDestroyLogs
    }

    var stubbedPendingLogCount = 0
    func pendingLogCount() -> Int {
        stubbedPendingLogCount
    }

    var flushLogsCallCount = 0
    func flushLogs() {
        flushLogsCallCount += 1
    }

    struct LogCall: Equatable {
        let level: Int
        let event: String
        let message: String?
        let data: String?
        let src: String
    }
    var logCalls: [LogCall] = []
    func log(level: Int, event: String, message: String?, data: String?, src: String) {
        logCalls.append(LogCall(level: level, event: event, message: message, data: data, src: src))
    }

    // MARK: - Geofences

    var stubbedAddGeofencesError: String?
    var addGeofencesCalls: [[[String: Any]]] = []
    func addGeofences(_ geofences: [[String: Any]]) -> String? {
        addGeofencesCalls.append(geofences)
        return stubbedAddGeofencesError
    }

    var stubbedRemoveGeofence = true
    var removeGeofenceIdentifiers: [String] = []
    func removeGeofence(_ identifier: String) -> Bool {
        removeGeofenceIdentifiers.append(identifier)
        return stubbedRemoveGeofence
    }

    var removeAllGeofencesCallCount = 0
    func removeAllGeofences() {
        removeAllGeofencesCallCount += 1
    }

    var stubbedGeofences: [[String: Any]] = []
    func geofences() -> [[String: Any]] {
        stubbedGeofences
    }

    var stubbedGeofenceExists = false
    var geofenceExistsIdentifiers: [String] = []
    func geofenceExists(_ identifier: String) -> Bool {
        geofenceExistsIdentifiers.append(identifier)
        return stubbedGeofenceExists
    }
}
