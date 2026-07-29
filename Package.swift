// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BackgroundGeolocation",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "BackgroundGeolocation", targets: ["BackgroundGeolocation"]),
    ],
    targets: [
        // Closed-source engine, built from the private core repo by
        // core/tools/build-ios.sh. Phase 2 replaces this local path with a
        // remote URL + checksum pointing at a GitHub release asset.
        .binaryTarget(name: "BGeoCore", path: "Frameworks/BGeoCore.xcframework"),
        .target(name: "BackgroundGeolocation", dependencies: ["BGeoCore"]),
        .testTarget(name: "BackgroundGeolocationTests", dependencies: ["BackgroundGeolocation"]),
    ]
)
