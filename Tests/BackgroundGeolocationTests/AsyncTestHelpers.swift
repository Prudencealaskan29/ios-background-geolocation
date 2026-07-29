import XCTest

/// Repeatedly checks `condition` until it's true or `timeout` elapses, then
/// fails the test if it never became true.
///
/// This exists to replace `await Task.yield()` used as a proxy for "some
/// other task has reached a specific point" (e.g. "has registered its
/// subscription" or "has run `onTermination` and unsubscribed").
/// `Task.yield()` only offers the current task's executor a chance to run
/// something else — it does not guarantee any other specific task has made
/// any specific progress, which makes it an inherently racy stand-in for
/// those conditions. Polling the actual state the test cares about is
/// deterministic regardless of how the scheduler interleaves tasks.
@MainActor
func pollUntil(
    _ description: String,
    timeout: TimeInterval = 2,
    pollInterval: TimeInterval = 0.005,
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= deadline {
            XCTFail("Timed out waiting for: \(description)", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
}
