import XCTest
@testable import BGeoExample
import BackgroundGeolocation

@MainActor
final class ConfigStoreTests: XCTestCase {
    var suiteName: String!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ConfigStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// `applyConfig` defaults to a no-op so tests don't touch the live SDK;
    /// individual tests override it again when they need to capture the patch.
    private func makeStore() -> ConfigStore {
        let store = ConfigStore(userDefaults: defaults)
        store.applyConfig = { _ in }
        return store
    }

    // MARK: - persistence round-trip

    func testOverrideRoundTripsThroughPersistenceAcrossFreshInstances() async {
        let store = makeStore()
        await store.setOverride("distanceFilter", 42.0)
        await store.setOverride("debug", false)

        // A brand new ConfigStore instance, same UserDefaults suite — not
        // just re-reading the same instance, which would prove nothing about
        // persistence.
        let fresh = ConfigStore(userDefaults: defaults)
        XCTAssertEqual(fresh.overrides["distanceFilter"] as? Double, 42.0)
        XCTAssertEqual(fresh.overrides["debug"] as? Bool, false)
    }

    func testFreshStoreWithNoStoredOverridesStartsEmpty() {
        let store = makeStore()
        XCTAssertTrue(store.overrides.isEmpty)
    }

    func testSetOverridePushesLiveConfigImmediately() async {
        let store = makeStore()
        var captured: Config?
        store.applyConfig = { config in captured = config }

        await store.setOverride("distanceFilter", 42.0)

        XCTAssertEqual(captured?.distanceFilter, 42.0)
    }

    // MARK: - merged()

    func testMergedAppliesOverrideOverBaseAndLeavesUntouchedKeysAlone() async {
        let store = makeStore()
        await store.setOverride("distanceFilter", 42.0)

        let base = Config(distanceFilter: 10, stopTimeout: 5, debug: true)
        let merged = store.merged(into: base)

        XCTAssertEqual(merged.distanceFilter, 42.0, "overridden key must reflect the override")
        XCTAssertEqual(merged.stopTimeout, 5, "untouched key must retain base's value")
        XCTAssertEqual(merged.debug, true, "untouched key must retain base's value")
    }

    func testMergedWithNoOverridesReturnsBaseUnchanged() {
        let store = makeStore()
        let base = Config(distanceFilter: 10, stationaryDesiredAccuracy: "LOW", stopTimeout: 5)
        let merged = store.merged(into: base)

        XCTAssertEqual(merged.distanceFilter, 10)
        XCTAssertEqual(merged.stopTimeout, 5)
        XCTAssertEqual(merged.stationaryDesiredAccuracy, "LOW")
    }

    func testMergedNotificationOverlayLeavesBaseSiblingFieldsAlone() async {
        // The critical case `overlayNotificationOverrides` exists for: base
        // already set notification.channelId (not via this store), and only
        // notification.priority is overridden. The channelId must survive —
        // NOT get reset to the schema default, which would be the wrong
        // (PATCH-oriented) behaviour for a boot-time merge.
        let store = makeStore()
        await store.setOverride("notification.priority", 1)

        let base = Config(notification: NotificationConfig(channelId: "custom-channel"))
        let merged = store.merged(into: base)

        XCTAssertEqual(merged.notification?.priority, 1, "the overridden field must apply")
        XCTAssertEqual(merged.notification?.channelId, "custom-channel", "untouched sibling field must survive from base")
        XCTAssertNil(merged.notification?.title, "a field base never set and no override touches stays nil")
    }

    func testMergedWithoutNotificationOverrideLeavesBaseNotificationUntouched() {
        let store = makeStore()
        let base = Config(notification: NotificationConfig(title: "Custom"))
        let merged = store.merged(into: base)
        XCTAssertEqual(merged.notification?.title, "Custom")
    }

    // MARK: - reset()

    func testResetClearsOverridesAndDoesNotSurviveAFreshInstance() async {
        let store = makeStore()
        await store.setOverride("distanceFilter", 42.0)
        await store.setOverride("debug", false)
        XCTAssertFalse(store.overrides.isEmpty)

        await store.reset()

        XCTAssertTrue(store.overrides.isEmpty)
        let fresh = ConfigStore(userDefaults: defaults)
        XCTAssertTrue(fresh.overrides.isEmpty, "reset must not survive a fresh instance")
    }

