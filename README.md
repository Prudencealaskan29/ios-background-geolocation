# BackgroundGeolocation

An open Swift facade over the closed-source BGeo background-geolocation engine.
The engine itself ships as a prebuilt binary vendored at
`Frameworks/BGeoCore.xcframework`; this package is pure Swift, async/await
throughout, and mirrors the vocabulary of `react-native/src/index.ts` so a
developer moving between BGeo SDKs finds the same method and event names.

## Installation

### Swift Package Manager

This package currently vendors `BGeoCore.xcframework` via a **local path**
binary target (see `Package.swift`). Point your app at this checkout directly:

```swift
.package(path: "../path/to/bgeo/ios")
```

A remote `binaryTarget` URL + checksum (so apps can depend on a tagged
release without a local checkout) lands in phase 2.

### CocoaPods

Not yet available. A podspec is planned for phase 2.

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
