import XCTest
@testable import BGeoExample
import BackgroundGeolocation

@MainActor
final class GeofencesTests: XCTestCase {
    var suiteName: String!
    var defaults: UserDefaults!
    var session: URLSession!
    var store: AppStore!
    var deviceLink: DeviceLink!

    private let home = Geofence(identifier: "home", radius: 200, latitude: 1, longitude: 2)
    private let office = Geofence(identifier: "office", radius: 100, latitude: 3, longitude: 4)

    override func setUp() {
        super.setUp()
        suiteName = "GeofencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        store = AppStore()
        deviceLink = DeviceLink(store: store, session: session, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// Seeds a link so `DeviceLink.putGeofences` actually hits the network
    /// stub instead of short-circuiting as "not linked".
    private func seedLink() {
        let link = StoredLink(serverUrl: "https://test.bgeo.dev", deviceId: "dev-1", accessToken: "at", refreshToken: "rt", installUuid: "uuid-1")
        defaults.set(try! JSONEncoder().encode(link), forKey: "bgeo:link")
    }

    private var putGeofencesCalls: [URLRequest] {
        StubURLProtocol.capturedRequests.filter { $0.httpMethod == "PUT" && $0.url?.path == "/device/geofences" }
    }

    // MARK: - refresh()

    func testRefreshSetsStoreThenPushesSnapshot() async {
        seedLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 200, json: ["ok": true])
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.getGeofencesCall = { [self.home, self.office] }

        await geofences.refresh()

        XCTAssertEqual(store.geofences.map(\.identifier), ["home", "office"])
        XCTAssertEqual(putGeofencesCalls.count, 1)
    }

    func testRefreshStillSetsStoreWhenNotLinked() async {
        // No seeded link: putGeofences is a no-op (per geofences.ts's
        // comment, "no-op (null) when not linked") — the store update must
        // still happen, and nothing should be sent over the wire.
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.getGeofencesCall = { [self.home] }

        await geofences.refresh()

        XCTAssertEqual(store.geofences.map(\.identifier), ["home"])
        XCTAssertEqual(putGeofencesCalls.count, 0)
    }

    /// The snapshot push is the only step whose failure is otherwise
    /// invisible — the fence is still on the device and drawn on the map, the
    /// console just never hears about it. Both outcomes are logged so the Logs
    /// tab can answer "did my geofence reach the console?".

    func testRefreshLogsThePushOutcomeWhenTheConsoleAcceptsIt() async {
        seedLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 200, json: ["ok": true])
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.getGeofencesCall = { [self.home, self.office] }

        await geofences.refresh()

        let line = try! XCTUnwrap(store.logs.last)
        XCTAssertEqual(line.event, "putGeofences")
        XCTAssertEqual(line.level, .info)
        XCTAssertEqual(line.message, "2 mirrored to console")
    }

    func testRefreshLogsAWarningWhenTheSnapshotNeverReachesTheConsole() async {
        // Not linked: `putGeofences` short-circuits without a request.
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.getGeofencesCall = { [self.home] }

        await geofences.refresh()

        let line = try! XCTUnwrap(store.logs.last)
        XCTAssertEqual(line.event, "putGeofences")
        XCTAssertEqual(line.level, .warn, "a snapshot the console never received must not log as success")
        XCTAssertEqual(line.message, "console not updated (1 local)")
    }

    func testRefreshLogsAWarningWhenTheConsoleRejectsThePush() async {
        seedLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 500, json: ["error": "boom"])
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.getGeofencesCall = { [self.home] }

        await geofences.refresh()

