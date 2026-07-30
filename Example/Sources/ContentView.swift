// Three-tab shell (Map / Logs / Settings) + the geofence-form modal, wired to
// the real screens built in Tasks 4-7. Swift port of the tab/stack structure
// `react-native/example/App.tsx` builds with `@react-navigation`.
//
// `@SwiftUI.State` (not bare `@State`): `BackgroundGeolocation.State` and
// SwiftUI's `State` collide once both modules are imported — the same trap
// Tasks 4-6 documented for their own screens.

import SwiftUI
import BackgroundGeolocation

struct ContentView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var configStore: ConfigStore
    let deviceLink: DeviceLink
    let geofences: Geofences

    /// Set by `MapScreen`'s `onGeofenceRequest` (long-press on the map, or a
    /// tap on an existing pin); presenting the sheet is driven off this being
    /// non-nil, mirroring `App.tsx`'s modal `Stack.Screen("GeofenceForm")`.
    @SwiftUI.State private var geofenceRequest: GeofenceRequest?

    var body: some View {
        TabView {
            MapScreen(appStore: appStore, themeStore: themeStore, deviceLink: deviceLink) { request in
                geofenceRequest = request
            }
            .tabItem { Label("Map", systemImage: "map") }

            LogsScreen(appStore: appStore, themeStore: themeStore)
                .tabItem { Label("Logs", systemImage: "list.bullet") }

            SettingsScreen(appStore: appStore, configStore: configStore, themeStore: themeStore, deviceLink: deviceLink)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .sheet(isPresented: Binding(
            get: { geofenceRequest != nil },
            set: { isPresented in if !isPresented { geofenceRequest = nil } }
        )) {
            if let geofenceRequest {
                GeofenceFormScreen(appStore: appStore, themeStore: themeStore, geofences: geofences, request: geofenceRequest)
            }
        }
    }
}
