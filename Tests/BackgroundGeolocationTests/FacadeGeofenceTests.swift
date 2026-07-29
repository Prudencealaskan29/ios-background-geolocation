import XCTest
@testable import BackgroundGeolocation

@MainActor
final class FacadeGeofenceTests: XCTestCase {

    private var engine: FakeEngine!

    private let home = Geofence(identifier: "home", radius: 200, latitude: 1.0, longitude: 2.0)
    private let office = Geofence(identifier: "office", radius: 100, latitude: 3.0, longitude: 4.0)

    override func setUp() async throws {
        engine = FakeEngine()
        BackgroundGeolocation.engine = engine
        BackgroundGeolocation.hub = EventHub()
        BackgroundGeolocation.hub.attach(to: engine)
    }

    // MARK: - addGeofence / addGeofences

    func testAddGeofenceForwardsAOneElementArray() async throws {
        try await BackgroundGeolocation.addGeofence(home)
        XCTAssertEqual(engine.addGeofencesCalls.count, 1)
        XCTAssertEqual(engine.addGeofencesCalls.first?.count, 1)
        XCTAssertEqual(engine.addGeofencesCalls.first?.first?["identifier"] as? String, "home")
    }

    func testAddGeofencesForwardsAllElementsWithTheirDictionaries() async throws {
        try await BackgroundGeolocation.addGeofences([home, office])
        XCTAssertEqual(engine.addGeofencesCalls.count, 1)
        let forwarded = engine.addGeofencesCalls.first ?? []
        XCTAssertEqual(forwarded.count, 2)
        XCTAssertEqual(forwarded.first?["identifier"] as? String, "home")
        XCTAssertEqual(forwarded.first?["radius"] as? Double, 200)
        XCTAssertEqual(forwarded.last?["identifier"] as? String, "office")
    }

    func testAddGeofencesThrowsTheEnginesInvalidGeofenceCode() async {
        engine.stubbedAddGeofencesError = "INVALID_GEOFENCE"
        do {
            try await BackgroundGeolocation.addGeofences([home])
            XCTFail("expected a rejection")
        } catch let error as BGeoError {
            XCTAssertEqual(error.code, "INVALID_GEOFENCE")
        } catch {
            XCTFail("expected BGeoError, got \(error)")
        }
    }

    func testAddGeofencesThrowsTheEnginesLicenseExpiredCode() async {
        engine.stubbedAddGeofencesError = "LICENSE_EXPIRED"
        do {
            try await BackgroundGeolocation.addGeofences([home])
            XCTFail("expected a rejection")
        } catch let error as BGeoError {
            XCTAssertEqual(error.code, "LICENSE_EXPIRED")
        } catch {
            XCTFail("expected BGeoError, got \(error)")
        }
    }

    // MARK: - removeGeofence / removeGeofences

    func testRemoveGeofenceDelegatesToTheEngine() async {
        await BackgroundGeolocation.removeGeofence(identifier: "home")
        XCTAssertEqual(engine.removeGeofenceIdentifiers, ["home"])
    }

    func testRemoveGeofencesDelegatesToTheEngine() async {
        await BackgroundGeolocation.removeGeofences()
        XCTAssertEqual(engine.removeAllGeofencesCallCount, 1)
    }

    // MARK: - getGeofences

    func testGetGeofencesUnwrapsAndDecodes() async {
        engine.stubbedGeofences = [home.toDictionary(), office.toDictionary()]
        let geofences = await BackgroundGeolocation.getGeofences()
        XCTAssertEqual(geofences.map(\.identifier), ["home", "office"])
    }

    func testGetGeofencesSkipsAMalformedRecordRatherThanFailing() async {
        let malformed: [String: Any] = ["identifier": "broken"] // missing radius/lat/lng
        engine.stubbedGeofences = [home.toDictionary(), malformed]
        let geofences = await BackgroundGeolocation.getGeofences()
        XCTAssertEqual(geofences.map(\.identifier), ["home"])
    }

    // MARK: - geofenceExists

    func testGeofenceExistsPassesThrough() async {
        engine.stubbedGeofenceExists = true
        let exists = await BackgroundGeolocation.geofenceExists(identifier: "home")
        XCTAssertTrue(exists)
        XCTAssertEqual(engine.geofenceExistsIdentifiers, ["home"])
    }

    // MARK: - onGeofence

    func testOnGeofenceDecodesAGeofenceEventWithItsAction() {
        var received: GeofenceEvent?
        _ = BackgroundGeolocation.onGeofence { received = $0 }
        engine.emit("geofence", [
            "identifier": "home",
            "action": "ENTER",
            "location": FakeEngine.sampleLocationDictionary,
        ])
        XCTAssertEqual(received?.identifier, "home")
        XCTAssertEqual(received?.action, .enter)
        XCTAssertEqual(received?.location.uuid, "sample-uuid")
    }

    // MARK: - onGeofencesChange

    func testOnGeofencesChangeDecodesBothOnAndOffArrays() {
        var received: GeofencesChangeEvent?
        _ = BackgroundGeolocation.onGeofencesChange { received = $0 }
        engine.emit("geofenceschange", [
            "on": [home.toDictionary()],
            "off": [office.toDictionary()],
        ])
        XCTAssertEqual(received?.on.map(\.identifier), ["home"])
        XCTAssertEqual(received?.off.map(\.identifier), ["office"])
    }
}
