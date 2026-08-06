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
        // core/tools/build-ios.sh and committed here.
        //
        // A local path, not a remote `url:`/`checksum:` binary target. The
        // xcframework is ~1.6 MB (≈0.9 MB of git history per engine release),
        // which is cheap next to what a remote asset costs: SwiftPM resolves
        // the checksum against an asset that has to stay reachable forever,
        // and deleting or re-uploading it silently breaks every version that
        // referenced it. Revisit if this repository ever approaches ~100 MB.
        .binaryTarget(name: "BGeoCore", path: "Frameworks/BGeoCore.xcframework"),
        .target(name: "BackgroundGeolocation", dependencies: ["BGeoCore"]),
        .testTarget(name: "BackgroundGeolocationTests", dependencies: ["BackgroundGeolocation"]),
    ]
)
