import Foundation

/// Small helpers for pulling typed values out of the engine's `[String: Any]`
/// payloads. The engine always sends numerics as `NSNumber` — `as? Double` on
/// an integer-valued `NSNumber` works, but `as? Double` on a Swift `Int`
/// literal (as used in test fixtures) does not. Routing every numeric read
/// through `NSNumber` handles both shapes.
extension Dictionary where Key == String, Value == Any {
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func bool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
    func string(_ key: String) -> String? { self[key] as? String }
    func dictionary(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
}
