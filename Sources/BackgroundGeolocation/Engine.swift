import Foundation
import BGeoCore

/// The testability seam over the closed-source `BGGeoEngine`. Everything in
/// this package talks to the engine only through this protocol, so the
/// facade can be unit-tested against `FakeEngine` without a device.
///
/// One method per `BGGeoEngine.h` member used by
/// `react-native/ios/RNBackgroundGeolocation.mm`.
@MainActor
protocol Engine: AnyObject {
    var eventEmitter: ((String, [String: Any]) -> Void)? { get set }
    var isEnabled: Bool { get }
    var odometer: Double { get }

    func applyConfig(_ config: [String: Any])
    func licenseErrorCode() -> String?
    func stateDictionary() -> [String: Any]
    func startTracking()
    func stopTracking()
    func changePace(_ isMoving: Bool) -> Bool

    func getCurrentPosition(_ options: [String: Any],
                            resolve: @escaping ([String: Any]) -> Void,
                            reject: @escaping (String, String) -> Void)
    func startWatch(_ options: [String: Any])
    func stopWatch()

    func requestPermission(resolve: @escaping (Int) -> Void,
                           reject: @escaping (String, String) -> Void)
    func requestTemporaryFullAccuracy(_ purpose: String,
                                      completion: @escaping (Int) -> Void)
    func providerState() -> [String: Any]
    func isPowerSaveMode() -> Bool

    func setOdometer(_ value: Double,
                     resolve: @escaping ([String: Any]) -> Void,
                     reject: @escaping (String, String) -> Void)

    func syncQueue() -> [String: Any]
    func queuedLocations() -> [String: Any]
    func destroyQueuedLocations() -> [String: Any]
    func pendingQueueCount() -> Int
    func destroyQueuedLocation(_ uuid: String) -> Bool
    func insertQueuedLocation(_ location: [String: Any])
    func authStateDictionary() -> [String: Any]

    func logEntries(_ limit: Int) -> [[String: Any]]
    func destroyLogs() -> Int
    func pendingLogCount() -> Int
    func flushLogs()
    func log(level: Int, event: String, message: String?, data: String?, src: String)

    func addGeofences(_ geofences: [[String: Any]]) -> String?
    func removeGeofence(_ identifier: String) -> Bool
    func removeAllGeofences()
    func geofences() -> [[String: Any]]
    func geofenceExists(_ identifier: String) -> Bool
}

/// Thin forwarder to `BGGeoEngine.shared` (and `BGGeoLogger`). No logic lives
/// here — every member is a 1:1 call-through, matching
/// `react-native/ios/RNBackgroundGeolocation.mm`.
@MainActor
final class LiveEngine: Engine {

    var eventEmitter: ((String, [String: Any]) -> Void)? {
        get {
            guard let block = BGGeoEngine.shared.eventEmitter else { return nil }
            return { name, body in
                block(name, body as [AnyHashable: Any])
            }
        }
        set {
            guard let handler = newValue else {
                BGGeoEngine.shared.eventEmitter = nil
                return
            }
            BGGeoEngine.shared.eventEmitter = { name, body in
                handler(name, (body as? [String: Any]) ?? [:])
            }
        }
    }

    var isEnabled: Bool { BGGeoEngine.shared.enabled }
    var odometer: Double { BGGeoEngine.shared.odometer }

    func applyConfig(_ config: [String: Any]) {
        BGGeoEngine.shared.applyConfig(config)
    }

    func licenseErrorCode() -> String? {
        BGGeoEngine.shared.licenseErrorCode()
    }

    func stateDictionary() -> [String: Any] {
        (BGGeoEngine.shared.stateDictionary() as? [String: Any]) ?? [:]
    }

    func startTracking() {
        BGGeoEngine.shared.startTracking()
    }

    func stopTracking() {
        BGGeoEngine.shared.stopTracking()
    }

    func changePace(_ isMoving: Bool) -> Bool {
        BGGeoEngine.shared.changePace(isMoving)
    }