    func testResetPushesDefaultsForPreviouslyOverriddenKeys() async throws {
        let store = makeStore()
        await store.setOverride("distanceFilter", 42.0)
        await store.setOverride("debug", false)

        var captured: Config?
        store.applyConfig = { config in captured = config }
        await store.reset()

        let dictionary = try XCTUnwrap(captured?.toDictionary())
        XCTAssertEqual(dictionary["distanceFilter"] as? Double, 10.0, "distanceFilter's schema default")
        XCTAssertEqual(dictionary["debug"] as? Bool, true, "debug's schema default")
    }

    func testResetWithNoOverridesDoesNotCallApplyConfig() async {
        let store = makeStore()
        var called = false
        store.applyConfig = { _ in called = true }

        await store.reset()

        XCTAssertFalse(called)
    }

    // MARK: - notification.* nested-patch safety (the wholesale-replace rule)

    func testNotificationOverrideLivePatchFillsEverySiblingFromSchemaDefaults() async throws {
        let store = makeStore()
        var captured: Config?
        store.applyConfig = { config in captured = config }

        await store.setOverride("notification.priority", 2)

        let notification = try XCTUnwrap(captured?.notification)
        let dictionary = notification.toDictionary()
        XCTAssertEqual(dictionary["priority"] as? Int, 2, "the field that actually changed")
        // Every OTHER notification field must also be present — proving the
        // patch was rebuilt wholesale, not just the one changed key. Without
        // this, pushing {notification: {priority: 2}} to the engine would
        // wipe title/text/channelId/etc previously set by an earlier call.
        XCTAssertEqual(dictionary["title"] as? String, "Location")
        XCTAssertEqual(dictionary["text"] as? String, "Location tracking active")
        XCTAssertEqual(dictionary["channelId"] as? String, "bgeo_location_min")
        XCTAssertEqual(dictionary["channelName"] as? String, "Location")
        XCTAssertEqual(dictionary["smallIcon"] as? String, "")
        XCTAssertEqual(dictionary["color"] as? String, "")
    }

    func testNotificationOverrideLivePatchPrefersExistingOverrideOverDefaultForSiblings() async {
        let store = makeStore()
        await store.setOverride("notification.title", "Custom title")

        var captured: Config?
        store.applyConfig = { config in captured = config }
        await store.setOverride("notification.priority", 1)

        // The sibling `title` override set a moment ago must survive into
        // THIS patch too, not get reset to the schema default.
        XCTAssertEqual(captured?.notification?.title, "Custom title")
        XCTAssertEqual(captured?.notification?.priority, 1)
    }

    // MARK: - type-mismatched overrides must not clobber base's value
    //
    // A persisted override can be the wrong type — e.g. a pre-phase-0 RN
    // install left a numeric `stationaryDesiredAccuracy` (the un-fixed
    // scale) in UserDefaults, and after upgrading to the corrected string
    // enum, `ConfigCoerce.string(-1)` returns nil. `ConfigStore.apply`'s
    // `set(_:_:)` helper must skip the assignment in that case, not write
    // `nil` over whatever `base` already had — the exact same clobber shape
    // `overlayNotificationOverrides` was written to avoid, but on the scalar
    // switch rather than the notification one.

    func testTypeMismatchedScalarOverrideDoesNotClobberBaseValueOnMergedPath() async {
        let store = makeStore()
        // Simulates the legacy numeric stationaryDesiredAccuracy sitting in
        // UserDefaults from before the phase-0 string-enum fix.
        await store.setOverride("stationaryDesiredAccuracy", -1)

        let base = Config(stationaryDesiredAccuracy: "BALANCED")
        let merged = store.merged(into: base)

        XCTAssertEqual(merged.stationaryDesiredAccuracy, "BALANCED", "a type-mismatched override must not erase base's value")
    }

