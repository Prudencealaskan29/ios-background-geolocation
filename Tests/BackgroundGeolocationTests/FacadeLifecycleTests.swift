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

    func testOnLocationErrorDeliversTheEnginesCodeAndMessage() {
        // The engine's only way of reporting a bad license on `startWatch`,
        // and every failed watch tick thereafter (`BGGeoEngine.mm:2653-2655`,
        // `:2689`) — before this API existed, an app had no way to reach it.
        var received: LocationErrorEvent?
        _ = BackgroundGeolocation.onLocationError { received = $0 }
        engine.emit("locationerror", ["code": "LICENSE_EXPIRED", "message": "Tracking is not licensed"])
        XCTAssertEqual(received?.code, "LICENSE_EXPIRED")
        XCTAssertEqual(received?.message, "Tracking is not licensed")
    }

    func testLocationErrorsStreamDecodesEventsAndUnsubscribesWhenItsTaskIsCancelled() async {
        var received: LocationErrorEvent?
        let task = Task {
            for await event in BackgroundGeolocation.locationErrors {
                received = event
            }
        }
        await Task.yield()
        engine.emit("locationerror", ["code": "408", "message": "no fix in 30s"])
        await Task.yield()
        XCTAssertEqual(received?.code, "408")

        task.cancel()
        await Task.yield()

        XCTAssertEqual(BackgroundGeolocation.hub.subscriberCount(for: "locationerror"), 0)
    }

    func testOnLocationDeliversAnNSNullIsMovingPayloadRatherThanDroppingIt() {
        // Regression for the cold-start probing window: the engine emits
        // NSNull, not false, for `is_moving` while a session's first fixes
        // are unconfirmed (`BGGeoEngine.mm:2826`) — up to 5 minutes after
        // `start()` by default. Before the fix, this failed `Location`'s
        // whole decode and `onLocation` silently dropped every one of these.
        var payload = FakeEngine.sampleLocationDictionary
        payload["is_moving"] = NSNull()

        var received: Location?
        _ = BackgroundGeolocation.onLocation { received = $0 }
        engine.emit("location", payload)

        XCTAssertNotNil(received, "an NSNull is_moving payload must be delivered, not dropped")
        XCTAssertEqual(received?.isMoving, false)
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

    func testReadyAttachesTheHubSoLaunchTimeEventsAreBufferedForLateSubscribers() async throws {
        // Reproduce the state a genuinely untouched engine/hub pair would be
        // in — the engine's `eventEmitter` slot is nil until something reads
        // `hub` — by undoing `setUp`'s manual attach.
        engine.eventEmitter = nil
        BackgroundGeolocation.hub = EventHub()
        engine.stubbedState = ["enabled": false]

        _ = try await BackgroundGeolocation.ready(Config())

        // Without `ready()` attaching the hub, this emit would have nowhere
        // to go and the event would be lost forever, not buffered.
        engine.emit("authorization", ["source": "launch"])

        var received: [String: Any]?
        _ = BackgroundGeolocation.onAuthorization { received = $0 }
        XCTAssertEqual(received?["source"] as? String, "launch")
    }

    func testRequestTemporaryFullAccuracyMapsTheNumericAccuracy() async {
        engine.stubbedAccuracyAuthorization = 1
        let accuracy = await BackgroundGeolocation.requestTemporaryFullAccuracy(purpose: "Trip")
        XCTAssertEqual(accuracy, .reduced)
        XCTAssertEqual(engine.requestTemporaryFullAccuracyPurposes, ["Trip"])
    }

    func testRequestTemporaryFullAccuracyResumesReducedIfCoreLocationNeverCompletes() async {
        // The hazard this watchdog exists for: if `purpose` is missing from
        // the app's NSLocationTemporaryUsageDescriptionDictionary, iOS may
        // never invoke CoreLocation's completion at all
        // (`react-native/src/index.ts:196-199`). Without a bound, this call
        // would hang forever.
        engine.completeRequestTemporaryFullAccuracy = false
        let originalTimeout = BackgroundGeolocation.temporaryFullAccuracyTimeout
        BackgroundGeolocation.temporaryFullAccuracyTimeout = 0.05
        defer { BackgroundGeolocation.temporaryFullAccuracyTimeout = originalTimeout }

        let accuracy = await BackgroundGeolocation.requestTemporaryFullAccuracy(purpose: "Trip")

        XCTAssertEqual(accuracy, .reduced)
    }

    func testWatchPositionDelegatesOptionsToTheEngine() {
        BackgroundGeolocation.watchPosition(WatchPositionOptions(interval: 5))
        XCTAssertEqual(engine.startWatchOptions.count, 1)
        XCTAssertEqual(engine.startWatchOptions.first?["interval"] as? Double, 5)
    }

    func testStopWatchPositionDelegatesToTheEngine() {
        BackgroundGeolocation.stopWatchPosition()
        XCTAssertEqual(engine.stopWatchCallCount, 1)
    }

    func testRemoveListenersDetachesEverySubscriber() {
        var callCount = 0
        _ = BackgroundGeolocation.onLocation { _ in callCount += 1 }
        BackgroundGeolocation.removeListeners()
        engine.emit("location", FakeEngine.sampleLocationDictionary)
        XCTAssertEqual(callCount, 0)
    }

    func testLocationsStreamDecodesEventsAndUnsubscribesWhenItsTaskIsCancelled() async {
        var received: Location?
        let task = Task {
            for await location in BackgroundGeolocation.locations {
                received = location
            }
        }
        await Task.yield()
        engine.emit("location", FakeEngine.sampleLocationDictionary)
        await Task.yield()
        XCTAssertEqual(received?.uuid, "sample-uuid")

        task.cancel()
        await Task.yield()

        XCTAssertEqual(BackgroundGeolocation.hub.subscriberCount(for: "location"), 0)
    }
}
