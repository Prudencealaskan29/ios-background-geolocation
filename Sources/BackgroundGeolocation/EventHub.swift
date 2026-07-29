import Foundation

/// A subscription handed back to callers of `EventHub.subscribe`/`stream`.
/// `remove()` is idempotent — calling it more than once, or after the hub has
/// already been torn down via `removeAll()`, is harmless.
///
/// `remove()` can be invoked from an arbitrary thread: `AsyncStream`'s
/// `onTermination` (used by `EventHub.stream`) runs on whatever context
/// cancelled the consuming task, not necessarily the main actor. `removed` is
/// therefore guarded by a lock rather than actor isolation.
public final class Subscription: @unchecked Sendable {
    private let onRemove: () -> Void
    private let lock = NSLock()
    private var removed = false

    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    public func remove() {
        lock.lock()
        let alreadyRemoved = removed
        removed = true
        lock.unlock()
        guard !alreadyRemoved else { return }
        onRemove()
    }
}

/// Claims the engine's single `eventEmitter` slot and fans each event out to
/// every subscriber of that event name.
///
/// The engine can emit before any subscriber exists — CoreLocation's initial
/// `didChangeAuthorization` fires during app launch. Events that arrive with
/// no subscriber are buffered (per event name, capped at 64, oldest kept) and
/// flushed, in order, to the FIRST subscriber of that name — once, not
/// replayed to every subscriber that ever attaches.
///
/// The subscriber/buffer bookkeeping is guarded by a lock rather than pure
/// actor isolation: `AsyncStream.Continuation.onTermination` (wired up by
/// `stream(_:)`) fires on an arbitrary, non-main-actor context when its
/// consuming task is cancelled, and unsubscribing there must take effect
/// synchronously and immediately — hopping back to the main actor via a new
/// `Task` is not ordering-guaranteed against a caller that only awaits a
/// single `Task.yield()` after cancelling.
@MainActor
final class EventHub {

    private static let bufferCap = 64

    private struct Entry {
        let token: UUID
        let handler: ([String: Any]) -> Void
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var subscribers: [String: [Entry]] = [:]
    private nonisolated(unsafe) var buffers: [String: [[String: Any]]] = [:]

    func attach(to engine: Engine) {
        engine.eventEmitter = { [weak self] name, body in
            self?.receive(name, body)
        }
    }

    private nonisolated func receive(_ name: String, _ body: [String: Any]) {
        lock.lock()
        let handlers = subscribers[name] ?? []
        if handlers.isEmpty {
            var buffered = buffers[name] ?? []
            if buffered.count < Self.bufferCap {
                buffered.append(body)
            }
            buffers[name] = buffered
        }
        lock.unlock()

        for entry in handlers {
            entry.handler(body)
        }
    }

    func subscribe(_ name: String, _ handler: @escaping ([String: Any]) -> Void) -> Subscription {
        let token = UUID()

        lock.lock()
        subscribers[name, default: []].append(Entry(token: token, handler: handler))
        let buffered = buffers.removeValue(forKey: name)
        lock.unlock()

        if let buffered {
            for body in buffered {
                handler(body)
            }
        }

        return Subscription { [weak self] in
            self?.unsubscribe(name, token: token)
        }
    }

    private nonisolated func unsubscribe(_ name: String, token: UUID) {
        lock.lock()
        subscribers[name]?.removeAll { $0.token == token }
        lock.unlock()
    }

    func stream(_ name: String) -> AsyncStream<[String: Any]> {
        AsyncStream { continuation in
            let subscription = subscribe(name) { body in
                continuation.yield(body)
            }
            continuation.onTermination = { _ in
                subscription.remove()
            }
        }
    }

    func removeAll() {
        lock.lock()
        subscribers.removeAll()
        buffers.removeAll()
        lock.unlock()
    }

    /// Internal test support.
    func subscriberCount(for name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return subscribers[name]?.count ?? 0
    }
}
