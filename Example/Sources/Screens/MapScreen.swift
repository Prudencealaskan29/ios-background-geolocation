// Map screen — current position, the accumulated track, geofence circles,
// start/stop + get-position controls, a from/to history range selector and
// the coordinates sheet.
//
// Swift port of `react-native/example/src/screens/MapScreen.tsx` (568 lines,
// the largest screen in the app); `flutter/example/lib/src/screens/
// map_screen.dart` is a file-for-file port of the same screen and corroborates
// every decision made here.
//
// **Action-list ruling (coordinator-confirmed, corrects task-4's brief):**
// this screen owns `requestPermission`, `getCurrentPosition`, `start`, `stop`
// — kept OFF `SettingsScreen` for exactly this reason (see that file's header
// comment). `sync`/`destroyLocations`/`uploadLog`/`resetOdometer`/`getState`/
// `getCount`/`getLog`/`requestTemporaryFullAccuracy`/`changePace`/`destroyLog`
// stay on Settings; nothing here duplicates them.
//
// **MapKit via `MKMapView`, not SwiftUI's `Map`.** RN uses `react-native-maps`
// (Apple Maps on iOS) rather than Google Maps because a Google provider needs
// an API key that would break the build for anyone cloning the repo — the
// Flutter example (OSM tiles) made the same call for the same reason. This
// port stays on MapKit for the same reason, but wraps `MKMapView` directly
// via `UIViewRepresentable` instead of adopting SwiftUI's own `Map` view.
// Reason: SwiftUI's `Map` only gained overlay content (`MapPolyline`,
// `MapCircle`) in iOS 17 — this app's deployment target is 15.5, and the
// track polyline + geofence circles are load-bearing, not optional chrome.
// Building two divergent rendering paths (an `if #available(iOS 17, *)`
// branch with overlays, and a materially degraded pre-17 fallback with none)
// is more code and more risk than one `MKMapView` wrapper that has supported
// every feature this screen needs since iOS 4. Marker CONTENT is still a
// "plain SwiftUI annotation" as directed: `DotMarker` (a real SwiftUI `View`)
// is hosted inside a custom `MKAnnotationView` via `UIHostingController` —
// MapKit has no counterpart to the `react-native-maps` custom-marker-view bug
// that forces RN to bundle PNG icons (see `DotMarker.swift`'s header).
//
// **`State`/`LogLevel` collision** (flagged by Task 4's report for this file):
// every `@State` property wrapper below is written `@SwiftUI.State`; `LogLevel`
// is left unqualified, which resolves to this module's own `AppStore.LogLevel`
// (same-module lookup wins over the imported `BackgroundGeolocation.LogLevel`),
// exactly as Task 4 found for `SettingsScreen.swift`.

import SwiftUI
import MapKit
import BackgroundGeolocation

// MARK: - Task 6 seam

/// What the geofence form needs to open: a long-press (new fence, no
/// `identifier`) or a tap on an existing fence's pin (edit). Swift port of
/// RN's two `navigation.navigate('GeofenceForm', {...})` call shapes
/// (`MapScreen.tsx:194-199` and `:238-244`). Task 6 supplies the real
/// `onGeofenceRequest` closure (presenting `GeofenceFormScreen`); this screen
/// is fully functional on its own with the default no-op.
public struct GeofenceRequest: Equatable {
    public let latitude: Double
    public let longitude: Double
    public let identifier: String?

    public init(latitude: Double, longitude: Double, identifier: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.identifier = identifier
    }
}

// MARK: - Pure logic (tested — see the task report for why the rest is view-only)

/// The track window over a (possibly very long) point list. Swift port of the
/// paging math inline in `MapScreen.tsx:61-72` — pulled out here because it's
/// exactly the kind of decimation logic the task brief calls out as testable
/// even though the screen around it is not.
public struct MapWindow: Equatable {
    public let effPage: Int
    public let pageCount: Int
    public let windowStart: Int
    public let windowEnd: Int
    public let onNewestPage: Bool
}

