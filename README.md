# BackgroundGeolocation

[![spm](https://img.shields.io/github/v/tag/dc-bgeo/ios-background-geolocation?label=spm&color=blue)](https://github.com/dc-bgeo/ios-background-geolocation/releases)

An open Swift facade over the closed-source BGeo background-geolocation engine.
The engine itself ships as a prebuilt binary vendored at
`Frameworks/BGeoCore.xcframework`; this package is pure Swift, async/await
throughout, and mirrors the vocabulary of `react-native/src/index.ts` so a
developer moving between BGeo SDKs finds the same method and event names.

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…**, then

```
https://github.com/dc-bgeo/ios-background-geolocation
```

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dc-bgeo/ios-background-geolocation", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "BackgroundGeolocation", package: "ios-background-geolocation"),
    ]),
]
```

The closed engine (`BGeoCore.xcframework`) is vendored in this repository, so
there is nothing else to download, no checksum to keep in step, and no release
asset that can go missing years from now. It costs roughly 0.9 MB of git
history per engine release — a deliberate trade for the simplest possible
consumer story. Full documentation: <https://bgeo.dev/docs/>.

### Toolchain requirement

**Xcode 26.6 or newer** (Swift 6.3.3+). This is not a style preference: the
engine ships as a binary framework, and a `.swiftinterface` can only be read by
a compiler at least as new as the one that produced it. An older Xcode fails to
import `BGeoCore` with an interface-parse error rather than anything that names
the real cause.

The floor moves with each engine release — it is whatever Xcode built the
binary. `Frameworks/BGeoCore.xcframework/*/Modules/*.swiftmodule/*.swiftinterface`
records it on the `swift-compiler-version` line, and CI checks it explicitly.

If that floor is too high for your team, the [React Native](https://bgeo.dev/docs/react-native/)
and [Flutter](https://bgeo.dev/docs/flutter/) SDKs ship the same engine and are
not affected — their binary is consumed through a bridge built against your own
toolchain.

### CocoaPods

Not available. Use SwiftPM.

## Info.plist requirements

The engine cannot obtain Always authorization or run location updates in the
background without these four keys in your app's `Info.plist`:

| Key | Purpose |
| --- | --- |
| `NSLocationWhenInUseUsageDescription` | Foreground location permission prompt. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Background ("Always") location permission prompt. |
| `NSMotionUsageDescription` | Motion-activity permission prompt (used to detect moving vs. stationary). |
| `UIBackgroundModes` → `location` | Lets the app receive location updates while backgrounded. |

Example:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Shows your location on the map.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Keeps tracking your route while the app is in the background.</string>
<key>NSMotionUsageDescription</key>
<string>Detects when you start and stop moving.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

If you call `requestTemporaryFullAccuracy(purpose:)`, you additionally need
`NSLocationTemporaryUsageDescriptionDictionary`, with `purpose` matching one
of its keys:

| Key | Purpose |
| --- | --- |
| `NSLocationTemporaryUsageDescriptionDictionary` | Per-`purpose` strings shown in the temporary-precise-accuracy prompt. **If `purpose` isn't a key here, iOS may never invoke the completion at all** — `requestTemporaryFullAccuracy` bounds this with a 30-second watchdog rather than hanging forever, but the call is still meant to be answered, not timed out. |

```xml
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
<dict>
    <key>Trip</key>
    <string>Precise location improves your trip route.</string>
</dict>
```

## Licence key

The licence key is **not** a `Config` option. Set it in your app's
`Info.plist`:

```xml
<key>BGeoLicense</key>
<string>BGEO1.your-license-token-here</string>
```

It's read once, at launch, before any other API on this package is used.

In a RELEASE build, a missing or invalid key makes `ready()`/`start()` throw a
`LICENSE_*` error. **Debuggable builds and the iOS Simulator always run
unlicensed (evaluation mode), regardless of the key's presence or validity** —
if tracking works fine in Debug but you're unsure whether your licence key is
actually wired up correctly, that's why: test the key in a Release build on a
device.

## Quickstart

```swift
import BackgroundGeolocation

try await BackgroundGeolocation.ready(Config(
    desiredAccuracy: DesiredAccuracy.high.rawValue,
    distanceFilter: 10,
    stopOnTerminate: false,
    startOnBoot: true
))

let status = try await BackgroundGeolocation.requestPermission()
guard status == .always || status == .whenInUse else { return }

try await BackgroundGeolocation.start()

for await location in BackgroundGeolocation.locations {
    print(location.coords.latitude, location.coords.longitude)
}
```

`locations` is an `AsyncStream<Location>`; there's also a callback form
(`BackgroundGeolocation.onLocation { location in ... }`, which returns a
`Subscription` you hold onto and call `.remove()` on to unsubscribe) for code
that isn't structured around async sequences.

## Example app

`Example/` is a console app that depends on this package by local path and
exercises the SDK on a real device — see `Example/README.md` for what it is
and how to run it. The Xcode project is generated by xcodegen from
`Example/project.yml`; regenerate it with `xcodegen generate` after changing
that file.

## Running the tests

The vendored `BGeoCore.xcframework` is iOS-only, so **`swift test` does not
work** — it builds for macOS by default and the binary can't link there.

Run the tests against an iOS simulator instead:

```bash
xcodebuild test -scheme BackgroundGeolocation \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

(Substitute whatever simulator you have installed — `xcrun simctl list
devices available` shows your options.)
