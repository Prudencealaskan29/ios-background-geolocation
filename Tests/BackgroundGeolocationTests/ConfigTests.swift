import XCTest
@testable import BackgroundGeolocation

final class ConfigTests: XCTestCase {

    func testEmptyConfigProducesEmptyDictionary() {
        // setConfig is a PATCH — an untouched Config must change nothing.
        XCTAssertTrue(Config().toDictionary().isEmpty)
    }

    func testOnlySetPropertiesAppear() {
        let dictionary = Config(distanceFilter: 30, debug: true).toDictionary()
        XCTAssertEqual(dictionary.count, 2)
        XCTAssertEqual(dictionary["distanceFilter"] as? Double, 30)
        XCTAssertEqual(dictionary["debug"] as? Bool, true)
    }

    func testDesiredAccuracyIsWrittenAsItsNumericConstant() {
        let dictionary = Config(desiredAccuracy: DesiredAccuracy.navigation.rawValue).toDictionary()
        XCTAssertEqual(dictionary["desiredAccuracy"] as? Int, -2)
    }

    func testNestedNotificationOmitsItsOwnNils() {
        let dictionary = Config(notification: NotificationConfig(title: "Tracking")).toDictionary()
        let notification = dictionary["notification"] as? [String: Any]
        XCTAssertEqual(notification?["title"] as? String, "Tracking")
        XCTAssertNil(notification?["channelId"])
        XCTAssertEqual(notification?.count, 1)
    }

    func testNestedAuthorizationSerialises() {
        let dictionary = Config(authorization: AuthorizationConfig(
            strategy: "JWT", accessToken: "a", refreshToken: "r",
            refreshUrl: "https://example.test/refresh"
        )).toDictionary()
        let authorization = dictionary["authorization"] as? [String: Any]
        XCTAssertEqual(authorization?["accessToken"] as? String, "a")
        XCTAssertEqual(authorization?["refreshUrl"] as? String, "https://example.test/refresh")
        XCTAssertNil(authorization?["refreshPayload"])
    }

    func testClearSentinelEmitsNSNullSoAKeyCanBeUnset() {
        // Flutter cannot express "clear this key" because its Config omits nulls
        // (see flutter/lib/src/config.dart). Swift must be able to.
        let dictionary = Config(url: Config.clearString).toDictionary()
        XCTAssertTrue(dictionary["url"] is NSNull)
    }

    func testClearSentinelWorksForLogUrlHeadersParamsExtras() {
        let dictionary = Config(
            logUrl: Config.clearString,
            headers: Config.clearDictionary,
            params: Config.clearAnyDictionary,
            extras: Config.clearAnyDictionary
        ).toDictionary()
        XCTAssertTrue(dictionary["logUrl"] is NSNull)
        XCTAssertTrue(dictionary["headers"] is NSNull)
        XCTAssertTrue(dictionary["params"] is NSNull)
        XCTAssertTrue(dictionary["extras"] is NSNull)
    }

    func testClearSentinelWorksForAuthorization() {
        let dictionary = Config(authorization: AuthorizationConfig.clear).toDictionary()
        XCTAssertTrue(dictionary["authorization"] is NSNull)
    }

    func testNonSentinelValuesAreNotMistakenForClear() {
        // A real headers/params/extras payload must serialise normally, not as NSNull.
        let dictionary = Config(
            headers: ["Authorization": "Bearer x"],
            params: ["deviceId": "abc"],
            extras: ["source": "test"]
        ).toDictionary()
        XCTAssertEqual((dictionary["headers"] as? [String: String])?["Authorization"], "Bearer x")
        XCTAssertEqual((dictionary["params"] as? [String: Any])?["deviceId"] as? String, "abc")
        XCTAssertEqual((dictionary["extras"] as? [String: Any])?["source"] as? String, "test")
    }
}