    func testTypeMismatchedNotificationOverrideDoesNotClobberBaseSiblingOnMergedPath() async {
        let store = makeStore()
        await store.setOverride("notification.priority", "not-a-number")

        let base = Config(notification: NotificationConfig(priority: 1))
        let merged = store.merged(into: base)

        XCTAssertEqual(merged.notification?.priority, 1, "a type-mismatched override must not erase base's value")
    }

    // MARK: - numeric text parsing must never crash (Int(exactly:) not Int())

    func testNumberFromTextRejectsIntOverflowInsteadOfTrapping() {
        // Double(text) parses fine (~1.1e21); Int(1.1e21) would TRAP via the
        // non-failable initializer. This exact string is reachable by typing
        // 22 digits into a "Max batch size"-style field.
        XCTAssertNil(ConfigCoerce.numberFromText("1100000000000000000000", matching: .int(50)))
    }

    func testNumberFromTextParsesValidIntWithinRange() {
        XCTAssertEqual(ConfigCoerce.numberFromText("42", matching: .int(50)) as? Int, 42)
    }

    func testNumberFromTextParsesDoubleFieldsAsDoubleEvenForHugeMagnitudes() {
        // Double fields never call Int(exactly:), so a huge value is fine.
        XCTAssertEqual(ConfigCoerce.numberFromText("1100000000000000000000", matching: .double(10)) as? Double, 1.1e21)
    }

    func testNumberFromTextRejectsUnparsableText() {
        XCTAssertNil(ConfigCoerce.numberFromText("not-a-number", matching: .int(5)))
    }

    // MARK: - display-string formatting must never crash either (the same
    // crash class as numberFromText, on the read side). numberFromText
    // deliberately lets a huge magnitude through for `.double`-kind fields
    // (a Double never traps on write) — so the very next render of that
    // field has to format it, and the naive `String(Int(v))` traps exactly
    // where `numberFromText`'s naive `Int(parsed)` used to.

    func testDisplayStringFormatsHugeDoubleWithoutTrappingInsteadOfCrashing() {
        // Reachable by typing 22 digits into ANY .double-kind field
        // (distanceFilter, stationaryRadius, locationFilterMaxAccuracy, ...)
        // — numberFromText lets this straight into `overrides` as a Double.
        let huge = 1.1e21
        XCTAssertEqual(ConfigCoerce.displayString(for: huge), String(huge), "must fall back to the plain Double description, not trap")
    }

    func testDisplayStringRendersInRangeWholeDoubleWithoutTrailingDecimal() {
        XCTAssertEqual(ConfigCoerce.displayString(for: 42.0), "42", "the original whole-number formatting intent must survive the fix")
    }

    func testDisplayStringRendersFractionalDoubleAsIs() {
        XCTAssertEqual(ConfigCoerce.displayString(for: 42.5), "42.5")
    }

    func testDisplayStringRendersOtherValueKinds() {
        XCTAssertEqual(ConfigCoerce.displayString(for: true), "true")
        XCTAssertEqual(ConfigCoerce.displayString(for: "hello"), "hello")
        XCTAssertEqual(ConfigCoerce.displayString(for: 7), "7")
    }

    // MARK: - drift guard: every non-notification schema key maps to a real
    // Config property, exercised through the actual ConfigStore.apply switch
    // (not asserted by inspection — this is a live round-trip test, so a
    // missing/mistyped switch case fails it).

    func testEveryNonNotificationSchemaKeyRoundTripsThroughMerged() async {
        let store = makeStore()
        var expected: [String: Any] = [:]
        for field in Self.nonNotificationFields {
            let value = Self.distinctOverride(for: field)
            await store.setOverride(field.key, value)
            expected[field.key] = value
        }

        let dictionary = store.merged(into: Config()).toDictionary()

        for field in Self.nonNotificationFields {
            Self.assertMatches(dictionary[field.key], expected[field.key], field: field)
        }
    }

    func testEveryNotificationSchemaKeyRoundTripsThroughMerged() async {
        let store = makeStore()
        let notificationFields = configSections.first(where: { $0.title == "Notification" })!.fields
        var expected: [String: Any] = [:]
        for field in notificationFields {
            let value = Self.distinctOverride(for: field)
            await store.setOverride(field.key, value)
            expected[field.key] = value
        }

        let notification = store.merged(into: Config()).notification
        let dictionary = notification?.toDictionary() ?? [:]

        for field in notificationFields {
            let sub = String(field.key.dropFirst("notification.".count))
            Self.assertMatches(dictionary[sub], expected[field.key], field: field)
        }
    }