    func getCurrentPosition(_ options: [String: Any],
                            resolve: @escaping ([String: Any]) -> Void,
                            reject: @escaping (String, String) -> Void) {
        BGGeoEngine.shared.getCurrentPosition(options, resolve: { location in
            resolve((location as? [String: Any]) ?? [:])
        }, reject: { code, message in
            reject(code, message)
        })
    }

    func startWatch(_ options: [String: Any]) {
        BGGeoEngine.shared.startWatch(options)
    }

    func stopWatch() {
        BGGeoEngine.shared.stopWatch()
    }

    func requestPermission(resolve: @escaping (Int) -> Void,
                           reject: @escaping (String, String) -> Void) {
        BGGeoEngine.shared.requestPermission({ status in
            resolve(status)
        }, reject: { code, message in
            reject(code, message)
        })
    }

    func requestTemporaryFullAccuracy(_ purpose: String,
                                      completion: @escaping (Int) -> Void) {
        BGGeoEngine.shared.requestTemporaryFullAccuracy(purpose, completion: { accuracyAuthorization in
            completion(accuracyAuthorization)
        })
    }

    func providerState() -> [String: Any] {
        (BGGeoEngine.shared.providerState() as? [String: Any]) ?? [:]
    }

    func isPowerSaveMode() -> Bool {
        BGGeoEngine.shared.isPowerSaveMode()
    }

    func setOdometer(_ value: Double,
                     resolve: @escaping ([String: Any]) -> Void,
                     reject: @escaping (String, String) -> Void) {
        BGGeoEngine.shared.setOdometer(value, resolve: { location in
            resolve((location as? [String: Any]) ?? [:])
        }, reject: { code, message in
            reject(code, message)
        })
    }

    func syncQueue() -> [String: Any] {
        (BGGeoEngine.shared.syncQueue() as? [String: Any]) ?? [:]
    }

    func queuedLocations() -> [String: Any] {
        (BGGeoEngine.shared.queuedLocations() as? [String: Any]) ?? [:]
    }

    func destroyQueuedLocations() -> [String: Any] {
        (BGGeoEngine.shared.destroyQueuedLocations() as? [String: Any]) ?? [:]
    }

    func pendingQueueCount() -> Int {
        Int(BGGeoEngine.shared.pendingQueueCount())
    }

    func destroyQueuedLocation(_ uuid: String) -> Bool {
        BGGeoEngine.shared.destroyQueuedLocation(uuid)
    }

    func insertQueuedLocation(_ location: [String: Any]) {
        BGGeoEngine.shared.insertQueuedLocation(location)
    }

    func authStateDictionary() -> [String: Any] {
        (BGGeoEngine.shared.authStateDictionary() as? [String: Any]) ?? [:]
    }

    func logEntries(_ limit: Int) -> [[String: Any]] {
        BGGeoEngine.shared.logEntries(limit).map { ($0 as? [String: Any]) ?? [:] }
    }

    func destroyLogs() -> Int {
        BGGeoEngine.shared.destroyLogs()
    }

    func pendingLogCount() -> Int {
        BGGeoEngine.shared.pendingLogCount()
    }

    func flushLogs() {
        BGGeoEngine.shared.flushLogs()
    }

    func log(level: Int, event: String, message: String?, data: String?, src: String) {
        BGGeoLogger.log(level, event: event, message: message, data: data, src: src)
    }

    func addGeofences(_ geofences: [[String: Any]]) -> String? {
        BGGeoEngine.shared.addGeofences(geofences)
    }

    func removeGeofence(_ identifier: String) -> Bool {
        BGGeoEngine.shared.removeGeofence(identifier)
    }

    func removeAllGeofences() {
        BGGeoEngine.shared.removeAllGeofences()
    }

    func geofences() -> [[String: Any]] {
        BGGeoEngine.shared.geofences().map { ($0 as? [String: Any]) ?? [:] }
    }

    func geofenceExists(_ identifier: String) -> Bool {
        BGGeoEngine.shared.geofenceExists(identifier)
    }
}