public enum MapPaging {
    /// RN's `PAGE_SIZE`: markers are native views and get slow in the
    /// thousands, so the map only ever draws a window of at most this many
    /// points (parity with the web console).
    public static let pageSize = 1000

    /// `page` 0 = the newest `pageSize` points (follows live); higher pages
    /// step back through history. `page` is clamped into range the same way
    /// RN's `effPage = Math.min(page, pageCount - 1)` does.
    public static func window(totalCount: Int, page: Int, pageSize: Int = MapPaging.pageSize) -> MapWindow {
        guard pageSize > 0 else {
            return MapWindow(effPage: 0, pageCount: 1, windowStart: 0, windowEnd: totalCount, onNewestPage: true)
        }
        // `Int(exactly:)`-guarded: totalCount/pageSize is always small in
        // practice (AppStore caps points at 2000), but a raw `Int(ceil(...))`
        // is exactly the trap class this repo has hit three times before.
        let rawPageCount = (Double(totalCount) / Double(pageSize)).rounded(.up)
        let pageCount = max(1, Int(exactly: rawPageCount) ?? Int.max)
        let effPage = min(max(page, 0), pageCount - 1)
        let windowEnd = totalCount - effPage * pageSize
        let windowStart = max(0, windowEnd - pageSize)
        return MapWindow(effPage: effPage, pageCount: pageCount, windowStart: windowStart, windowEnd: windowEnd, onNewestPage: effPage == 0)
    }
}

/// Geofence transition colors — parity with the web console's `TrackMap` and
/// RN's `GEOFENCE_ACTION_COLOR`/`GEOFENCE_FALLBACK_COLOR`
/// (`MapScreen.tsx:33-38`). Returns hex strings (not `Color`) so this stays
/// trivially unit-testable without pulling `Color`'s non-`Equatable`-friendly
/// comparison into the test.
public enum GeofenceColors {
    public static let enter = "#22C55E"
    public static let exit = "#EF4444"
    public static let dwell = "#F59E0B"
    public static let fallback = "#F97316"
    public static let track = "#3A6FF0"

    public static func hex(forAction action: String?) -> String {
        switch action?.uppercased() {
        case "ENTER": return enter
        case "EXIT": return exit
        case "DWELL": return dwell
        default: return fallback
        }
    }
}

// `HistoryLoader` (the range selector's data source, a Swift port of
// `history.ts`) lives in `Sources/History.swift` as of Task 7 — promoted out
// of this file so it stays independently testable and this file stops
// growing. See that file's header for why the type/method names were kept
// as-is rather than renamed to the task-7 brief's `History.locations(range:)`
// paraphrase. This screen calls the exact same `HistoryLoader.load`/
// `filterPointsByRange`/`point(fromServerJSON:)` it always has.

// MARK: - Screen

public struct MapScreen: View {
    @ObservedObject private var appStore: AppStore
    @ObservedObject private var themeStore: ThemeStore
    private let deviceLink: DeviceLink
    private let onGeofenceRequest: (GeofenceRequest) -> Void

    @Environment(\.colorScheme) private var systemColorScheme

    public init(
        appStore: AppStore,
        themeStore: ThemeStore,
        deviceLink: DeviceLink,
        onGeofenceRequest: @escaping (GeofenceRequest) -> Void = { _ in }
    ) {
        self.appStore = appStore
        self.themeStore = themeStore
        self.deviceLink = deviceLink
        self.onGeofenceRequest = onGeofenceRequest
    }

