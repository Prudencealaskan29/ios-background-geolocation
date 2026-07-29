import XCTest
@testable import BackgroundGeolocation

/// Guards the Swift `Config` against the cross-SDK source of truth,
/// `react-native/src/types.ts`. Adding a key anywhere must fail here until
/// this facade agrees.
final class ConfigDriftTests: XCTestCase {

    /// Every property name in `interface Config`, parsed out of types.ts.
    private func keysDeclaredInTypesTS() throws -> Set<String> {
        // types.ts lives in the SIBLING repo, so walk up out of `ios/` entirely.
        // #filePath is .../bgeo/ios/Tests/BackgroundGeolocationTests/ConfigDriftTests.swift
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // .../ios/Tests/BackgroundGeolocationTests
            .deletingLastPathComponent()   // .../ios/Tests
            .deletingLastPathComponent()   // .../ios
            .deletingLastPathComponent()   // .../bgeo        <- the workspace root
            .appendingPathComponent("react-native/src/types.ts")

        // `ios/` currently lives as a checkout alongside `react-native/` in
        // the same private workspace. Once `ios/` becomes a standalone
        // public repo (phase 2), this sibling won't exist on disk at all —
        // skip rather than hard-fail so that split doesn't break every
        // consumer's test run over a check that can no longer run as written.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("react-native/src/types.ts not found at \(url.path) — "
                + "this drift check only works when ios/ and react-native/ are sibling "
                + "checkouts in the same workspace; skipping rather than failing.")
        }

        let source = try String(contentsOf: url, encoding: .utf8)

        guard let start = source.range(of: "export interface Config {") else {
            XCTFail("Config interface not found in \(url.path)"); return []
        }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n}") else {
            XCTFail("unterminated Config interface"); return []
        }
        let body = rest[..<end.lowerBound]

        var keys = Set<String>()
        // Property lines look like `  someKey?: type;` at two-space indent.
        let pattern = try NSRegularExpression(pattern: #"^  ([A-Za-z][A-Za-z0-9_]*)\??:"#,
                                              options: [.anchorsMatchLines])
        let text = String(body)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text) {
                keys.insert(String(text[range]))
            }
        }
        return keys
    }

    func testConfigCoversExactlyTheKeysTypesTSDeclares() throws {
        let expected = try keysDeclaredInTypesTS()
        XCTAssertEqual(expected.count, 57, "types.ts key count changed — update this expectation deliberately")

        // Build a Config with every property set, then read the dictionary back.
        let actual = Set(Config.everyKeyPopulated.toDictionary().keys)

        let missing = expected.subtracting(actual)
        let extra = actual.subtracting(expected)
        XCTAssertTrue(missing.isEmpty, "Config is missing keys declared in types.ts: \(missing.sorted())")
        XCTAssertTrue(extra.isEmpty, "Config emits keys types.ts does not declare: \(extra.sorted())")
    }
}

extension Config {
    /// Every one of the 57 `Config` properties set to a concrete value.
    /// Enumerated explicitly, in `types.ts` declaration order — a fixture
    /// that only set 40 keys would let the other 17 vanish from
    /// `ConfigDriftTests` without failing it.
    static let everyKeyPopulated = Config(
        locationAuthorizationRequest: "Always",
        locationAuthorizationAlert: ["titleWhenNotEnabled": "Location required"],
        disableLocationAuthorizationAlert: true,
        backgroundPermissionRationale: ["title": "Rationale"],
        desiredAccuracy: DesiredAccuracy.high.rawValue,
        distanceFilter: 30,
        disableLocationFilter: false,
        locationFilterMaxAccuracy: 100,
        locationFilterMaxSpeed: 60,
        locationFilterPolicy: "Conservative",
        kalmanProfile: "DEFAULT",
        odometerAccuracyThreshold: 0,
        disableElasticity: false,
        elasticityMultiplier: 1.0,
        stationaryDesiredAccuracy: "BALANCED",
        stationaryLocationUpdateInterval: 30000,
        triggerActivities: "in_vehicle,on_bicycle,walking,running,on_foot",
        minimumActivityRecognitionConfidence: 50,
        activityRecognitionInterval: 10000,
        disableMotionActivityUpdates: false,
        stopTimeout: 5,
        showsBackgroundLocationIndicator: true,
        stationaryRadius: 25,
        stationaryDistanceFilter: 25,
        preventSuspend: false,
        heartbeatInterval: 60,
        motionTriggerDelay: 10000,
        locationUpdateInterval: 1000,
        foregroundService: false,
        notification: NotificationConfig(title: "Tracking"),
        stopOnTerminate: false,
        startOnBoot: true,
        debug: false,
        logLevel: LogLevel.info.rawValue,
        logMaxDays: 3,
        logUrl: "https://example.test/log",
        maxDaysToPersist: 7,
        url: "https://example.test/locations",
        method: "POST",
        headers: ["X-Test": "1"],
        params: ["device": "test"],
        extras: ["source": "test"],
        httpRootProperty: "location",
        autoSync: true,
        disableAutoSyncOnCellular: false,
        autoSyncThreshold: 5,
        batchSync: false,
        maxBatchSize: 50,
        httpTimeoutMs: 60000,
        maxRecordsToPersist: 10000,
        authorization: AuthorizationConfig(
            strategy: "JWT", accessToken: "a", refreshToken: "r",
            refreshUrl: "https://example.test/refresh"
        ),
        stationaryKeepAlive: true,
        diagnosticExtras: false,
        useSessionEngine: true,
        geofenceProximityRadius: 1000,
        maxMonitoredGeofences: -1,
        geofenceInitialTriggerEntry: true
    )
}
