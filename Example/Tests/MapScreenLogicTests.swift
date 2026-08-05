import XCTest
import MapKit
@testable import BGeoExample
import BackgroundGeolocation

/// Covers the pure logic pulled out of `MapScreen.swift`/`CoordinatesSheet.swift`
/// — the screens themselves are view code with no unit tests (per the task
/// brief, verified instead by a simulator run; see the task report). This
/// file is the "test the logic instead" half of that rule: track paging,
/// the history-source switch, geofence action coloring, and coordinate/time
/// formatting.
@MainActor
final class MapScreenLogicTests: XCTestCase {

    // MARK: - MapPaging.window

    func testWindowUnderOnePageIsTheWholeRangeOnNewestPage() {
        let window = MapPaging.window(totalCount: 5, page: 0, pageSize: 10)
        XCTAssertEqual(window, MapWindow(effPage: 0, pageCount: 1, windowStart: 0, windowEnd: 5, onNewestPage: true))
    }

    func testWindowExactMultipleOfPageSizeSplitsCleanly() {
        // 2500 points, page size 1000 -> 3 pages (1000, 1000, 500).
        let page0 = MapPaging.window(totalCount: 2500, page: 0, pageSize: 1000)
        XCTAssertEqual(page0, MapWindow(effPage: 0, pageCount: 3, windowStart: 1500, windowEnd: 2500, onNewestPage: true))

        let page1 = MapPaging.window(totalCount: 2500, page: 1, pageSize: 1000)
        XCTAssertEqual(page1, MapWindow(effPage: 1, pageCount: 3, windowStart: 500, windowEnd: 1500, onNewestPage: false))

        let page2 = MapPaging.window(totalCount: 2500, page: 2, pageSize: 1000)
        XCTAssertEqual(page2, MapWindow(effPage: 2, pageCount: 3, windowStart: 0, windowEnd: 500, onNewestPage: false))
    }

    func testWindowClampsAPageRequestPastTheOldestPage() {
        // Only 2 pages exist (1500 points / 1000) — requesting page 9 clamps to page 1 (the oldest).
        let window = MapPaging.window(totalCount: 1500, page: 9, pageSize: 1000)
        XCTAssertEqual(window.effPage, 1)
        XCTAssertEqual(window.windowStart, 0)
        XCTAssertEqual(window.windowEnd, 500)
    }

    func testWindowWithZeroPointsStaysOnASinglePage() {
        let window = MapPaging.window(totalCount: 0, page: 0, pageSize: 1000)
        XCTAssertEqual(window, MapWindow(effPage: 0, pageCount: 1, windowStart: 0, windowEnd: 0, onNewestPage: true))
    }

    func testWindowNegativePageClampsToZero() {
        let window = MapPaging.window(totalCount: 50, page: -3, pageSize: 10)
        XCTAssertEqual(window.effPage, 0)
    }

    // MARK: - MapRebuild.decide (the geofence-pin-churn fix)
    //
    // IMPORTANT-1 from the final review: a live location fix must NOT
    // invalidate the geofence pins/circles, or an open callout is dismissed
    // out from under the user before they can tap the ⓘ accessory. These
    // tests exercise the pure decision function directly — the `MKMapView`
    // wiring around it is view code with no unit tests, same rule as
    // `MapPaging` above.

    private func trackSnapshot(lastKey: String? = "a") -> TrackSnapshot {
        TrackSnapshot(trackKeys: ["a", "b"], eventKeys: [], lastKey: lastKey, lastMoving: true, showPolyline: 2)
    }

    private func geofenceSnapshot(ids: [String] = ["home"], colors: [String] = [GeofenceColors.fallback]) -> GeofenceSnapshot {
        GeofenceSnapshot(geofenceKeys: ids, geofenceColors: colors)
    }

