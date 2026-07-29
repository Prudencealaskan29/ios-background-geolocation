import Foundation

/// The public BGeo API. Method and event names mirror
/// `react-native/src/index.ts` so a developer moving between SDKs finds the
/// same vocabulary.
///
/// Every method that isn't a pure getter goes through `engine`/`hub` — never
/// `LiveEngine`/`BGeoCore` directly — so the whole surface is testable
/// against `FakeEngine` without a device.
@MainActor
public enum BackgroundGeolocation {

    /// Test seam: defaults to `LiveEngine`, swapped by tests for `FakeEngine`.
    static var engine: Engine = LiveEngine()

    /// Test seam: defaults to a hub attached to `engine`, swapped by tests.
    static var hub: EventHub = {
        let hub = EventHub()
        hub.attach(to: engine)
        return hub
    }()

    // MARK: - Lifecycle

    /// Forces `hub` to be read (and therefore attached to `engine`) before the
    /// first engine interaction of a session. `hub`'s default value attaches
    /// lazily on first access; until something touches it, the engine's
    /// `eventEmitter` slot is nil and events — including the launch-time
    /// `authorization`/`providerchange` CoreLocation can fire before any
    /// listener is registered — are dropped instead of buffered. `attach` is
    /// idempotent, so calling it here is harmless even if a subscriber (or a
    /// test) already attached the hub.
    ///
    /// Applies `config`, THEN checks the license — the engine reads the
    /// license key out of the config it was just given, so a bad license
    /// still leaves `config` applied (`RNBackgroundGeolocation.mm:115-127`).
    @discardableResult
    public static func ready(_ config: Config) async throws -> State {
        hub.attach(to: engine)
        engine.applyConfig(config.toDictionary())
        if let code = engine.licenseErrorCode() {
            throw licenseError(code)
        }
        return State(dictionary: engine.stateDictionary())
    }

    /// Applies `config` and resolves state. Unlike `ready`/`start`, this
    /// never consults the license (`RNBackgroundGeolocation.mm:129-136`).
    @discardableResult
    public static func setConfig(_ config: Config) async throws -> State {
        engine.applyConfig(config.toDictionary())
        return State(dictionary: engine.stateDictionary())
    }

    /// Checks the license BEFORE starting tracking — a bad license must not
    /// start tracking (`RNBackgroundGeolocation.mm:138-148`).
    @discardableResult
    public static func start() async throws -> State {
        if let code = engine.licenseErrorCode() {
            throw licenseError(code)
        }
        engine.startTracking()
        return State(dictionary: engine.stateDictionary())
    }

    /// Never consults the license (`RNBackgroundGeolocation.mm:150-155`).
    @discardableResult
    public static func stop() async throws -> State {
        engine.stopTracking()
        return State(dictionary: engine.stateDictionary())
    }

    public static func getState() async -> State {
        State(dictionary: engine.stateDictionary())
    }

    /// Throws `.disabled` when the engine refuses (tracking is off)
    /// (`RNBackgroundGeolocation.mm:162-171`).
    public static func changePace(_ isMoving: Bool) async throws {
        guard engine.changePace(isMoving) else {
            throw BGeoError(code: "DISABLED", message: "Cannot changePace while tracking is disabled")
        }
    }

    // MARK: - Single-shot / watch

    /// Resolves a single fix. `options.timeout` is in SECONDS (default 30) —
    /// the engine multiplies by 1000 internally to get milliseconds.
    public static func getCurrentPosition(_ options: CurrentPositionOptions = .init()) async throws -> Location {
        let dictionary: [String: Any] = try await withEngineContinuation { resolve, reject in
            engine.getCurrentPosition(options.toDictionary(), resolve: resolve, reject: reject)
        }
        return try decodedLocation(dictionary)
    }

    /// Watch fixes are ordinary `location` events carrying `extras.watch` —
    /// there is no separate channel; subscribe via `locations`/`onLocation`
    /// as normal (`react-native/src/index.ts:167-173`).
    public static func watchPosition(_ options: WatchPositionOptions = .init()) {
        engine.startWatch(options.toDictionary())
    }

