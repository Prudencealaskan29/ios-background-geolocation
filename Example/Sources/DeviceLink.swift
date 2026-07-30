// Links this install to a BGeo account using a registration code from the
// web console, then points the SDK's native uploader at the demo server with
// JWT auth (native refresh via refreshUrl survives killed-app uploads).
//
// This is a Swift port of `react-native/example/src/deviceLink.ts` (the
// cross-client contract); `flutter/example/lib/src/device_link.dart` is the
// same port for Flutter. One deliberate divergence from both: `unlink()`
// clears `url`/`authorization` via `Config.clearString`/`AuthorizationConfig.clear`
// (phase 1's clear sentinel) rather than Flutter's empty-string workaround —
// Swift's `Config.toDictionary()` can express a true "unset this key" the way
// Flutter's `Config.toMap()` cannot. See `Config.clearString`'s doc comment.

import Foundation
import UIKit
import BackgroundGeolocation

/// Persisted device link: server, device id and JWT pair, plus the
/// once-generated install UUID sent on every registration.
public struct StoredLink: Codable, Equatable {
    public var serverUrl: String
    public var deviceId: String
    public var accessToken: String
    public var refreshToken: String
    public var installUuid: String

    public init(serverUrl: String, deviceId: String, accessToken: String, refreshToken: String, installUuid: String) {
        self.serverUrl = serverUrl
        self.deviceId = deviceId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.installUuid = installUuid
    }
}

/// Surfaces the server's own error message (`detail`, falling back to
/// `error`, falling back to a generic "register failed (<status>)") — what a
/// developer sees when their registration code is wrong.
public struct DeviceLinkError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// `@MainActor class`, not `actor`: every non-trivial method here ends by
/// calling either `AppStore.setLink` or `BackgroundGeolocation.setConfig`,
/// both themselves `@MainActor`-isolated. An `actor` would add a hop across
/// the actor boundary on every single call for no benefit — nothing in this
/// type does concurrent work that needs an actor's mutual exclusion; the
/// network calls are awaited sequentially one at a time, same as the RN/
/// Flutter originals. `@MainActor` keeps call sites hop-free and lets the
/// example's UI layer (already `@MainActor` via SwiftUI) call straight
/// through, matching `AppStore`'s own choice.
@MainActor
public final class DeviceLink {
    private static let linkKey = "bgeo:link"
    private static let installUuidKey = "bgeo:installUuid"

    private let store: AppStore
    private let session: URLSession
    private let defaults: UserDefaults

    /// Test seam: `BackgroundGeolocation` is a `@MainActor enum` with static
    /// members, so it cannot be swapped for a fake the way `Engine` is inside
    /// the SDK itself. Injecting a closure here — rather than (a) a protocol
    /// wrapping the enum, which would need a second production implementation
    /// that just forwards to the static calls for no behavioural gain, or (b)
    /// a global mutable "current engine" seam duplicating one the SDK already
    /// has internally — lets tests assert on exactly the `Config` handed to
    /// `setConfig` with a single stored property and no new protocol surface.
    var applyConfig: (Config) async throws -> Void = { config in
        try await BackgroundGeolocation.setConfig(config)
    }

    public init(store: AppStore, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.store = store
        self.session = session
        self.defaults = defaults
    }

    // MARK: - Install UUID

    private func installUuid() -> String {
        if let existing = defaults.string(forKey: Self.installUuidKey) {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Self.installUuidKey)
        return fresh
    }

    // MARK: - Persistence

    private func loadStoredLink() -> StoredLink? {
        guard let data = defaults.data(forKey: Self.linkKey) else { return nil }
        return try? JSONDecoder().decode(StoredLink.self, from: data)
    }

    private func saveStoredLink(_ link: StoredLink) {
        guard let data = try? JSONEncoder().encode(link) else { return }
        defaults.set(data, forKey: Self.linkKey)
    }

    private func clearStoredLink() {
        defaults.removeObject(forKey: Self.linkKey)
    }

    // MARK: - SDK config

    private func applySdkConfig(_ link: StoredLink) async throws {
        let config = Config(
            logUrl: "\(link.serverUrl)/device/logs",
            url: "\(link.serverUrl)/device/locations",
            autoSync: true,
            batchSync: true,
            maxBatchSize: 50,
            authorization: AuthorizationConfig(
                strategy: "JWT",
                accessToken: link.accessToken,
                refreshToken: link.refreshToken,
                refreshUrl: "\(link.serverUrl)/device/auth/refresh",
                refreshPayload: ["refresh_token": "{refreshToken}"]
            )
        )
        try await applyConfig(config)
    }

    // MARK: - Public API

    /// Restore a persisted link on app start (returns nil when not linked).
    /// Deliberately non-throwing (unlike `link`): a best-effort SDK-config
    /// apply failure at launch shouldn't crash the restore path — the persisted
    /// link and store update still succeed either way.
    public func restore() async -> StoredLink? {
        guard let link = loadStoredLink() else { return nil }
        try? await applySdkConfig(link)
        store.setLink(serverUrl: link.serverUrl, linked: true, deviceId: link.deviceId)
        return link
    }

