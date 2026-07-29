import SwiftUI
import BackgroundGeolocation

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Map")
                .tabItem { Label("Map", systemImage: "map") }
            Text("Logs")
                .tabItem { Label("Logs", systemImage: "list.bullet") }
            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