    func testANewLocationFixAloneDoesNotRequestAGeofenceRebuild() {
        let geofences = geofenceSnapshot()
        let decision = MapRebuild.decide(
            track: trackSnapshot(lastKey: "new-fix"),
            previousTrack: trackSnapshot(lastKey: "previous-fix"),
            geofences: geofences,
            previousGeofences: geofences
        )
        XCTAssertTrue(decision.rebuildTrack, "the track/last-point marker must still update")
        XCTAssertFalse(decision.rebuildGeofences, "unchanged geofences must not be torn down by an unrelated location fix")
    }

    func testAGeofenceTransitionRequestsAGeofenceRebuildEvenWithNoTrackChange() {
        let track = trackSnapshot()
        let decision = MapRebuild.decide(
            track: track,
            previousTrack: track,
            geofences: geofenceSnapshot(colors: [GeofenceColors.enter]),
            previousGeofences: geofenceSnapshot(colors: [GeofenceColors.fallback])
        )
        XCTAssertFalse(decision.rebuildTrack)
        XCTAssertTrue(decision.rebuildGeofences, "a real geofence color/set change must still rebuild the pins")
    }

    func testIdenticalSnapshotsRequestNoRebuildAtAll() {
        let track = trackSnapshot()
        let geofences = geofenceSnapshot()
        let decision = MapRebuild.decide(track: track, previousTrack: track, geofences: geofences, previousGeofences: geofences)
        XCTAssertFalse(decision.rebuildTrack)
        XCTAssertFalse(decision.rebuildGeofences)
    }

    func testNoPreviousSnapshotRequestsARebuildOfBoth() {
        let decision = MapRebuild.decide(track: trackSnapshot(), previousTrack: nil, geofences: geofenceSnapshot(), previousGeofences: nil)
        XCTAssertTrue(decision.rebuildTrack, "first layout must draw the track")
        XCTAssertTrue(decision.rebuildGeofences, "first layout must draw the geofences")
    }

    func testAddingOrRemovingAGeofenceRequestsAGeofenceRebuild() {
        let track = trackSnapshot()
        let decision = MapRebuild.decide(
            track: track,
            previousTrack: track,
            geofences: geofenceSnapshot(ids: ["home", "work"], colors: [GeofenceColors.fallback, GeofenceColors.fallback]),
            previousGeofences: geofenceSnapshot(ids: ["home"], colors: [GeofenceColors.fallback])
        )
        XCTAssertTrue(decision.rebuildGeofences)
    }

    // MARK: - GeofenceSnapshot.build (round 2 regression: identifier-only keys
    // silently swallowed a radius/geometry edit — this is the actual
    // key-construction logic the bug lived in, extracted out of
    // `Coordinator.applyOverlaysAndAnnotationsIfNeeded` specifically so it's
    // testable without `MKMapView`.)

    func testGeofenceSnapshotBuildKeysOnGeometryNotJustIdentifier() {
        let original = Geofence(identifier: "home", radius: 100, latitude: 52.5, longitude: 13.4)
        let editedRadius = Geofence(identifier: "home", radius: 250, latitude: 52.5, longitude: 13.4)

        let before = GeofenceSnapshot.build(from: [original], colorHex: { _ in GeofenceColors.fallback })
        let after = GeofenceSnapshot.build(from: [editedRadius], colorHex: { _ in GeofenceColors.fallback })

        XCTAssertNotEqual(before, after, "editing a geofence's radius (same identifier, same color) must change the snapshot key")
    }

    // MARK: - Coordinator wiring (integration-level, deliberately touching
    // MKMapView/MKCircle rather than only `MapRebuild.decide`: the re-review
    // found the five `decide`-only tests above stay green even if the
    // Coordinator is reverted to a single combined rebuild, so they don't
    // actually guard the behaviour they're named for. These two exercise the
    // real `Coordinator.applyOverlaysAndAnnotationsIfNeeded` call the app
    // makes, which is the seam both round-1's fix and round-2's regression
    // actually live in.)