    /// Exchange a registration code for device tokens and configure the SDK.
    public func link(serverUrl: String, code: String) async throws -> StoredLink {
        guard let url = URL(string: "\(serverUrl)/device/register") else {
            throw DeviceLinkError("invalid server URL")
        }
        let uuid = installUuid()
        let devicePayload: [String: Any] = [
            "uuid": uuid,
            "model": "iPhone",
            "platform": "ios",
            "osVersion": UIDevice.current.systemVersion,
            "appVersion": "0.0.1",
            "name": "BGeoExample (ios)",
        ]
        let body: [String: Any] = [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "device": devicePayload,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeviceLinkError("register failed (no response)")
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let detail = errorBody.string("detail") ?? errorBody.string("error")
            throw DeviceLinkError(detail ?? "register failed (\(http.statusCode))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceId = json.string("device_id"),
              let accessToken = json.string("access_token"),
              let refreshToken = json.string("refresh_token") else {
            throw DeviceLinkError("register response malformed")
        }

        let link = StoredLink(
            serverUrl: serverUrl,
            deviceId: deviceId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            installUuid: uuid
        )
        saveStoredLink(link)
        try await applySdkConfig(link)
        store.setLink(serverUrl: serverUrl, linked: true, deviceId: link.deviceId)
        return link
    }

    /// Persist rotated tokens surfaced by the native uploader (onAuthorization).
    /// Only overwrites fields actually present (and non-empty) in `event` —
    /// mirrors `deviceLink.ts`'s truthy check (`if (event?.accessToken)`).
    public func persistRotatedTokens(_ event: [String: Any]) async {
        guard var link = loadStoredLink() else { return }
        if let accessToken = event["accessToken"] as? String, !accessToken.isEmpty {
            link.accessToken = accessToken
        }
        if let refreshToken = event["refreshToken"] as? String, !refreshToken.isEmpty {
            link.refreshToken = refreshToken
        }
        saveStoredLink(link)
    }

    /// Clears persistence and unsets the SDK's `url`/`authorization` via the
    /// clear sentinel (see the file header). Deliberately non-throwing, same
    /// reasoning as `restore()`.
    public func unlink() async {
        clearStoredLink()
        try? await applyConfig(Config(url: Config.clearString, authorization: AuthorizationConfig.clear))
        store.setLink(linked: false, clearDeviceId: true)
    }

    /// Authorized fetch against the linked demo server with one 401-refresh
    /// retry. Returns raw response data, or nil when not linked / the request
    /// failed. A second 401 (after a successful refresh) gives up rather than
    /// looping — a dead refresh token must not be retried indefinitely.
    public func deviceFetch(_ path: String, method: String = "GET", body: Encodable? = nil) async -> Data? {
        guard let link = loadStoredLink() else { return nil }
        guard let url = URL(string: "\(link.serverUrl)\(path)") else { return nil }

        func send(_ token: String) async -> (Data, HTTPURLResponse)? {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = try? JSONEncoder().encode(body)
            }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else {
                return nil
            }
            return (data, http)
        }

        guard var result = await send(link.accessToken) else { return nil }
        if result.1.statusCode == 401 {
            guard let fresh = await refreshTokens() else { return nil }
            guard let retried = await send(fresh.accessToken) else { return nil }
            result = retried
        }
        guard (200...299).contains(result.1.statusCode) else { return nil }
        return result.0
    }

    /// Mirror the SDK's geofence set to the console (snapshot replace).
    public func putGeofences(_ geofences: [Geofence]) async -> Bool {
        let payload = GeofencesPayload(geofences: geofences.map(GeofencePayload.init))
        let data = await deviceFetch("/device/geofences", method: "PUT", body: payload)
        return data != nil
    }

    /// Refresh helper shared between `deviceFetch`'s retry and (in a later
    /// task) the log uploader — the Swift-side twin of the native refresh
    /// cycle. Not part of this task's public interface list; kept internal so
    /// `@testable import` still reaches it.
    func refreshTokens() async -> StoredLink? {
        guard var link = loadStoredLink(),
              let url = URL(string: "\(link.serverUrl)/device/auth/refresh") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": link.refreshToken])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json.string("access_token"),
              let refreshToken = json.string("refresh_token") else {
            return nil
        }

        link.accessToken = accessToken
        link.refreshToken = refreshToken
        saveStoredLink(link)
        try? await applySdkConfig(link)
        return link
    }
}

// MARK: - Geofence JSON payload

/// `Geofence` isn't `Encodable` (its `extras` is `[String: Any]?`), so
/// `putGeofences` needs a small Encodable mirror to go through `deviceFetch`'s
/// `body: Encodable?` seam. `AnyJSONValue` boxes `extras`' values (the only
/// untyped part) so the whole payload can still ride `JSONEncoder`.
private struct GeofencesPayload: Encodable {
    let geofences: [GeofencePayload]
}

private struct GeofencePayload: Encodable {
    let identifier: String
    let radius: Double
    let latitude: Double
    let longitude: Double
    let notifyOnEntry: Bool?
    let notifyOnExit: Bool?
    let notifyOnDwell: Bool?
    let loiteringDelay: Double?
    let extras: [String: AnyJSONValue]?

    init(_ geofence: Geofence) {
        identifier = geofence.identifier
        radius = geofence.radius
        latitude = geofence.latitude
        longitude = geofence.longitude
        notifyOnEntry = geofence.notifyOnEntry
        notifyOnExit = geofence.notifyOnExit
        notifyOnDwell = geofence.notifyOnDwell
        loiteringDelay = geofence.loiteringDelay
        extras = geofence.extras?.mapValues(AnyJSONValue.init)
    }
}

/// Minimal `Encodable` box for JSON-safe `Any` values (String, Bool, numeric,
/// Array, Dictionary, NSNull) — just enough to carry `Geofence.extras`
/// through `JSONEncoder`. Not a general-purpose type; scoped to this file.
private struct AnyJSONValue: Encodable {
    let value: Any

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as [String: Any]: try container.encode(v.mapValues(AnyJSONValue.init))
        case let v as [Any]: try container.encode(v.map(AnyJSONValue.init))
        default: try container.encodeNil()
        }
    }
}

// MARK: - JSON dictionary helpers

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
}
