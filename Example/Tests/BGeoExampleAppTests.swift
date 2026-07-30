import XCTest
@testable import BGeoExample

/// Covers `redactedAuthorizationLogData` (`Sources/BGeoExampleApp.swift`) —
/// the `onAuthorization` event is `{success, accessToken, refreshToken}` (live
/// JWTs); this must never reach the Logs screen/`bgeo.db`/`/device/logs`
/// verbatim. `persistRotatedTokens` (a separate call site) still gets the raw
/// event — this function is only for the logged copy.
final class BGeoExampleAppTests: XCTestCase {
    func testRedactsTokensToPresenceBooleansOnSuccess() {
        let event: [String: Any] = ["success": true, "accessToken": "eyJ.live.jwt", "refreshToken": "eyJ.live.refresh"]

        let redacted = redactedAuthorizationLogData(event)

        XCTAssertEqual(redacted.count, 3, "must not carry the raw event (or anything else) through unredacted")
        XCTAssertEqual(redacted["success"] as? Bool, true)
        XCTAssertEqual(redacted["hasAccessToken"] as? Bool, true)
        XCTAssertEqual(redacted["hasRefreshToken"] as? Bool, true)
        XCTAssertNil(redacted["accessToken"], "the raw access token must never appear in the logged data")
        XCTAssertNil(redacted["refreshToken"], "the raw refresh token must never appear in the logged data")
    }

    func testRedactsToFalsePresenceOnFailureWithNoTokens() {
        let event: [String: Any] = ["success": false]

        let redacted = redactedAuthorizationLogData(event)

        XCTAssertEqual(redacted["success"] as? Bool, false)
        XCTAssertEqual(redacted["hasAccessToken"] as? Bool, false)
        XCTAssertEqual(redacted["hasRefreshToken"] as? Bool, false)
    }

    func testEmptyStringTokensCountAsAbsent() {
        let event: [String: Any] = ["success": true, "accessToken": "", "refreshToken": ""]

        let redacted = redactedAuthorizationLogData(event)

        XCTAssertEqual(redacted["hasAccessToken"] as? Bool, false)
        XCTAssertEqual(redacted["hasRefreshToken"] as? Bool, false)
    }
}