    /// The reverse direction of the drift guard above: walks `Config`'s ACTUAL
    /// stored properties (via `Mirror`, so this can't itself drift out of
    /// sync with `Config.swift` the way a hardcoded name list could) and
    /// asserts every one is either in the schema or in the documented
    /// exclusion list from `ConfigSchema.swift`'s header comment. Mirrors the
    /// SDK's own `ConfigDriftTests.testConfigCoversExactlyTheKeysTypesTSDeclares`
    /// shape, including the "assert the expected count, update deliberately"
    /// guard against the property list itself drifting unnoticed.
    func testEveryConfigPropertyIsInTheSchemaOrDocumentedAsExcluded() {
        let configPropertyNames = Set(Mirror(reflecting: Config()).children.compactMap(\.label))
        XCTAssertEqual(configPropertyNames.count, 57, "Config's property count changed — update this expectation deliberately")

        let schemaPropertyNames = Set(Self.nonNotificationFields.map(\.key)).union(["notification"])

        // From ConfigSchema.swift's header comment — keep these two lists in
        // sync by hand; this test's job is to catch anything belonging to
        // NEITHER, not to own the reasoning for why each is excluded.
        let documentedExclusions: Set<String> = [
            "foregroundService", "backgroundPermissionRationale", // documented no-ops
            "locationAuthorizationAlert", "headers", "params", "extras", // dictionary types
            "url", "logUrl", "authorization", // DeviceLink-owned
        ]

        let uncovered = configPropertyNames.subtracting(schemaPropertyNames).subtracting(documentedExclusions)
        XCTAssertTrue(uncovered.isEmpty, "Config properties with neither a schema entry nor a documented exclusion: \(uncovered.sorted())")

        // The exclusion list itself must stay accurate — every name in it
        // really is a Config property, and none of them snuck into the
        // schema without the comment being updated (which would make the
        // exclusion claim false).
        let staleExclusions = documentedExclusions.subtracting(configPropertyNames)
        XCTAssertTrue(staleExclusions.isEmpty, "documented exclusions that aren't real Config properties: \(staleExclusions.sorted())")
        let exclusionsNowInSchema = documentedExclusions.intersection(schemaPropertyNames)
        XCTAssertTrue(exclusionsNowInSchema.isEmpty, "keys documented as excluded but now present in the schema — update the header comment: \(exclusionsNowInSchema.sorted())")
    }

    // MARK: - test helpers

    private static var nonNotificationFields: [ConfigField] {
        configSections.flatMap(\.fields).filter { !$0.key.hasPrefix("notification.") }
    }

    /// A value of the same underlying type as `field.defaultValue`, but
    /// guaranteed different from it — so a round trip that silently no-ops
    /// (e.g. a missing switch case leaving the property untouched, which
    /// would otherwise coincidentally already equal a zero-ish default)
    /// cannot pass by accident.
    private static func distinctOverride(for field: ConfigField) -> Any {
        switch field.defaultValue {
        case .bool(let value): return !value
        case .int(let value): return value + 4242
        case .double(let value): return value + 4242.5
        case .string(let value): return value + "-test-override"
        }
    }

    private static func assertMatches(_ actual: Any?, _ expected: Any?, field: ConfigField, file: StaticString = #filePath, line: UInt = #line) {
        switch field.defaultValue {
        case .bool:
            XCTAssertEqual(actual as? Bool, expected as? Bool, "key \"\(field.key)\"", file: file, line: line)
        case .int:
            XCTAssertEqual(actual as? Int, expected as? Int, "key \"\(field.key)\"", file: file, line: line)
        case .double:
            XCTAssertEqual(actual as? Double, expected as? Double, "key \"\(field.key)\"", file: file, line: line)
        case .string:
            XCTAssertEqual(actual as? String, expected as? String, "key \"\(field.key)\"", file: file, line: line)
        }
    }
}
