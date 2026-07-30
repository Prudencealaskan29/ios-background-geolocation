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

    func testResetPushesDefaultsForPreviouslyOverriddenKeys() async {
        let store = makeStore()
        await store.setOverride("distanceFilter", 42.0)
        await store.setOverride("debug", false)

        var captured: Config?
        store.applyConfig = { config in captured = config }
        await store.reset()

        let dictionary = try! XCTUnwrap(captured?.toDictionary())
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

    func testNotificationOverrideLivePatchFillsEverySiblingFromSchemaDefaults() async {
        let store = makeStore()
        var captured: Config?
        store.applyConfig = { config in captured = config }

        await store.setOverride("notification.priority", 2)

        let notification = try! XCTUnwrap(captured?.notification)
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
