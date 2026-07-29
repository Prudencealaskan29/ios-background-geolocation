import XCTest
@testable import BackgroundGeolocation

final class BGeoErrorTests: XCTestCase {
    func testLicenseCodesMapToTypedCases() {
        XCTAssertEqual(BGeoError(code: "LICENSE_MISSING", message: "m"), .licenseMissing(message: "m"))
        XCTAssertEqual(BGeoError(code: "LICENSE_INVALID", message: "m"), .licenseInvalid(message: "m"))
        XCTAssertEqual(BGeoError(code: "LICENSE_EXPIRED", message: "m"), .licenseExpired(message: "m"))
        XCTAssertEqual(BGeoError(code: "LICENSE_APP_MISMATCH", message: "m"), .licenseAppMismatch(message: "m"))
    }

    func testKnownOperationalCodesMapToTypedCases() {
        XCTAssertEqual(BGeoError(code: "DISABLED", message: "m"), .disabled(message: "m"))
        XCTAssertEqual(BGeoError(code: "NOT_FOUND", message: "m"), .notFound(message: "m"))
        XCTAssertEqual(BGeoError(code: "INVALID_GEOFENCE", message: "m"), .invalidGeofence(message: "m"))
    }

    func testUnknownCodeSurvivesAsUnknownWithItsCodeIntact() {
        // The engine may add codes; the facade must never swallow one.
        let error = BGeoError(code: "SOME_NEW_ENGINE_CODE", message: "boom")
        XCTAssertEqual(error, .unknown(code: "SOME_NEW_ENGINE_CODE", message: "boom"))
        XCTAssertEqual(error.code, "SOME_NEW_ENGINE_CODE")
        XCTAssertEqual(error.message, "boom")
    }

    func testCodeRoundTripsForEveryTypedCase() {
        // Whatever case a code maps to, reading .code back must return the
        // original string — apps log and compare it.
        for code in ["LICENSE_MISSING", "LICENSE_INVALID", "LICENSE_EXPIRED",
                     "LICENSE_APP_MISMATCH", "DISABLED", "NOT_FOUND",
                     "INVALID_GEOFENCE", "WHATEVER"] {
            XCTAssertEqual(BGeoError(code: code, message: "m").code, code)
        }
    }

    func testConstantsMatchTheCrossSdkContract() {
        XCTAssertEqual(AuthorizationStatus.always.rawValue, 3)
        XCTAssertEqual(DesiredAccuracy.high.rawValue, -1)
        XCTAssertEqual(DesiredAccuracy.navigation.rawValue, -2)
        XCTAssertEqual(LogLevel.verbose.rawValue, 5)
        XCTAssertEqual(AccuracyAuthorization.reduced.rawValue, 1)
        XCTAssertEqual(ActivityType.inVehicle.rawValue, "in_vehicle")
    }
}
