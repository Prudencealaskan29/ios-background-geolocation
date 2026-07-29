# BackgroundGeolocation

This package is the open Swift facade over the closed-source BGeo background-geolocation
engine. The engine itself ships as a prebuilt binary vendored at
`Frameworks/BGeoCore.xcframework`; the Swift sources in this package will provide the
public API surface over it in later tasks.

## Running the tests

The vendored xcframework is iOS-only, so `swift test` cannot link it (it builds for
macOS). Run the tests against an iOS simulator instead:

```bash
xcodebuild test -scheme BackgroundGeolocation \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
