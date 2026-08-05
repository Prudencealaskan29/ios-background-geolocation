import XCTest
@testable import BGeoExample

/// Covers `stateValueDescription` (`Sources/Screens/SettingsScreen.swift`) —
/// the Engine state list's value formatter. Everything else on that screen is
/// view code (the module has no Compose/SwiftUI test harness); this function
/// was pulled out of it precisely because it got a value's TYPE wrong, which
/// no amount of looking at the view can catch.
final class SettingsScreenTests: XCTestCase {

    /// The bug this exists for: `State.raw` comes from the ObjC engine, so
    /// every number is an `NSNumber`, and `NSNumber as? Bool` succeeds for any
    /// number equal to 0 or 1. Matching `Bool` first therefore rendered
    /// `odometer 0` as "false" and `geofenceCount 1` as "true" on the live
    /// screen.
    func testNumericZeroAndOneRenderAsNumbersNotBooleans() {
        XCTAssertEqual(stateValueDescription(NSNumber(value: 0)), "0")
        XCTAssertEqual(stateValueDescription(NSNumber(value: 1)), "1")
        XCTAssertEqual(stateValueDescription(NSNumber(value: 0.0 as Double)), "0")
        XCTAssertEqual(stateValueDescription(NSNumber(value: 1.0 as Double)), "1")
    }

    func testRealBooleansStillRenderAsTrueFalse() {
        XCTAssertEqual(stateValueDescription(NSNumber(value: true)), "true")
        XCTAssertEqual(stateValueDescription(NSNumber(value: false)), "false")
        XCTAssertEqual(stateValueDescription(true), "true")
        XCTAssertEqual(stateValueDescription(false), "false")
    }

    func testNonIntegralNumbersKeepTheirValue() {
        XCTAssertEqual(stateValueDescription(NSNumber(value: 3)), "3")
        XCTAssertEqual(stateValueDescription(NSNumber(value: 19.3226)), "19.3226")
    }

    func testStringsAndMissingValues() {
        XCTAssertEqual(stateValueDescription("kCLAuthorizationStatusAuthorizedAlways"), "kCLAuthorizationStatusAuthorizedAlways")
        XCTAssertEqual(stateValueDescription(nil), "—")
    }
}