    @SwiftUI.State private var follow = true
    @SwiftUI.State private var mapType: MKMapType = .standard
    @SwiftUI.State private var showMarkers = true
    @SwiftUI.State private var showPolylines = true
    @SwiftUI.State private var showGeofences = true
    @SwiftUI.State private var panelOpen = true
    @SwiftUI.State private var fromDraft: Date?
    @SwiftUI.State private var toDraft: Date?
    @SwiftUI.State private var historyPoints: [Point]?
    @SwiftUI.State private var loading = false
    @SwiftUI.State private var page = 0
    @SwiftUI.State private var fittedPage = 0
    @SwiftUI.State private var cameraCommandID = 0
    @SwiftUI.State private var cameraTarget: TrackMapView.CameraTarget?

    private var scheme: Scheme {
        switch themeStore.mode {
        case .system: return systemColorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var colors: ThemeColors { palette[scheme] ?? lightColors }

    private var rangeActive: Bool { historyPoints != nil }
    private var displayPoints: [Point] { historyPoints ?? appStore.points }
    private var window: MapWindow { MapPaging.window(totalCount: displayPoints.count, page: page) }
    private var trackView: [Point] {
        guard window.windowStart < window.windowEnd, window.windowEnd <= displayPoints.count else { return [] }
        return Array(displayPoints[window.windowStart..<window.windowEnd])
    }
    private var last: Point? { displayPoints.last }

    /// Latest geofence transition per region in the window — mirrors
    /// `MapScreen.tsx:162-178`'s `geofenceActionColor`/`geofenceEvents` memo.
    private var geofenceEventData: (colorByIdentifier: [String: String], events: [(Point, String)]) {
        guard showGeofences else { return ([:], []) }
        let known = Set(appStore.geofences.map(\.identifier))
        var colorByIdentifier: [String: String] = [:]
        var events: [(Point, String)] = []
        for p in trackView where p.event == "geofence" {
            let hex = GeofenceColors.hex(forAction: p.geofence?.action)
            events.append((p, hex))
            if let id = p.geofence?.identifier, known.contains(id) {
                colorByIdentifier[id] = hex
            }
        }
        return (colorByIdentifier, events)
    }

    private var initialCenter: CLLocationCoordinate2D {
        guard let last else { return CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405) }
        return CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            let geofenceData = geofenceEventData
            TrackMapView(
                mapType: mapType,
                isDark: scheme == .dark,
                polyline: showPolylines && trackView.count > 1
                    ? trackView.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } : [],
                trackPoints: showMarkers ? trackView : [],
                geofenceEvents: geofenceData.events,
                geofences: showGeofences ? appStore.geofences : [],
                geofenceColorHex: { geofenceData.colorByIdentifier[$0] ?? GeofenceColors.fallback },
                lastPoint: window.onNewestPage ? last : nil,
                isMoving: appStore.status.isMoving,
                initialCenter: initialCenter,
                cameraTarget: cameraTarget,
                onLongPress: { coordinate in
                    onGeofenceRequest(GeofenceRequest(latitude: coordinate.latitude, longitude: coordinate.longitude))
                },
                onGeofenceTap: { geofence in
                    onGeofenceRequest(GeofenceRequest(latitude: geofence.latitude, longitude: geofence.longitude, identifier: geofence.identifier))
                },
                onUserPan: { follow = false }
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("map.mapView")

            VStack(alignment: .leading, spacing: 8) {
                statusRow
                controlCard
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
        }
        .overlay(alignment: .bottomTrailing) { fabColumn }
        .overlay(alignment: .bottomLeading) { if window.pageCount > 1 { pager } }
        .overlay(alignment: .bottom) { CoordinatesSheet(points: displayPoints, colors: colors) }
        // No `.onAppear` camera command here: `TrackMapView.makeUIView` already
        // sets the map's initial region to `initialCenter` once, unanimated,
        // at creation. An `.onAppear`-issued animated re-center to that exact
        // same coordinate used to duplicate that work — see
        // `Coordinator.applyCameraIfNeeded`'s no-op guard for why that was
        // more than just redundant.
        .onChange(of: appStore.points.count) { _ in maybeFollowLive() }
        .onChange(of: window.effPage) { _ in maybeFitPage() }
        .background(colors.background)
    }

    // MARK: - camera

    private func moveCamera(_ kind: TrackMapView.CameraKind) {
        cameraCommandID += 1
        cameraTarget = TrackMapView.CameraTarget(id: cameraCommandID, kind: kind)
    }

    /// `MapScreen.tsx:75-79`: while following live tracking (not browsing
    /// history, on the newest page), re-center on every new point.
    private func maybeFollowLive() {
        guard follow, !rangeActive, window.onNewestPage, let last else { return }
        moveCamera(.center(CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude), zoom: nil))
    }

