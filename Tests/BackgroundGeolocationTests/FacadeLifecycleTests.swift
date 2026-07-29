import XCTest
@testable import BackgroundGeolocation

@MainActor
final class FacadeLifecycleTests: XCTestCase {

    private var engine: FakeEngine!

    override func setUp() async throws {
        engine = FakeEngine()
        BackgroundGeolocation.engine = engine
        BackgroundGeolocation.hub = EventHub()
        BackgroundGeolocation.hub.attach(to: engine)
    }

    func testReadyAppliesConfigThenReturnsState() async throws {
        engine.stubbedState = ["enabled": false, "odometer": 0.0]
        let state = try await BackgroundGeolocation.ready(Config(distanceFilter: 25))
        XCTAssertEqual(engine.appliedConfigs.count, 1)
        XCTAssertEqual(engine.appliedConfigs.first?["distanceFilter"] as? Double, 25)
        XCTAssertEqual(state.enabled, false)
    }

    func testReadyThrowsTheEnginesLicenseCode() async {
        engine.stubbedLicenseError = "LICENSE_EXPIRED"
        do {
            _ = try await BackgroundGeolocation.ready(Config())
            XCTFail("expected a license error")
        } catch let error as BGeoError {
            XCTAssertEqual(error, .licenseExpired(message: error.message))
            XCTAssertEqual(error.code, "LICENSE_EXPIRED")
        } catch {
            XCTFail("expected BGeoError, got \(error)")
        }
    }

    func testReadyStillAppliedTheConfigBeforeTheLicenseCheckFailed() async {
        // Order matters: the engine reads the license key out of the config.
        engine.stubbedLicenseError = "LICENSE_MISSING"
        _ = try? await BackgroundGeolocation.ready(Config(debug: true))
        XCTAssertEqual(engine.appliedConfigs.count, 1)
    }

    func testStartChecksTheLicenseBeforeStartingTracking() async {
        engine.stubbedLicenseError = "LICENSE_APP_MISMATCH"
        _ = try? await BackgroundGeolocation.start()
        XCTAssertEqual(engine.startTrackingCallCount, 0, "tracking must not start on a bad license")
    }

    func testStartStartsTrackingWhenLicensed() async throws {
        engine.stubbedState = ["enabled": true]
        let state = try await BackgroundGeolocation.start()
        XCTAssertEqual(engine.startTrackingCallCount, 1)
        XCTAssertEqual(state.enabled, true)
    }

    func testStopNeverConsultsTheLicense() async throws {
        engine.stubbedLicenseError = "LICENSE_EXPIRED"
        engine.stubbedState = ["enabled": false]
        _ = try await BackgroundGeolocation.stop()
        XCTAssertEqual(engine.stopTrackingCallCount, 1)
    }

    func testSetConfigNeverConsultsTheLicense() async throws {
        engine.stubbedLicenseError = "LICENSE_EXPIRED"
        engine.stubbedState = ["enabled": false]
        _ = try await BackgroundGeolocation.setConfig(Config(debug: false))
        XCTAssertEqual(engine.appliedConfigs.count, 1)
    }

    func testChangePaceThrowsDisabledWhenTheEngineRefuses() async {
        engine.stubbedChangePaceResult = false
        do {
            try await BackgroundGeolocation.changePace(true)
            XCTFail("expected DISABLED")
        } catch let error as BGeoError {
            XCTAssertEqual(error.code, "DISABLED")
        } catch {
            XCTFail("expected BGeoError, got \(error)")
        }
    }

    func testGetCurrentPositionResolvesADecodedLocation() async throws {
        engine.stubbedCurrentPosition = .success(FakeEngine.sampleLocationDictionary)
        let location = try await BackgroundGeolocation.getCurrentPosition()
        XCTAssertEqual(location.uuid, "sample-uuid")
    }

    func testGetCurrentPositionThrowsTheEnginesRejection() async {
        engine.stubbedCurrentPosition = .failure(("TIMEOUT", "no fix in 30s"))
        do {
            _ = try await BackgroundGeolocation.getCurrentPosition()
            XCTFail("expected a rejection")
        } catch let error as BGeoError {
            XCTAssertEqual(error.code, "TIMEOUT")
            XCTAssertEqual(error.message, "no fix in 30s")
        } catch {
            XCTFail("expected BGeoError, got \(error)")
        }
    }

    func testCurrentPositionOptionsOmitUnsetValues() {
        XCTAssertTrue(CurrentPositionOptions().toDictionary().isEmpty)
        let dictionary = CurrentPositionOptions(samples: 3, timeout: 10).toDictionary()
        XCTAssertEqual(dictionary.count, 2)
        XCTAssertEqual(dictionary["samples"] as? Int, 3)
    }

    func testResetOdometerDelegatesToSetOdometerZero() async throws {
        engine.stubbedSetOdometer = .success(FakeEngine.sampleLocationDictionary)
        _ = try await BackgroundGeolocation.resetOdometer()
        XCTAssertEqual(engine.setOdometerValues, [0])
    }

    func testRequestPermissionMapsTheNumericStatus() async throws {
        engine.stubbedPermission = .success(3)
        let status = try await BackgroundGeolocation.requestPermission()
        XCTAssertEqual(status, .always)
    }

    func testOnLocationDeliversDecodedLocations() {
        var received: Location?
        _ = BackgroundGeolocation.onLocation { received = $0 }
        engine.emit("location", FakeEngine.sampleLocationDictionary)
        XCTAssertEqual(received?.uuid, "sample-uuid")
    }

    func testUndecodableEventPayloadIsDroppedNotCrashed() {
        var callCount = 0
        _ = BackgroundGeolocation.onLocation { _ in callCount += 1 }
        engine.emit("location", ["garbage": true])
        XCTAssertEqual(callCount, 0)
    }

    func testPowerSaveChangeUnwrapsTheBareBoolean() {
        // Native emits { isPowerSaveMode }; the callback takes a Bool.
        var received: Bool?
        _ = BackgroundGeolocation.onPowerSaveChange { received = $0 }
        engine.emit("powersavechange", ["isPowerSaveMode": true])
        XCTAssertEqual(received, true)
    }
}
