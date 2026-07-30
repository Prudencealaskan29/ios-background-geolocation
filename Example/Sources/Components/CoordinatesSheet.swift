// Collapsible bottom sheet with the collected-coordinates table (newest
// first). Swift port of `components/CoordinatesSheet.tsx`
// (`flutter/example/lib/src/widgets/coordinates_sheet.dart` is the same port
// for Flutter). Consumed by `Screens/MapScreen.swift`.
//
// One deliberate simplification from both reference clients: RN/Flutter drive
// the sheet's height with a drag gesture (`PanResponder`/raw pointer
// tracking) that free-scrubs between a peek and an expanded height; this port
// only offers a tap-to-toggle (the handle, or the chevron button) between the
// same two states. Same two end states, same information, far less gesture
// code to get right on a screen that's already the largest in the app — a tap
// target is also more discoverable without ever having seen the RN app.
//
// Row cell formatting (`PointFormat`, `parseISODate`) is pulled out as pure,
// independently-testable functions — this is the "coordinate formatting"
// logic the task's verification plan calls out, since the view around it
// cannot be unit tested.

import SwiftUI

private let peekHeight: CGFloat = 26 + 44 // handle zone + header, mirrors HANDLE_ZONE_HEIGHT + HEADER_HEIGHT
public let sheetPeekHeight: CGFloat = peekHeight

// MARK: - pure formatting (tested)

/// Parses either fractional- or whole-second ISO 8601 (the two shapes
/// `Point.timestamp`/server `recordedAt` arrive in), returning `nil` for
/// anything else instead of crashing on a malformed string.
public func parseISODate(_ iso: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: iso) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: iso)
}

/// Swift port of `CoordinatesSheet.tsx`'s cell formatters (`formatTime`,
/// `num`, and the inline `Math.round`/`heading >= 0` rules). Kept as pure
/// static functions — no `View` involved — so they're directly unit-testable.
public enum PointFormat {
    /// Local wall-clock `HH:mm:ss`, matching RN's `new Date(iso)` +
    /// `getHours`/`getMinutes`/`getSeconds` (device-local, not UTC).
    public static func time(fromISO iso: String) -> String {
        guard let date = parseISODate(iso) else { return "--:--:--" }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        func pad(_ n: Int) -> String { String(format: "%02d", n) }
        return "\(pad(c.hour ?? 0)):\(pad(c.minute ?? 0)):\(pad(c.second ?? 0))"
    }

    public static func coordinate(_ v: Double, digits: Int = 5) -> String {
        String(format: "%.\(digits)f", v)
    }

    /// RN's `num(v, digits)`: dash for missing or negative values (used for
    /// speed, which is never legitimately negative).
    public static func nonNegative(_ v: Double?, digits: Int) -> String {
        guard let v, v >= 0 else { return "–" }
        return String(format: "%.\(digits)f", v)
    }

    /// Rounds to the nearest whole number for display — guarded with
    /// `Int(exactly:)` rather than `Int(v)`, which traps on values outside
    /// `Int`'s range (the exact crash class this repo hit three times in the
    /// Settings screen). Falls back to a plain rounded-`Double` string on
    /// overflow instead of crashing.
    public static func roundedOrDash(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        let rounded = v.rounded()
        if let whole = Int(exactly: rounded) { return String(whole) }
        return String(format: "%.0f", rounded)
    }

    /// RN: `heading != null && heading >= 0 ? Math.round(heading)+'°' : '–'`.
    public static func heading(_ v: Double?) -> String {
        guard let v, v >= 0 else { return "–" }
        return "\(roundedOrDash(v))°"
    }

    public static func isMoving(_ v: Bool?) -> String {
        guard let v else { return "–" }
        return v ? "yes" : "no"
    }

    /// RN's `EventCell`: `"<identifier> · <ACTION>"` for a geofence point,
    /// else the raw event name (or a dash).
    public static func eventLabel(_ point: Point) -> String {
        guard point.event == "geofence" else { return point.event ?? "-" }
        let identifier = point.geofence?.identifier ?? "geofence"
        guard let action = point.geofence?.action?.uppercased() else { return identifier }
        return "\(identifier) · \(action)"
    }
}

// MARK: - view

public struct CoordinatesSheet: View {
    public let points: [Point]
    let colors: ThemeColors

    @SwiftUI.State private var expanded = false

    public init(points: [Point], colors: ThemeColors) {
        self.points = points
        self.colors = colors
    }

    private var rows: [Point] { points.reversed() }
    private var expandedHeight: CGFloat { 320 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            header
            table
        }
        .frame(height: expanded ? expandedHeight : peekHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(colors.panel)
        .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private var handle: some View {
        Button { expanded.toggle() } label: {
            Capsule()
                .fill(colors.handle)
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Collected coordinates")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(colors.text)
            Text("\(points.count) pts")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(colors.accentText)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(colors.accentSoft)
                .clipShape(Capsule())
            Spacer()
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .foregroundColor(colors.textDim)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headRow
                if rows.isEmpty {
                    Text("no points yet")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(colors.textDim)
                        .padding(16)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows.indices, id: \.self) { i in
                                rowView(rows[i], number: rows.count - i)
                            }
                        }
                    }
                }
            }
        }
    }

    private var headRow: some View {
        HStack(spacing: 0) {
            th("#", width: 34)
            th("TIME", width: 86)
            th("LAT", width: 96, trailing: true)
            th("LNG", width: 96, trailing: true)
            th("ACCURACY (m)", width: 96, trailing: true)
            th("SPEED (m/s)", width: 116, trailing: true)
            th("ODOMETER (m)", width: 96, trailing: true)
            th("HEADING", width: 96, trailing: true)
            th("MOVING", width: 96, trailing: true)
            th("ACTIVITY", width: 96, trailing: true)
            th("EVENT", width: 170)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func th(_ text: String, width: CGFloat, trailing: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(colors.textDim)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
    }

    private func rowView(_ point: Point, number: Int) -> some View {
        HStack(spacing: 0) {
            cell(String(format: "%02d", number), width: 34, color: colors.textDim)
            cell(PointFormat.time(fromISO: point.timestamp), width: 86, color: colors.text)
            cell(PointFormat.coordinate(point.latitude), width: 96, color: colors.text, trailing: true)
            cell(PointFormat.coordinate(point.longitude), width: 96, color: colors.text, trailing: true)
            cell(PointFormat.roundedOrDash(point.accuracy), width: 96, color: colors.accentText, trailing: true)
            cell(PointFormat.nonNegative(point.speed, digits: 1), width: 116, color: colors.text, trailing: true)
            cell(PointFormat.roundedOrDash(point.odometer), width: 96, color: colors.text, trailing: true)
            cell(PointFormat.heading(point.heading), width: 96, color: colors.text, trailing: true)
            cell(PointFormat.isMoving(point.isMoving), width: 96, color: point.isMoving == true ? colors.successText : colors.textDim, trailing: true)
            cell(point.activity ?? "–", width: 96, color: colors.textDim, trailing: true)
            cell(PointFormat.eventLabel(point), width: 170, color: point.event == "geofence" ? colors.warningText : colors.textDim)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(point.event == "geofence" ? colors.warningSoft : Color.clear)
    }

    private func cell(_ text: String, width: CGFloat, color: Color, trailing: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
    }
}

/// Rounds only the top corners — `.cornerRadius` on `UIRectCorner.allCorners`
/// would also round the bottom edge, which should stay flush with the screen
/// edge like RN's `borderTopLeftRadius`/`borderTopRightRadius`.
private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