        XCTAssertEqual(putGeofencesCalls.count, 1)
        XCTAssertEqual(store.logs.last?.level, .warn)
    }

    // MARK: - add()

    func testAddCallsSdkThenPushesSnapshot() async throws {
        seedLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 200, json: ["ok": true])
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        var callOrder: [String] = []
        var addedGeofence: Geofence?
        geofences.addGeofenceCall = { g in callOrder.append("add"); addedGeofence = g }
        geofences.getGeofencesCall = { callOrder.append("get"); return [self.home] }

        try await geofences.add(home)

        XCTAssertEqual(addedGeofence?.identifier, "home")
        XCTAssertEqual(callOrder, ["add", "get"], "the SDK call must run, and the refresh's getGeofences after it")
        XCTAssertEqual(store.geofences.map(\.identifier), ["home"])
        XCTAssertEqual(putGeofencesCalls.count, 1, "a successful add must push exactly one snapshot")
    }

    func testAddFailureDoesNotPushSnapshot() async {
        seedLink()
        // Deliberately no PUT stub registered: if the code pushed a snapshot
        // anyway, StubURLProtocol would fail that request rather than the
        // test silently passing — but the explicit count assertion below is
        // what actually communicates the guarantee under test.
        struct Boom: Error {}
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.addGeofenceCall = { _ in throw Boom() }
        var refreshRan = false
        geofences.getGeofencesCall = { refreshRan = true; return [] }

        do {
            try await geofences.add(home)
            XCTFail("expected add() to rethrow the SDK's error")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("wrong error type: \(error)")
        }

        XCTAssertFalse(refreshRan, "refresh() must not run after a failed SDK call")
        XCTAssertTrue(store.geofences.isEmpty)
        XCTAssertEqual(putGeofencesCalls.count, 0, "no snapshot must reach the console on failure")
    }

    // MARK: - remove()

    func testRemoveCallsSdkThenPushesSnapshot() async throws {
        seedLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 200, json: ["ok": true])
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        var callOrder: [String] = []
        var removedIdentifier: String?
        geofences.removeGeofenceCall = { id in callOrder.append("remove"); removedIdentifier = id }
        geofences.getGeofencesCall = { callOrder.append("get"); return [self.office] }

        try await geofences.remove(identifier: "home")

        XCTAssertEqual(removedIdentifier, "home")
        XCTAssertEqual(callOrder, ["remove", "get"])
        XCTAssertEqual(store.geofences.map(\.identifier), ["office"])
        XCTAssertEqual(putGeofencesCalls.count, 1)
    }

    func testRemoveFailureDoesNotPushSnapshot() async {
        seedLink()
        struct Boom: Error {}
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.removeGeofenceCall = { _ in throw Boom() }
        var refreshRan = false
        geofences.getGeofencesCall = { refreshRan = true; return [] }

        do {
            try await geofences.remove(identifier: "home")
            XCTFail("expected remove() to rethrow the SDK's error")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("wrong error type: \(error)")
        }

        XCTAssertFalse(refreshRan)
        XCTAssertEqual(putGeofencesCalls.count, 0)
    }

    // MARK: - removeAll()

    func testRemoveAllCallsSdkThenPushesSnapshot() async throws {
        seedLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 200, json: ["ok": true])
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        var callOrder: [String] = []
        geofences.removeGeofencesCall = { callOrder.append("removeAll") }
        geofences.getGeofencesCall = { callOrder.append("get"); return [] }

        try await geofences.removeAll()

        XCTAssertEqual(callOrder, ["removeAll", "get"])
        XCTAssertTrue(store.geofences.isEmpty)
        XCTAssertEqual(putGeofencesCalls.count, 1)
    }

    func testRemoveAllFailureDoesNotPushSnapshot() async {
        seedLink()
        struct Boom: Error {}
        let geofences = Geofences(store: store, deviceLink: deviceLink)
        geofences.removeGeofencesCall = { throw Boom() }
        var refreshRan = false
        geofences.getGeofencesCall = { refreshRan = true; return [] }

        do {
            try await geofences.removeAll()
            XCTFail("expected removeAll() to rethrow the SDK's error")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("wrong error type: \(error)")
        }

        XCTAssertFalse(refreshRan)
        XCTAssertEqual(putGeofencesCalls.count, 0)
    }

    // MARK: - geofenceschange.off regression guard (engine 0.13.1 / core 24cac4f)
    //
    // Before the fix, the engine's `geofenceschange.off` entries for a
    // removed geofence carried only `identifier` — no lat/lng/radius. The
    // SDK's own decoder (`Geofence.init?(dictionary:)`, `Models.swift`)
    // correctly treats those three fields as required and drops any record
    // missing them, so a malformed `off` entry silently vanished via
    // `compactMap` and the app never learned a fence had been removed. This
    // is the consumer-side guard for the fix: it decodes the wire shape the
    // fixed engine (0.13.1) actually emits and asserts the coordinates
    // survive, using nothing but the SDK's public `GeofencesChangeEvent`/
    // `Geofence` initialisers — no `@testable` reach into engine internals,
    // because none is needed or available from this package.

    func testGeofencesChangeOffEntryDecodesWithCoordinatesIntact() throws {
        let payload: [String: Any] = [
            "on": [],
            "off": [
                [
                    "identifier": "home",
                    "radius": 150.0,
                    "latitude": 52.52,
                    "longitude": 13.405,
                    "notifyOnEntry": true,
                    "notifyOnExit": true,
                ],
            ],
        ]

        let event = try XCTUnwrap(GeofencesChangeEvent(dictionary: payload))

        XCTAssertEqual(event.off.count, 1, "the removed fence must decode, not be dropped")
        let removed = try XCTUnwrap(event.off.first)
        XCTAssertEqual(removed.identifier, "home")
        XCTAssertEqual(removed.latitude, 52.52)
        XCTAssertEqual(removed.longitude, 13.405)
        XCTAssertEqual(removed.radius, 150)
    }

    /// Negative control: documents the PRE-FIX wire shape (identifier only)
    /// and confirms the decoder's behaviour on it is "drop, don't crash" —
    /// proving the positive test above is actually exercising the coordinate
    /// fields, not a decoder that accepts anything. If this ever starts
    /// decoding a coordinate-less record, the requirement in
    /// `Geofence.init?(dictionary:)` that let the fix work has regressed.
    func testGeofencesChangeOffEntryMissingCoordinatesIsDroppedNotCrashed() throws {
        let payload: [String: Any] = [
            "on": [],
            "off": [["identifier": "home"]],
        ]

        let event = try XCTUnwrap(GeofencesChangeEvent(dictionary: payload))

        XCTAssertTrue(event.off.isEmpty, "a coordinate-less off entry must be dropped, matching the pre-fix decoder contract")
    }
}