    public static func stopWatchPosition() {
        engine.stopWatch()
    }

    // MARK: - Permission / provider

    public static func requestPermission() async throws -> AuthorizationStatus {
        let status: Int = try await withEngineContinuation { resolve, reject in
            engine.requestPermission(resolve: resolve, reject: reject)
        }
        guard let authorizationStatus = AuthorizationStatus(rawValue: status) else {
            throw BGeoError(code: "DECODE_ERROR", message: "Unknown authorization status \(status)")
        }
        return authorizationStatus
    }

    /// `purpose` must be a key in the app's
    /// `NSLocationTemporaryUsageDescriptionDictionary` (see the README's
    /// Info.plist section). **CAUTION:** if it isn't, iOS may never invoke
    /// CoreLocation's completion at all (`react-native/src/index.ts:196-199`
    /// documents the same hazard) — this is the only bridged call in the
    /// package the engine doesn't itself time out. `temporaryFullAccuracyTimeout`
    /// below bounds the wait so the caller cannot hang forever; `ResumeGuard`
    /// makes it safe if CoreLocation's completion arrives after the watchdog
    /// already resumed.
    public static func requestTemporaryFullAccuracy(purpose: String) async -> AccuracyAuthorization {
        let accuracy = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            let resumeGuard = ResumeGuard()
            engine.requestTemporaryFullAccuracy(purpose) { value in
                resumeGuard.runOnce { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(temporaryFullAccuracyTimeout * 1_000_000_000))
                resumeGuard.runOnce { continuation.resume(returning: AccuracyAuthorization.reduced.rawValue) }
            }
        }
        return AccuracyAuthorization(rawValue: accuracy) ?? .reduced
    }

    /// Test seam: bounds the watchdog above, in seconds. Defaults to 30,
    /// consistent with the engine's other timeouts; tests shrink this to
    /// prove the watchdog actually fires without a real 30-second wait.
    static var temporaryFullAccuracyTimeout: Double = 30

    public static func getProviderState() async -> ProviderState {
        ProviderState(dictionary: engine.providerState())
    }

    public static func isPowerSaveMode() async -> Bool {
        engine.isPowerSaveMode()
    }

    // MARK: - Odometer

    public static func getOdometer() async -> Double {
        engine.odometer
    }

    @discardableResult
    public static func setOdometer(_ value: Double) async throws -> Location {
        let dictionary: [String: Any] = try await withEngineContinuation { resolve, reject in
            engine.setOdometer(value, resolve: resolve, reject: reject)
        }
        return try decodedLocation(dictionary)
    }

    /// `resetOdometer` is `setOdometer(0)`, not a distinct engine call
    /// (`react-native/src/index.ts:228-230`).
    @discardableResult
    public static func resetOdometer() async throws -> Location {
        try await setOdometer(0)
    }

    // MARK: - Streams
    //
    // Every property below is computed: each access calls `typedStream`
    // and mints a NEW subscription to the underlying event. `AsyncStream` is
    // single-consumer, so `for await x in BackgroundGeolocation.locations`
    // twice does not fan the same events out to both loops — it creates two
    // independent subscriptions, and if you re-read the property mid-loop
    // (rather than binding it to a `let` once) you silently start a second
    // subscription and leak the first until its task is cancelled.

    /// See the note above `// MARK: - Streams` — each access mints a new
    /// subscription; bind the result to a `let` rather than re-reading this
    /// property.
    public static var locations: AsyncStream<Location> {
        typedStream("location", decode: Location.init(dictionary:))
    }

    /// See `locations`.
    public static var locationErrors: AsyncStream<LocationErrorEvent> {
        typedStream("locationerror", decode: LocationErrorEvent.init(dictionary:))
    }

    /// See `locations`.
    public static var motionChanges: AsyncStream<MotionChangeEvent> {
        typedStream("motionchange", decode: MotionChangeEvent.init(dictionary:))
    }

    /// See `locations`.
    public static var providerChanges: AsyncStream<ProviderChangeEvent> {
        // ProviderChangeEvent (= ProviderState) is non-failable — never dropped.
        typedStream("providerchange") { ProviderChangeEvent(dictionary: $0) }
    }

    /// See `locations`.
    public static var heartbeats: AsyncStream<HeartbeatEvent> {
        typedStream("heartbeat", decode: HeartbeatEvent.init(dictionary:))
    }

    /// See `locations`.
    public static var httpEvents: AsyncStream<HttpEvent> {
        typedStream("http", decode: HttpEvent.init(dictionary:))
    }

    /// See `locations`.
    public static var connectivityChanges: AsyncStream<ConnectivityChangeEvent> {
        typedStream("connectivitychange", decode: ConnectivityChangeEvent.init(dictionary:))
    }

    /// See `locations`.
    public static var powerSaveChanges: AsyncStream<Bool> {
        typedStream("powersavechange", decode: { $0.bool("isPowerSaveMode") })
    }

    /// See `locations`.
    public static var authorizationEvents: AsyncStream<[String: Any]> {
        typedStream("authorization", decode: { $0 })
    }

    // MARK: - Callback equivalents

    @discardableResult
    public static func onLocation(_ handler: @escaping (Location) -> Void) -> Subscription {
        hub.subscribe("location") { dictionary in
            if let location = Location(dictionary: dictionary) {
                handler(location)
            }
        }
    }

    /// The only way to learn `startWatch` refused a bad license, or that a
    /// watch tick failed — see `LocationErrorEvent`'s doc comment.
    @discardableResult
    public static func onLocationError(_ handler: @escaping (LocationErrorEvent) -> Void) -> Subscription {
        hub.subscribe("locationerror") { dictionary in
            if let event = LocationErrorEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    @discardableResult
    public static func onMotionChange(_ handler: @escaping (MotionChangeEvent) -> Void) -> Subscription {
        hub.subscribe("motionchange") { dictionary in
            if let event = MotionChangeEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    @discardableResult
    public static func onProviderChange(_ handler: @escaping (ProviderChangeEvent) -> Void) -> Subscription {
        // ProviderChangeEvent (= ProviderState) is non-failable — never dropped.
        hub.subscribe("providerchange") { dictionary in
            handler(ProviderChangeEvent(dictionary: dictionary))
        }
    }

    @discardableResult
    public static func onHeartbeat(_ handler: @escaping (HeartbeatEvent) -> Void) -> Subscription {
        hub.subscribe("heartbeat") { dictionary in
            if let event = HeartbeatEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    @discardableResult
    public static func onHttp(_ handler: @escaping (HttpEvent) -> Void) -> Subscription {
        hub.subscribe("http") { dictionary in
            if let event = HttpEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    @discardableResult
    public static func onConnectivityChange(_ handler: @escaping (ConnectivityChangeEvent) -> Void) -> Subscription {
        hub.subscribe("connectivitychange") { dictionary in
            if let event = ConnectivityChangeEvent(dictionary: dictionary) {
                handler(event)
            }
        }
    }

    @discardableResult
    public static func onPowerSaveChange(_ handler: @escaping (Bool) -> Void) -> Subscription {
        hub.subscribe("powersavechange") { dictionary in
            if let value = dictionary.bool("isPowerSaveMode") {
                handler(value)
            }
        }
    }

    @discardableResult
    public static func onAuthorization(_ handler: @escaping ([String: Any]) -> Void) -> Subscription {
        hub.subscribe("authorization", handler)
    }

    public static func removeListeners() {
        hub.removeAll()
    }

    // MARK: - Private helpers

    private static func licenseError(_ code: String) -> BGeoError {
        BGeoError(code: code, message: "BGeo license check failed (\(code))")
    }

    private static func decodedLocation(_ dictionary: [String: Any]) throws -> Location {
        guard let location = Location(dictionary: dictionary) else {
            throw BGeoError(code: "DECODE_ERROR", message: "Failed to decode location")
        }
        return location
    }

    /// Bridges an engine `(resolve, reject)` pair — as used by
    /// `getCurrentPosition`, `requestPermission`, `setOdometer` — to an async
    /// throwing call. The engine's callbacks are single-shot by contract, but
    /// `ResumeGuard` still guards against a double resume: `CheckedContinuation`
    /// traps the process if resumed twice, and a silently dropped second
    /// callback is far better than a crash in a shipped app.
    private static func withEngineContinuation<T>(
        _ body: (@escaping (T) -> Void, @escaping (String, String) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let resumeGuard = ResumeGuard()
            body(
                { value in resumeGuard.runOnce { continuation.resume(returning: value) } },
                { code, message in resumeGuard.runOnce { continuation.resume(throwing: BGeoError(code: code, message: message)) } }
            )
        }
    }

    /// An `AsyncStream` view over `hub.subscribe`, decoding each payload and
    /// dropping it (never crashing, never yielding a half-built model) if
    /// decoding fails.
    ///
    /// Not `private`: `BackgroundGeolocation+Geofences.swift` reuses this for
    /// `geofenceEvents`/`geofenceChanges` rather than duplicating the
    /// decode-or-drop `AsyncStream` wiring.
    static func typedStream<T>(_ name: String, decode: @escaping ([String: Any]) -> T?) -> AsyncStream<T> {
        AsyncStream { continuation in
            let subscription = hub.subscribe(name) { dictionary in
                if let value = decode(dictionary) {
                    continuation.yield(value)
                }
            }
            continuation.onTermination = { _ in
                subscription.remove()
            }
        }
    }
}

/// Options for `BackgroundGeolocation.getCurrentPosition`.
public struct CurrentPositionOptions {
    public var persist: Bool?
    public var samples: Int?
    /// SECONDS, default 30 — the engine multiplies this by 1000 internally
    /// to get milliseconds. This has been got wrong before; do not convert
    /// units here.
    public var timeout: Double?
    public var maximumAge: Double?
    public var desiredAccuracy: Int?
    public var extras: [String: Any]?

    public init(
        persist: Bool? = nil,
        samples: Int? = nil,
        timeout: Double? = nil,
        maximumAge: Double? = nil,
        desiredAccuracy: Int? = nil,
        extras: [String: Any]? = nil
    ) {
        self.persist = persist
        self.samples = samples
        self.timeout = timeout
        self.maximumAge = maximumAge
        self.desiredAccuracy = desiredAccuracy
        self.extras = extras
    }

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        if let persist { dictionary["persist"] = persist }
        if let samples { dictionary["samples"] = samples }
        if let timeout { dictionary["timeout"] = timeout }
        if let maximumAge { dictionary["maximumAge"] = maximumAge }
        if let desiredAccuracy { dictionary["desiredAccuracy"] = desiredAccuracy }
        if let extras { dictionary["extras"] = extras }
        return dictionary
    }
}

/// Options for `BackgroundGeolocation.watchPosition`.
public struct WatchPositionOptions {
    public var interval: Double?
    public var desiredAccuracy: Int?
    public var persist: Bool?
    public var extras: [String: Any]?

    public init(
        interval: Double? = nil,
        desiredAccuracy: Int? = nil,
        persist: Bool? = nil,
        extras: [String: Any]? = nil
    ) {
        self.interval = interval
        self.desiredAccuracy = desiredAccuracy
        self.persist = persist
        self.extras = extras
    }

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        if let interval { dictionary["interval"] = interval }
        if let desiredAccuracy { dictionary["desiredAccuracy"] = desiredAccuracy }
        if let persist { dictionary["persist"] = persist }
        if let extras { dictionary["extras"] = extras }
        return dictionary
    }
}

/// Guards a resolve/reject pair against a double resume — `CheckedContinuation`
/// traps the process if resumed twice. The engine's callbacks are single-shot
/// by contract, but a silently dropped second callback beats a crash.
private final class ResumeGuard {
    private var hasResumed = false

    func runOnce(_ body: () -> Void) {
        guard !hasResumed else { return }
        hasResumed = true
        body()
    }
}
