import BGeoCore
import XCTest
@testable import BackgroundGeolocation

final class SmokeTests: XCTestCase {
    func testPackageLinksAndEngineHeaderIsVisible() {
        // Proves the binaryTarget linked and its public header is importable —
        // if the xcframework is missing or malformed this fails to compile.
        XCTAssertNotNil(BGGeoEngine.shared)
    }
}
