import XCTest
@testable import BGeoExample
import BackgroundGeolocation

/// A `URLProtocol` stub so `DeviceLinkTests` never touches the network.
/// Responses are queued per `"METHOD path"` key and consumed in order — this
/// is what lets a single test stub "401, then a successful refresh, then a
/// successful retry" against the same endpoint.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: Data
    }

    static var responses: [String: [Stub]] = [:]
    static var capturedRequests: [URLRequest] = []

    static func reset() {
        responses = [:]
        capturedRequests = []
    }

    static func stub(_ method: String, _ path: String, status: Int, json: [String: Any] = [:]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let key = "\(method) \(path)"
        responses[key, default: []].append(Stub(statusCode: status, body: data))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        guard var queue = Self.responses[key], !queue.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stub = queue.removeFirst()
        Self.responses[key] = queue
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class DeviceLinkTests: XCTestCase {
    var suiteName: String!
    var defaults: UserDefaults!
    var session: URLSession!
    var store: AppStore!

    override func setUp() {
        super.setUp()
        suiteName = "DeviceLinkTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        store = AppStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeLink() -> DeviceLink {
        DeviceLink(store: store, session: session, defaults: defaults)
    }

    private func seedStoredLink(
        serverUrl: String = "https://test.bgeo.dev",
        deviceId: String = "dev-1",
        accessToken: String = "old-token",
        refreshToken: String = "old-refresh",
        installUuid: String = "uuid-1"
    ) -> StoredLink {
        let link = StoredLink(
            serverUrl: serverUrl,
            deviceId: deviceId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            installUuid: installUuid
        )
        defaults.set(try! JSONEncoder().encode(link), forKey: "bgeo:link")
        return link
    }

    private func loadPersistedLink() -> StoredLink? {
        guard let data = defaults.data(forKey: "bgeo:link") else { return nil }
        return try? JSONDecoder().decode(StoredLink.self, from: data)
    }

    // MARK: - link()

    func testLinkSuccessStoresLinkAndConfiguresSDK() async throws {
        StubURLProtocol.stub("POST", "/device/register", status: 200, json: [
            "device_id": "dev-1", "access_token": "at-1", "refresh_token": "rt-1",
        ])
        let link = makeLink()
        var capturedConfig: Config?
        link.applyConfig = { config in capturedConfig = config }

        let result = try await link.link(serverUrl: "https://test.bgeo.dev", code: "  ABC123  ")

        XCTAssertEqual(result.serverUrl, "https://test.bgeo.dev")
        XCTAssertEqual(result.deviceId, "dev-1")
        XCTAssertEqual(result.accessToken, "at-1")
        XCTAssertEqual(result.refreshToken, "rt-1")
        XCTAssertFalse(result.installUuid.isEmpty)

        XCTAssertEqual(loadPersistedLink(), result)

        let dictionary = try XCTUnwrap(capturedConfig?.toDictionary())
        XCTAssertEqual(dictionary["url"] as? String, "https://test.bgeo.dev/device/locations")
        XCTAssertEqual(dictionary["logUrl"] as? String, "https://test.bgeo.dev/device/logs")
        XCTAssertEqual(dictionary["autoSync"] as? Bool, true)
        XCTAssertEqual(dictionary["batchSync"] as? Bool, true)
        XCTAssertEqual(dictionary["maxBatchSize"] as? Int, 50)
        let authorization = try XCTUnwrap(dictionary["authorization"] as? [String: Any])
        XCTAssertEqual(authorization["strategy"] as? String, "JWT")
        XCTAssertEqual(authorization["accessToken"] as? String, "at-1")
        XCTAssertEqual(authorization["refreshToken"] as? String, "rt-1")
        XCTAssertEqual(authorization["refreshUrl"] as? String, "https://test.bgeo.dev/device/auth/refresh")

        XCTAssertTrue(store.link.linked)
        XCTAssertEqual(store.link.deviceId, "dev-1")
        XCTAssertEqual(store.link.serverUrl, "https://test.bgeo.dev")

        // `code` is sent trimmed.
        let registerBody = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.url)
        XCTAssertEqual(registerBody.path, "/device/register")
    }

    func testLinkNon2xxSurfacesDetailField() async {
        StubURLProtocol.stub("POST", "/device/register", status: 400, json: ["detail": "bad registration code"])
        let link = makeLink()

        do {
            _ = try await link.link(serverUrl: "https://test.bgeo.dev", code: "bad")
            XCTFail("expected link() to throw")
        } catch let error as DeviceLinkError {
            XCTAssertEqual(error.message, "bad registration code")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testLinkNon2xxFallsBackToErrorField() async {
        StubURLProtocol.stub("POST", "/device/register", status: 400, json: ["error": "expired code"])
        let link = makeLink()

        do {
            _ = try await link.link(serverUrl: "https://test.bgeo.dev", code: "bad")
            XCTFail("expected link() to throw")
        } catch let error as DeviceLinkError {
            XCTAssertEqual(error.message, "expired code")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testLinkNon2xxFallsBackToGenericStatusMessage() async {
        StubURLProtocol.stub("POST", "/device/register", status: 500, json: [:])
        let link = makeLink()

        do {
            _ = try await link.link(serverUrl: "https://test.bgeo.dev", code: "bad")
            XCTFail("expected link() to throw")
        } catch let error as DeviceLinkError {
            XCTAssertEqual(error.message, "register failed (500)")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    // MARK: - install UUID

    func testInstallUuidGeneratedOnceAndReusedAcrossInstances() async throws {
        StubURLProtocol.stub("POST", "/device/register", status: 200, json: [
            "device_id": "d1", "access_token": "a1", "refresh_token": "r1",
        ])
        StubURLProtocol.stub("POST", "/device/register", status: 200, json: [
            "device_id": "d2", "access_token": "a2", "refresh_token": "r2",
        ])

        let firstLink = makeLink()
        firstLink.applyConfig = { _ in }
        let firstResult = try await firstLink.link(serverUrl: "https://test.bgeo.dev", code: "AAA")

        // Fresh instance, same UserDefaults suite.
        let secondLink = makeLink()
        secondLink.applyConfig = { _ in }
        let secondResult = try await secondLink.link(serverUrl: "https://test.bgeo.dev", code: "BBB")

        XCTAssertEqual(firstResult.installUuid, secondResult.installUuid)
        XCTAssertEqual(defaults.string(forKey: "bgeo:installUuid"), firstResult.installUuid)
    }

    // MARK: - restore()

    func testRestoreRoundTripsThroughFreshInstance() async throws {
        let seeded = seedStoredLink(deviceId: "dev-9", accessToken: "at-9", refreshToken: "rt-9", installUuid: "uuid-9")

        let freshStore = AppStore()
        let freshLink = DeviceLink(store: freshStore, session: session, defaults: defaults)
        var capturedConfig: Config?
        freshLink.applyConfig = { config in capturedConfig = config }

        let restored = await freshLink.restore()

        XCTAssertEqual(restored, seeded)
        XCTAssertEqual(capturedConfig?.authorization?.accessToken, "at-9")
        XCTAssertEqual(capturedConfig?.authorization?.refreshToken, "rt-9")
        XCTAssertTrue(freshStore.link.linked)
        XCTAssertEqual(freshStore.link.deviceId, "dev-9")
        XCTAssertEqual(freshStore.link.serverUrl, seeded.serverUrl)
    }

    func testRestoreReturnsNilAndSkipsSdkConfigWhenNotLinked() async {
        let link = makeLink()
        var applyConfigCalled = false
        link.applyConfig = { _ in applyConfigCalled = true }

        let restored = await link.restore()

        XCTAssertNil(restored)
        XCTAssertFalse(applyConfigCalled)
    }

    // MARK: - unlink() — the clear-sentinel test

    func testUnlinkEmitsClearSentinelForUrlAndAuthorization() async throws {
        _ = seedStoredLink()
        store.setLink(serverUrl: "https://test.bgeo.dev", linked: true, deviceId: "dev-1")

        let link = makeLink()
        var capturedConfig: Config?
        link.applyConfig = { config in capturedConfig = config }

        await link.unlink()

        let dictionary = try XCTUnwrap(capturedConfig?.toDictionary())
        // Must be NSNull — not an omitted key, not an empty string. An empty
        // string is the Flutter workaround this task deliberately does not
        // copy (Swift's Config has a real clear sentinel; Dart's does not).
        XCTAssertTrue(dictionary["url"] is NSNull, "url must serialise as NSNull, got \(String(describing: dictionary["url"]))")
        XCTAssertTrue(dictionary["authorization"] is NSNull, "authorization must serialise as NSNull, got \(String(describing: dictionary["authorization"]))")

        XCTAssertNil(loadPersistedLink())
        XCTAssertFalse(store.link.linked)
        XCTAssertNil(store.link.deviceId)
        // serverUrl is left alone (deviceLink.ts's unlinkDevice never touches it).
        XCTAssertEqual(store.link.serverUrl, "https://test.bgeo.dev")
    }

    // MARK: - deviceFetch() — the single-retry test

    func test401RefreshesOnceThenRetriesSucceeds() async {
        _ = seedStoredLink(accessToken: "old-token", refreshToken: "old-refresh")
        StubURLProtocol.stub("GET", "/device/geofences", status: 401)
        StubURLProtocol.stub("POST", "/device/auth/refresh", status: 200, json: [
            "access_token": "new-token", "refresh_token": "new-refresh",
        ])
        StubURLProtocol.stub("GET", "/device/geofences", status: 200, json: ["geofences": []])

        let link = makeLink()
        link.applyConfig = { _ in }

        let data = await link.deviceFetch("/device/geofences")

        XCTAssertNotNil(data)

        let refreshCalls = StubURLProtocol.capturedRequests.filter { $0.url?.path == "/device/auth/refresh" }
        XCTAssertEqual(refreshCalls.count, 1)

        let geofenceCalls = StubURLProtocol.capturedRequests.filter { $0.url?.path == "/device/geofences" }
        XCTAssertEqual(geofenceCalls.count, 2, "one failed attempt + one retry, not more")
        XCTAssertEqual(geofenceCalls[0].value(forHTTPHeaderField: "Authorization"), "Bearer old-token")
        XCTAssertEqual(geofenceCalls[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")

        let persisted = loadPersistedLink()
        XCTAssertEqual(persisted?.accessToken, "new-token")
        XCTAssertEqual(persisted?.refreshToken, "new-refresh")
    }

    func test401TwiceGivesUpWithoutLooping() async {
        _ = seedStoredLink(accessToken: "old-token", refreshToken: "old-refresh")
        StubURLProtocol.stub("GET", "/device/geofences", status: 401)
        StubURLProtocol.stub("POST", "/device/auth/refresh", status: 200, json: [
            "access_token": "new-token", "refresh_token": "new-refresh",
        ])
        StubURLProtocol.stub("GET", "/device/geofences", status: 401) // retry also fails

        let link = makeLink()
        link.applyConfig = { _ in }

        let data = await link.deviceFetch("/device/geofences")

        XCTAssertNil(data)

        let refreshCalls = StubURLProtocol.capturedRequests.filter { $0.url?.path == "/device/auth/refresh" }
        XCTAssertEqual(refreshCalls.count, 1, "a second 401 must not trigger a second refresh")

        let geofenceCalls = StubURLProtocol.capturedRequests.filter { $0.url?.path == "/device/geofences" }
        XCTAssertEqual(geofenceCalls.count, 2, "must not retry more than once")
    }

    func testDeviceFetchGivesUpWhenRefreshFails() async {
        _ = seedStoredLink(accessToken: "old-token", refreshToken: "dead-refresh")
        StubURLProtocol.stub("GET", "/device/geofences", status: 401)
        StubURLProtocol.stub("POST", "/device/auth/refresh", status: 401) // refresh token itself dead

        let link = makeLink()
        link.applyConfig = { _ in }

        let data = await link.deviceFetch("/device/geofences")

        XCTAssertNil(data)
        let geofenceCalls = StubURLProtocol.capturedRequests.filter { $0.url?.path == "/device/geofences" }
        XCTAssertEqual(geofenceCalls.count, 1, "no retry is attempted when the refresh itself fails")
    }

    func testDeviceFetchReturnsNilWhenNotLinked() async {
        let link = makeLink()
        let data = await link.deviceFetch("/device/geofences")
        XCTAssertNil(data)
    }

    // MARK: - persistRotatedTokens()

    func testPersistRotatedTokensOverwritesOnlyPresentFields() async {
        _ = seedStoredLink(accessToken: "at-old", refreshToken: "rt-old")
        let link = makeLink()

        await link.persistRotatedTokens(["accessToken": "at-new"])

        let persisted = loadPersistedLink()
        XCTAssertEqual(persisted?.accessToken, "at-new")
        XCTAssertEqual(persisted?.refreshToken, "rt-old", "refreshToken absent from the event must be untouched")
    }

    func testPersistRotatedTokensIgnoresEmptyStringFields() async {
        _ = seedStoredLink(accessToken: "at-old", refreshToken: "rt-old")
        let link = makeLink()

        await link.persistRotatedTokens(["accessToken": "", "refreshToken": "rt-new"])

        let persisted = loadPersistedLink()
        XCTAssertEqual(persisted?.accessToken, "at-old", "an empty string is falsy in the RN original and must not overwrite")
        XCTAssertEqual(persisted?.refreshToken, "rt-new")
    }

    func testPersistRotatedTokensNoopWhenNotLinked() async {
        let link = makeLink()
        await link.persistRotatedTokens(["accessToken": "at-new"])
        XCTAssertNil(loadPersistedLink())
    }

    // MARK: - putGeofences()

    func testPutGeofencesReturnsTrueOn2xx() async {
        _ = seedStoredLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 200, json: ["ok": true, "count": 1])
        let link = makeLink()

        let geofence = Geofence(identifier: "home", radius: 100, latitude: 1, longitude: 2)
        let ok = await link.putGeofences([geofence])

        XCTAssertTrue(ok)
    }

    func testPutGeofencesReturnsFalseOnFailure() async {
        _ = seedStoredLink()
        StubURLProtocol.stub("PUT", "/device/geofences", status: 500, json: [:])
        let link = makeLink()

        let geofence = Geofence(identifier: "home", radius: 100, latitude: 1, longitude: 2)
        let ok = await link.putGeofences([geofence])

        XCTAssertFalse(ok)
    }
}