    func testEditingAGeofenceRadiusRepaintsItsCircleThroughTheRealCoordinator() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let original = Geofence(identifier: "home", radius: 100, latitude: 52.5, longitude: 13.4)
        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [], geofenceEvents: [],
            geofences: [original], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: nil, isMoving: false
        )
        XCTAssertEqual(mapView.overlays.compactMap { $0 as? MKCircle }.first?.radius, 100)

        // Same identifier, same color — only the radius changed (exactly
        // what the edit form allows, since it disables the identifier field).
        let editedRadius = Geofence(identifier: "home", radius: 250, latitude: 52.5, longitude: 13.4)
        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [], geofenceEvents: [],
            geofences: [editedRadius], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: nil, isMoving: false
        )

        XCTAssertEqual(
            mapView.overlays.compactMap { $0 as? MKCircle }.first?.radius, 250,
            "editing a geofence's radius must repaint the MKCircle with the new radius"
        )
    }

    func testAnUnrelatedLocationFixDoesNotTearDownAnUnchangedGeofenceCircleInstance() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let geofence = Geofence(identifier: "home", radius: 100, latitude: 52.5, longitude: 13.4)
        let pointA = Point(latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")
        let pointB = Point(latitude: 1.001, longitude: 2, timestamp: "2026-07-01T00:00:05Z")

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointA], geofenceEvents: [],
            geofences: [geofence], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointA, isMoving: true
        )
        let circleBefore = mapView.overlays.compactMap { $0 as? MKCircle }.first

        // A new location fix changes the track/last-point snapshot but not
        // the geofence list at all — pre-round-1, a single combined rebuild
        // would tear down and recreate every overlay (including this circle)
        // on every fix.
        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointB], geofenceEvents: [],
            geofences: [geofence], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointB, isMoving: true
        )
        let circleAfter = mapView.overlays.compactMap { $0 as? MKCircle }.first

        XCTAssertTrue(circleBefore === circleAfter, "an unrelated location fix must not tear down/rebuild an unchanged geofence circle")
    }

    // MARK: - Track-dot diffing (the "everything blinks while following" fix)
    //
    // The track half used to be rebuilt wholesale on every accepted fix:
    // every dot annotation removed and a fresh one added, plus a new
    // "last point" annotation. MapKit answered by destroying and re-hosting
    // up to `MapPaging.pageSize` annotation views per fix, which is what the
    // user saw as the marker, the polyline and the whole dot layer blinking.
    // These tests pin the incremental behaviour that replaced it.

    private func dotAnnotations(_ mapView: MKMapView) -> [DotAnnotation] {
        mapView.annotations.compactMap { $0 as? DotAnnotation }
    }

    func testANewFixKeepsTheAlreadyDrawnTrackDotsAndOnlyAddsTheNewOne() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let pointA = Point(uuid: "a", latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")
        let pointB = Point(uuid: "b", latitude: 1.001, longitude: 2, timestamp: "2026-07-01T00:00:05Z")

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointA], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointA, isMoving: true
        )
        let dotForA = try! XCTUnwrap(dotAnnotations(mapView).first { $0.kind == .track })

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointA, pointB], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointB, isMoving: true
        )

        let trackDots = dotAnnotations(mapView).filter { $0.kind == .track }
        XCTAssertEqual(trackDots.count, 2)
        XCTAssertTrue(
            trackDots.contains { $0 === dotForA },
            "the dot already on the map must survive the next fix, not be torn down and recreated"
        )
    }

    func testANewFixMovesTheSameLastPointAnnotationInsteadOfReplacingIt() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let pointA = Point(uuid: "a", latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")
        let pointB = Point(uuid: "b", latitude: 1.001, longitude: 2.002, timestamp: "2026-07-01T00:00:05Z")

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointA], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointA, isMoving: false
        )
        let markerBefore = try! XCTUnwrap(dotAnnotations(mapView).first { $0.kind == .last(moving: false) })

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointA, pointB], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointB, isMoving: true
        )

        let markers = dotAnnotations(mapView).filter { if case .last = $0.kind { return true } else { return false } }
        XCTAssertEqual(markers.count, 1, "exactly one current-position marker, ever")
        XCTAssertTrue(markers[0] === markerBefore, "the marker must be moved, not removed and re-added")
        XCTAssertEqual(markerBefore.coordinate.latitude, 1.001)
        XCTAssertEqual(markerBefore.coordinate.longitude, 2.002)
        XCTAssertEqual(markerBefore.kind, .last(moving: true), "moving/stationary must still follow the fix")
    }

    func testADotThatLeavesTheWindowIsRemovedFromTheMap() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let pointA = Point(uuid: "a", latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")
        let pointB = Point(uuid: "b", latitude: 1.001, longitude: 2, timestamp: "2026-07-01T00:00:05Z")

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointA, pointB], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointB, isMoving: true
        )
        XCTAssertEqual(dotAnnotations(mapView).filter { $0.kind == .track }.count, 2)

        // The window slid past `pointA` (what paging past `MapPaging.pageSize`
        // points does) — its dot must go with it.
        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [pointB], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointB, isMoving: true
        )

        let trackDots = dotAnnotations(mapView).filter { $0.kind == .track }
        XCTAssertEqual(trackDots.count, 1)
        XCTAssertEqual(trackDots.first?.point.uuid, "b")
    }

    /// Points carry no guaranteed-unique key (`uuid` is optional and the
    /// fallback `timestamp` can repeat), so the diff's keying has to survive a
    /// collision without silently dropping a dot.
    func testTwoPointsSharingAKeyStillDrawTwoDots() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let same = Point(latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: [], trackPoints: [same, same], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: nil, isMoving: false
        )

        XCTAssertEqual(dotAnnotations(mapView).filter { $0.kind == .track }.count, 2)
    }

    func testTheTrackPolylineIsNeverAbsentBetweenTwoFixes() {
        let mapView = MKMapView()
        let coordinator = TrackMapView.Coordinator()
        let line = [CLLocationCoordinate2D(latitude: 1, longitude: 2), CLLocationCoordinate2D(latitude: 1.001, longitude: 2)]
        let pointA = Point(uuid: "a", latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: line, trackPoints: [pointA], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointA, isMoving: true
        )
        let polylineBefore = try! XCTUnwrap(mapView.overlays.compactMap { $0 as? MKPolyline }.first)

        coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView, polyline: line + [CLLocationCoordinate2D(latitude: 1.002, longitude: 2)],
            trackPoints: [pointA], geofenceEvents: [],
            geofences: [], geofenceColorHex: { _ in GeofenceColors.fallback },
            lastPoint: pointA, isMoving: true
        )

        let polylines = mapView.overlays.compactMap { $0 as? MKPolyline }
        XCTAssertEqual(polylines.count, 1, "the previous polyline must be removed once the new one is up")
        XCTAssertFalse(polylines[0] === polylineBefore)
        XCTAssertEqual(polylines[0].pointCount, 3)
    }

    // MARK: - GeofenceColors

    func testGeofenceColorsMapEachActionCaseInsensitively() {
        XCTAssertEqual(GeofenceColors.hex(forAction: "ENTER"), GeofenceColors.enter)
        XCTAssertEqual(GeofenceColors.hex(forAction: "enter"), GeofenceColors.enter)
        XCTAssertEqual(GeofenceColors.hex(forAction: "Exit"), GeofenceColors.exit)
        XCTAssertEqual(GeofenceColors.hex(forAction: "dwell"), GeofenceColors.dwell)
    }

    func testGeofenceColorsFallsBackForUnknownOrMissingAction() {
        XCTAssertEqual(GeofenceColors.hex(forAction: "SOMETHING_ELSE"), GeofenceColors.fallback)
        XCTAssertEqual(GeofenceColors.hex(forAction: nil), GeofenceColors.fallback)
    }

    // `HistoryLoader`'s tests (filterPointsByRange, point(fromServerJSON:),
    // load) moved to `HistoryTests.swift` when Task 7 promoted the type out
    // of `MapScreen.swift` into `Sources/History.swift`.

    // MARK: - parseISODate

    func testParseISODateAcceptsFractionalAndPlainSeconds() {
        XCTAssertNotNil(parseISODate("2026-07-01T12:00:00.123Z"))
        XCTAssertNotNil(parseISODate("2026-07-01T12:00:00Z"))
        XCTAssertNil(parseISODate("not-a-date"))
    }

    // MARK: - PointFormat

    func testPointFormatTimeFormatsLocalWallClock() {
        // Fixed instant so the test is deterministic regardless of the CI
        // machine's timezone: format, then re-derive expected H:M:S the same
        // way the formatter does (local `Calendar.current`), rather than
        // hardcoding a specific timezone's clock time.
        let iso = "2026-07-01T12:34:56Z"
        let date = parseISODate(iso)!
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let expected = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        XCTAssertEqual(PointFormat.time(fromISO: iso), expected)
    }

    func testPointFormatTimeFallsBackOnUnparsableTimestamp() {
        XCTAssertEqual(PointFormat.time(fromISO: "garbage"), "--:--:--")
    }

    func testPointFormatCoordinateFixedDigits() {
        XCTAssertEqual(PointFormat.coordinate(52.123456789), "52.12346")
    }

    func testPointFormatNonNegativeDashesOutMissingOrNegative() {
        XCTAssertEqual(PointFormat.nonNegative(nil, digits: 1), "–")
        XCTAssertEqual(PointFormat.nonNegative(-1, digits: 1), "–")
        XCTAssertEqual(PointFormat.nonNegative(3.14, digits: 1), "3.1")
    }

    func testPointFormatRoundedOrDashHandlesNilAndNormalValues() {
        XCTAssertEqual(PointFormat.roundedOrDash(nil), "–")
        XCTAssertEqual(PointFormat.roundedOrDash(4.6), "5")
    }

    /// The exact crash class this repo hit three times: `Int(_:)` on an
    /// out-of-range `Double` traps. `roundedOrDash` must degrade instead.
    func testPointFormatRoundedOrDashDoesNotTrapOnHugeMagnitude() {
        let huge = 1.0e21
        XCTAssertNoThrow(_ = PointFormat.roundedOrDash(huge))
        XCTAssertEqual(PointFormat.roundedOrDash(huge), String(format: "%.0f", huge))
    }

    func testPointFormatHeadingDashesOutNegativeOrMissing() {
        XCTAssertEqual(PointFormat.heading(nil), "–")
        XCTAssertEqual(PointFormat.heading(-1), "–")
        XCTAssertEqual(PointFormat.heading(270.4), "270°")
    }

    func testPointFormatIsMovingTristate() {
        XCTAssertEqual(PointFormat.isMoving(nil), "–")
        XCTAssertEqual(PointFormat.isMoving(true), "yes")
        XCTAssertEqual(PointFormat.isMoving(false), "no")
    }

    func testPointFormatEventLabelForGeofencePoint() {
        let point = Point(
            latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z",
            event: "geofence", geofence: PointGeofence(identifier: "home", action: "enter")
        )
        XCTAssertEqual(PointFormat.eventLabel(point), "home · ENTER")
    }

    func testPointFormatEventLabelForGeofencePointWithoutAction() {
        let point = Point(
            latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z",
            event: "geofence", geofence: PointGeofence(identifier: "home")
        )
        XCTAssertEqual(PointFormat.eventLabel(point), "home")
    }

    func testPointFormatEventLabelForNonGeofencePoint() {
        let point = Point(latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z", event: "motionchange")
        XCTAssertEqual(PointFormat.eventLabel(point), "motionchange")

        let noEvent = Point(latitude: 1, longitude: 2, timestamp: "2026-07-01T00:00:00Z")
        XCTAssertEqual(PointFormat.eventLabel(noEvent), "-")
    }
}
