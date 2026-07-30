// Small circular breadcrumb dot — the plain SwiftUI content hosted inside
// each `TrackMapView` annotation view (`Screens/MapScreen.swift`).
//
// Swift port of the *content* `components/DotMarker.tsx` wraps (that file's
// child `<View style={styles.dot}>` etc.), not its marker-recycling
// machinery. RN needed `redrawKey` + a `tracksViewChanges` timer because
// `react-native-maps` on Android snapshots marker children to a bitmap once
// and only re-snapshots on demand; `flutter/example/lib/src/screens/
// map_screen.dart` sidesteps the whole problem with `CircleLayer`/`MarkerLayer`
// primitives instead of custom widgets. MapKit's `MKAnnotationView` can host a
// live SwiftUI view via `UIHostingController` and simply re-renders when
// `rootView` is reassigned — no snapshot cache, no redraw key, nothing extra
// needed. See `MapScreen.swift`'s `DotHostingAnnotationView` for the hosting
// side.

import SwiftUI

/// A filled circle with a stroked border — the only marker shape this screen
/// needs (breadcrumb dot, geofence-event dot, last-position dot), each a
/// different size/color/border passed in by the caller.
public struct DotMarker: View {
    public var diameter: CGFloat
    public var fillColor: Color
    public var borderColor: Color
    public var borderWidth: CGFloat

    public init(
        diameter: CGFloat,
        fillColor: Color,
        borderColor: Color = .white,
        borderWidth: CGFloat = 1
    ) {
        self.diameter = diameter
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    public var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(borderColor, lineWidth: borderWidth))
    }
}
