// Keep the app store and the web console in sync with the SDK's geofence set
// (the device is the source of truth). Call after every CRUD operation and on
// onGeofencesChange.
//
// Swift port of `react-native/example/src/geofences.ts`; `flutter/example/lib/
// src/geofences.dart` is the same port for Flutter. `geofences.ts` itself is
// only `syncGeofences()` (this file's `refresh()`) — `add`/`remove` are
// inlined in `GeofenceFormScreen.tsx`'s `onSave`/`onDelete` (SDK call, then
// `await syncGeofences()`, both wrapped in try/catch so a failed SDK call
// never reaches the sync step). `removeAll` has no reference-app call site at
// all (neither RN nor Flutter wires a "clear all" action anywhere), but this
// task's brief names it explicitly as part of `Geofences`'s interface and the
// SDK already exposes `removeGeofences()` — added for that reason, following
// the exact same call-then-sync shape as `add`/`remove` rather than inventing
// a different one.
//
// `add`/`remove`/`removeAll` are all `async throws`, mirroring the try/catch
// RN wraps around every one of these calls (even `removeGeofence`, whose iOS
// facade never actually throws) — see the interior comment on the `Call`
// typealiases below for why the closure seam keeps that shape all the way
// through the test surface.

import Foundation
import BackgroundGeolocation

@MainActor
public final class Geofences {
    private let store: AppStore
    private let deviceLink: DeviceLink

    /// Test seams: `BackgroundGeolocation` is a `@MainActor` enum with static
    /// members, so — same reasoning as `DeviceLink.applyConfig` — it can't be
    /// swapped for a fake directly. Each seam is `throws` even where the
    /// production closure never actually throws (`removeGeofence`/
    /// `removeGeofences`), so a test can inject a failure for any of the
    /// three CRUD paths and assert the snapshot push is skipped — the same
    /// defensive try/catch shape `GeofenceFormScreen.tsx` wraps around every
    /// one of these calls, not just `addGeofence`.
    var addGeofenceCall: (Geofence) async throws -> Void = { try await BackgroundGeolocation.addGeofence($0) }
    var removeGeofenceCall: (String) async throws -> Void = { await BackgroundGeolocation.removeGeofence(identifier: $0) }
    var removeGeofencesCall: () async throws -> Void = { await BackgroundGeolocation.removeGeofences() }
    var getGeofencesCall: () async -> [Geofence] = { await BackgroundGeolocation.getGeofences() }

    public init(store: AppStore, deviceLink: DeviceLink) {
        self.store = store
        self.deviceLink = deviceLink
    }

    /// `geofences.ts`'s `syncGeofences`: read the SDK's current set, update
    /// the store, mirror the snapshot to the console. `putGeofences` is a
    /// no-op (returns false) when not linked.
    ///
    /// The RN original discards that result; this port logs it instead. A
    /// rejected PUT (not linked, expired tokens, server down) is otherwise
    /// completely invisible — the fence is on the device and drawn on the map,
    /// the console just never hears about it, and there is nothing anywhere to
    /// say so.
    public func refresh() async {
        let geofences = await getGeofencesCall()
        store.setGeofences(geofences)
        let pushed = await deviceLink.putGeofences(geofences)
        LogUploader.logEvent(
            "putGeofences",
            message: pushed
                ? "\(geofences.count) mirrored to console"
                : "console not updated (\(geofences.count) local)",
            level: pushed ? .info : .warn,
            store: store
        )
    }

    /// Add a geofence, then sync. A failed SDK call rethrows without ever
    /// calling `refresh()` — the console must not learn about a fence the
    /// device doesn't actually have.
    public func add(_ geofence: Geofence) async throws {
        try await addGeofenceCall(geofence)
        await refresh()
    }

    /// Remove one geofence, then sync. Same failure guard as `add`.
    public func remove(identifier: String) async throws {
        try await removeGeofenceCall(identifier)
        await refresh()
    }

    /// Remove every geofence, then sync. Same failure guard as `add`.
    public func removeAll() async throws {
        try await removeGeofencesCall()
        await refresh()
    }
}
