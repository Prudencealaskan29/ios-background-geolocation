import Foundation

/// Cross-SDK numeric/string constants. Values MUST match
/// `react-native/src/constants.ts` exactly — apps compare
/// `onProviderChange.status` against `AuthorizationStatus.always`, etc.

public enum DesiredAccuracy: Int {
    case navigation = -2
    case high = -1
    case medium = 10
    case low = 100
    case veryLow = 1000
    case lowest = 3000
}

public enum LogLevel: Int {
    case off = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    case verbose = 5
}

public enum AuthorizationStatus: Int {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case always = 3
    case whenInUse = 4
}

public enum AccuracyAuthorization: Int {
    case full = 0
    case reduced = 1
}

public enum ActivityType: String {
    case still
    case onFoot = "on_foot"
    case walking
    case running
    case onBicycle = "on_bicycle"
    case inVehicle = "in_vehicle"
    case unknown
}