    /// `MapScreen.tsx:82-92`: fit the camera to the window when the user
    /// pages through history.
    private func maybeFitPage() {
        guard fittedPage != window.effPage else { return }
        fittedPage = window.effPage
        guard trackView.count > 1 else { return }
        moveCamera(.fit(trackView.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }))
    }

    // MARK: - actions

    private func toggleTracking() async {
        if appStore.status.enabled {
            _ = try? await BackgroundGeolocation.stop()
            appStore.setStatus(enabled: false)
            log("stop", "tracking stopped", .info)
        } else {
            do {
                _ = try await BackgroundGeolocation.requestPermission()
            } catch {
                log("requestPermission", error.localizedDescription, .error)
            }
            do {
                _ = try await BackgroundGeolocation.start()
                appStore.setStatus(enabled: true)
                log("start", "tracking started", .info)
            } catch {
                log("start", error.localizedDescription, .error)
            }
        }
    }

    private func getPosition() async {
        do {
            let location = try await BackgroundGeolocation.getCurrentPosition(CurrentPositionOptions(samples: 1, timeout: 30))
            log("getCurrentPosition", String(format: "%.6f, %.6f", location.coords.latitude, location.coords.longitude), .info)
        } catch {
            log("getCurrentPosition", error.localizedDescription, .error)
        }
    }

    private func applyRange() async {
        guard fromDraft != nil || toDraft != nil else { return }
        loading = true
        follow = false
        let points = await HistoryLoader.load(from: fromDraft, to: toDraft, linked: appStore.link.linked, localPoints: appStore.points, deviceLink: deviceLink)
        historyPoints = points
        loading = false
        page = 0
        fittedPage = 0
        // Fit to the newest window of the range — that's what the map will draw.
        let windowPoints = Array(points.suffix(MapPaging.pageSize))
        if windowPoints.count > 1 {
            moveCamera(.fit(windowPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }))
        }
    }

    private func resetRange() {
        historyPoints = nil
        fromDraft = nil
        toDraft = nil
        page = 0
    }

    private func recenter() {
        if let last {
            moveCamera(.center(CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude), zoom: 15))
        }
        follow = true
    }

    private func log(_ event: String, _ message: String, _ level: LogLevel) {
        appStore.appendLog(LogLine(ts: isoTimestamp(), level: level, event: event, message: message))
    }

    // MARK: - subviews

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appStore.status.ready ? (appStore.status.enabled ? colors.success : colors.textDim) : colors.warning)
                .frame(width: 10, height: 10)
            Text(appStore.link.linked ? "linked" : "not linked")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(colors.text)
            if appStore.link.linked, let deviceId = appStore.link.deviceId {
                Text(String(deviceId.prefix(8)))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textDim)
            }
            Spacer()
            Text("● \(appStore.status.isMoving ? "moving" : "stationary")")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(appStore.status.isMoving ? colors.successText : colors.textDim)
            if let batteryLevel = appStore.status.batteryLevel {
                Text("\(Int((batteryLevel * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(colors.textDim)
            }
            Text("·").font(.system(size: 13, design: .monospaced)).foregroundColor(colors.textDim)
            Text("\(displayPoints.count) pts\(rangeActive ? " (hist)" : "")")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(colors.warningText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(colors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await toggleTracking() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: appStore.status.enabled ? "stop.fill" : "play.fill")
                        Text(appStore.status.enabled ? "Stop" : "Start").fontWeight(.bold)
                    }
                    .frame(height: 46).padding(.horizontal, 18)
                }
                .foregroundColor(colors.onAccent)
                .background(appStore.status.enabled ? colors.danger : colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("map.startStopButton")

                Button {
                    Task { await getPosition() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location")
                        Text("Get position").fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 46)
                }
                .foregroundColor(colors.text)
                .background(colors.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button { panelOpen.toggle() } label: {
                    Image(systemName: panelOpen ? "chevron.up" : "chevron.down")
                        .foregroundColor(colors.textDim)
                        .frame(width: 46, height: 46)
                }
                .background(colors.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if panelOpen {
                HStack(spacing: 8) {
                    layerToggle("Follow", active: follow) { follow.toggle() }
                    layerToggle("Pts", active: showMarkers) { showMarkers.toggle() }
                    layerToggle("Line", active: showPolylines) { showPolylines.toggle() }
                    layerToggle("Geo", active: showGeofences) { showGeofences.toggle() }
                }

                HStack(spacing: 8) {
                    DateTimeField(label: "From", value: $fromDraft)
                    DateTimeField(label: "To", value: $toDraft, placeholder: "now")
                    if loading {
                        ProgressView().tint(colors.accent)
                    } else {
                        Button("Apply") { Task { await applyRange() } }
                            .disabled(fromDraft == nil && toDraft == nil)
                            .opacity(fromDraft == nil && toDraft == nil ? 0.4 : 1)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(colors.onAccent)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if rangeActive {
                        Button("Live") { resetRange() }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(colors.onAccent)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(10)
        .background(colors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func layerToggle(_ label: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle().fill(active ? colors.onAccent : colors.textDim).frame(width: 5, height: 5)
                Text(label).font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 14).frame(height: 38)
        }
        .foregroundColor(active ? colors.onAccent : colors.textDim)
        .background(active ? colors.accent : colors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var fabColumn: some View {
        VStack(spacing: 12) {
            Button { mapType = mapType == .standard ? .satellite : .standard } label: {
                Image(systemName: mapType == .satellite ? "square.stack.3d.up.fill" : "map")
                    .foregroundColor(colors.text)
                    .frame(width: 48, height: 48)
            }
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6, y: 3)

            Button { recenter() } label: {
                Image(systemName: follow ? "location.fill" : "location")
                    .foregroundColor(follow ? colors.onAccent : colors.text)
                    .frame(width: 48, height: 48)
            }
            .disabled(follow)
            .background(follow ? colors.accent : colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6, y: 3)
            .accessibilityIdentifier("map.recenterButton")
        }
        .padding(.trailing, 14)
        .padding(.bottom, sheetPeekHeight + 24)
    }

    private var pager: some View {
        HStack(spacing: 2) {
            Button { page = window.effPage + 1 } label: {
                Text("‹").font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .disabled(window.effPage >= window.pageCount - 1)
            .opacity(window.effPage >= window.pageCount - 1 ? 0.4 : 1)

            Text("\(window.windowStart + 1)–\(window.windowEnd) / \(displayPoints.count)\(window.onNewestPage && !rangeActive ? " · live" : "")")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))

            Button { page = max(0, window.effPage - 1) } label: {
                Text("›").font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .disabled(window.onNewestPage)
            .opacity(window.onNewestPage ? 0.4 : 1)
        }
        .foregroundColor(colors.text)
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(colors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.leading, 14)
        .padding(.bottom, sheetPeekHeight + 24)
    }
}

private func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

// MARK: - MKMapView wrapper

/// Thin `UIViewRepresentable` over `MKMapView` — see this file's header for
/// why `MKMapView` directly rather than SwiftUI's `Map`.
struct TrackMapView: UIViewRepresentable {

    enum CameraKind: Equatable {
        case center(CLLocationCoordinate2D, zoom: Double?)
        case fit([CLLocationCoordinate2D])

        static func == (lhs: CameraKind, rhs: CameraKind) -> Bool {
            switch (lhs, rhs) {
            case let (.center(c1, z1), .center(c2, z2)):
                return c1.latitude == c2.latitude && c1.longitude == c2.longitude && z1 == z2
            case let (.fit(a), .fit(b)):
                return a.count == b.count && zip(a, b).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
            default:
                return false
            }
        }
    }

    struct CameraTarget: Equatable {
        let id: Int
        let kind: CameraKind
    }

    var mapType: MKMapType
    var isDark: Bool
    var polyline: [CLLocationCoordinate2D]
    var trackPoints: [Point]
    var geofenceEvents: [(Point, String)]
    var geofences: [Geofence]
    var geofenceColorHex: (String) -> String
    var lastPoint: Point?
    var isMoving: Bool
    var initialCenter: CLLocationCoordinate2D
    var cameraTarget: CameraTarget?
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onGeofenceTap: (Geofence) -> Void
    var onUserPan: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        // This initial region-set is programmatic too — mark it the same way
        // `applyCameraIfNeeded` marks its own calls, otherwise the delegate
        // sees the flag at its unset `false` default when this (reliably
        // real, first-ever) region change reports back, misreads it as a
        // user pan, and disengages Follow before the map has even finished
        // appearing.
        context.coordinator.markProgrammaticRegionChange()
        mapView.setRegion(MKCoordinateRegion(center: initialCenter, latitudinalMeters: 1200, longitudinalMeters: 1200), animated: false)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        // MKMapView installs its own pan/pinch/rotate recognizers, which by
        // default block a newly-added recognizer from recognizing at the same
        // time — the tiny jitter in a held touch is enough for MapKit's own
        // pan recognizer to win the exclusivity race and starve a long press
        // that never gets a chance to fire. The delegate below opts this
        // recognizer into simultaneous recognition instead.
        longPress.delegate = context.coordinator
        mapView.addGestureRecognizer(longPress)
        context.coordinator.mapView = mapView
        context.coordinator.longPressRecognizer = longPress
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        mapView.overrideUserInterfaceStyle = isDark ? .dark : .light

        context.coordinator.onLongPress = onLongPress
        context.coordinator.onGeofenceTap = onGeofenceTap
        context.coordinator.onUserPan = onUserPan

        context.coordinator.applyOverlaysAndAnnotationsIfNeeded(
            mapView: mapView,
            polyline: polyline,
            trackPoints: trackPoints,
            geofenceEvents: geofenceEvents,
            geofences: geofences,
            geofenceColorHex: geofenceColorHex,
            lastPoint: lastPoint,
            isMoving: isMoving
        )
        context.coordinator.applyCameraIfNeeded(mapView: mapView, target: cameraTarget)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        weak var mapView: MKMapView?
        weak var longPressRecognizer: UILongPressGestureRecognizer?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        var onGeofenceTap: ((Geofence) -> Void)?
        var onUserPan: (() -> Void)?

        private var isProgrammaticRegionChange = false
        private var lastAppliedCameraID: Int?
        private var lastSnapshot: Snapshot?
        private var circleColorByObjectID: [ObjectIdentifier: String] = [:]

        /// Marks the next `regionDidChangeAnimated` callback as ours — used
        /// both by `applyCameraIfNeeded` and by `makeUIView`'s own initial
        /// `setRegion` call, which doesn't go through `applyCameraIfNeeded`
        /// at all but is exactly as programmatic.
        func markProgrammaticRegionChange() {
            isProgrammaticRegionChange = true
        }

        struct Snapshot: Equatable {
            let trackKeys: [String]
            let eventKeys: [String]
            let geofenceIDs: [String]
            let geofenceColors: [String]
            let lastKey: String?
            let lastMoving: Bool?
            let showPolyline: Int // polyline.count, coarse enough to detect on/off + growth
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView else { return }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onLongPress?(coordinate)
        }

        func applyCameraIfNeeded(mapView: MKMapView, target: CameraTarget?) {
            guard let target, target.id != lastAppliedCameraID else { return }
            lastAppliedCameraID = target.id

            switch target.kind {
            case let .center(coordinate, zoom):
                // A plain re-center (no zoom change) to a coordinate the map
                // is already centered on is a no-op `MKMapView` is not
                // guaranteed to report back through `regionDidChangeAnimated`
                // — that delegate callback is `isProgrammaticRegionChange`'s
                // ONLY reset path. An unreported no-op would leave the flag
                // stuck `true`, and the next real region change (a genuine
                // user pan) would be misread as this command's tail: the
                // delegate would consume the stuck flag, reset it, and
                // return WITHOUT calling `onUserPan()` — Follow would
                // silently stay engaged through the user's first drag. Skip
                // the call entirely rather than risk that; nothing to
                // animate toward if the map is already there.
                guard zoom != nil || !Self.isSameCoordinate(coordinate, mapView.centerCoordinate) else {
                    return
                }
                isProgrammaticRegionChange = true
                if let zoom {
                    let span = MKCoordinateSpan(latitudeDelta: 360 / pow(2, zoom), longitudeDelta: 360 / pow(2, zoom))
                    mapView.setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: true)
                } else {
                    mapView.setCenter(coordinate, animated: true)
                }
            case let .fit(coordinates):
                guard coordinates.count > 1 else { return }
                isProgrammaticRegionChange = true
                let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
                mapView.setVisibleMapRect(
                    line.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 180, left: 40, bottom: 60, right: 40),
                    animated: true
                )
            }
        }

        /// Sub-degree epsilon (~0.1mm at the equator) — treats two
        /// coordinates as "the same place" for the no-op guard above without
        /// depending on exact `Double` equality.
        private static func isSameCoordinate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, epsilon: Double = 1e-9) -> Bool {
            abs(a.latitude - b.latitude) < epsilon && abs(a.longitude - b.longitude) < epsilon
        }

        func applyOverlaysAndAnnotationsIfNeeded(
            mapView: MKMapView,
            polyline: [CLLocationCoordinate2D],
            trackPoints: [Point],
            geofenceEvents: [(Point, String)],
            geofences: [Geofence],
            geofenceColorHex: (String) -> String,
            lastPoint: Point?,
            isMoving: Bool
        ) {
            let geofenceColors = geofences.map(\.identifier).map(geofenceColorHex)
            let snapshot = Snapshot(
                trackKeys: trackPoints.map { $0.uuid ?? $0.timestamp },
                eventKeys: geofenceEvents.map { ($0.0.uuid ?? $0.0.timestamp) + "|" + $0.1 },
                geofenceIDs: geofences.map(\.identifier),
                geofenceColors: geofenceColors,
                lastKey: lastPoint.map { $0.uuid ?? $0.timestamp },
                lastMoving: lastPoint == nil ? nil : isMoving,
                showPolyline: polyline.count
            )
            guard snapshot != lastSnapshot else { return }
            lastSnapshot = snapshot

            mapView.removeOverlays(mapView.overlays)
            circleColorByObjectID.removeAll()
            if polyline.count > 1 {
                mapView.addOverlay(MKPolyline(coordinates: polyline, count: polyline.count))
            }
            for geofence in geofences {
                let circle = MKCircle(
                    center: CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude),
                    radius: geofence.radius
                )
                circleColorByObjectID[ObjectIdentifier(circle)] = geofenceColorHex(geofence.identifier)
                mapView.addOverlay(circle)
            }

            let toRemove = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(toRemove)

            var newAnnotations: [MKAnnotation] = trackPoints.map { DotAnnotation(point: $0, kind: .track) }
            newAnnotations += geofenceEvents.map { DotAnnotation(point: $0.0, kind: .geofenceEvent(hex: $0.1)) }
            newAnnotations += geofences.map { GeofencePinAnnotation(geofence: $0, hexColor: geofenceColorHex($0.identifier)) }
            if let lastPoint {
                newAnnotations.append(DotAnnotation(point: lastPoint, kind: .last(moving: isMoving)))
            }
            mapView.addAnnotations(newAnnotations)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(hex: GeofenceColors.track)
                renderer.lineWidth = 3
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let hex = circleColorByObjectID[ObjectIdentifier(circle)] ?? GeofenceColors.fallback
                let color = UIColor(hex: hex)
                renderer.strokeColor = color
                renderer.lineWidth = 2
                renderer.fillColor = color.withAlphaComponent(0.12)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let pin = annotation as? GeofencePinAnnotation {
                let identifier = "geofencePin"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.markerTintColor = UIColor(hex: pin.hexColor)
                view.canShowCallout = true
                view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
                return view
            }
            if let dot = annotation as? DotAnnotation {
                let identifier = "dot"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? DotHostingAnnotationView)
                    ?? DotHostingAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.configure(kind: dot.kind)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let pin = view.annotation as? GeofencePinAnnotation else { return }
            onGeofenceTap?(pin.geofence)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange {
                isProgrammaticRegionChange = false
                return
            }
            onUserPan?()
        }
    }
}

// MARK: - Annotations

final class DotAnnotation: NSObject, MKAnnotation {
    enum Kind: Equatable {
        case track
        case geofenceEvent(hex: String)
        case last(moving: Bool)
    }

    let point: Point
    let kind: Kind
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude) }

    init(point: Point, kind: Kind) {
        self.point = point
        self.kind = kind
    }
}

final class GeofencePinAnnotation: NSObject, MKAnnotation {
    let geofence: Geofence
    let hexColor: String
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude) }
    var title: String? { geofence.identifier }
    var subtitle: String? { "tap again to edit" }

    init(geofence: Geofence, hexColor: String) {
        self.geofence = geofence
        self.hexColor = hexColor
    }
}

/// Hosts a plain SwiftUI `DotMarker` as the annotation's visual content — see
/// this file's header for why this sidesteps the RN custom-marker-view bug
/// with no bundled image assets.
final class DotHostingAnnotationView: MKAnnotationView {
    private var hostingController: UIHostingController<DotMarker>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(kind: DotAnnotation.Kind) {
        let marker: DotMarker
        let size: CGFloat
        switch kind {
        case .track:
            marker = DotMarker(diameter: 8, fillColor: Color(hex: GeofenceColors.track).opacity(0.8), borderColor: Color.white.opacity(0.7), borderWidth: 1)
            size = 8
        case let .geofenceEvent(hex):
            let color = Color(hex: hex)
            marker = DotMarker(diameter: 14, fillColor: color.opacity(0.4), borderColor: color, borderWidth: 2)
            size = 14
        case let .last(moving):
            let color = moving ? Color(hex: GeofenceColors.enter) : Color(hex: GeofenceColors.track)
            marker = DotMarker(diameter: 16, fillColor: color, borderColor: .white, borderWidth: 2)
            size = 16
        }
        if let hostingController {
            hostingController.rootView = marker
        } else {
            let controller = UIHostingController(rootView: marker)
            controller.view.backgroundColor = .clear
            addSubview(controller.view)
            hostingController = controller
        }
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        hostingController?.view.frame = bounds
        centerOffset = .zero
    }
}

// MARK: - hex color helpers

extension Color {
    init(hex: String) {
        let (r, g, b) = Self.components(hex)
        self.init(red: r, green: g, blue: b)
    }

    private static func components(_ hex: String) -> (Double, Double, Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
