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
    private let onRemove: @Sendable () -> Void
    private let lock = NSLock()
    private var removed = false

    init(onRemove: @escaping @Sendable () -> Void) {
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
/// replayed to every subscriber that ever attaches. The buffer latches shut
/// the first time any subscriber attaches for a given name: it never re-arms,
/// even if every subscriber is later removed, matching
/// `RNBackgroundGeolocation.mm`'s one-shot `_emitterReady` gate. Otherwise an
/// app that drops and re-adds its `location` listener would see a burst of up
/// to 64 stale locations replayed as if they just happened.
///
/// Handlers passed to `subscribe`/`stream` are always invoked on the main
/// thread: `receive` delivers inline when already on main, otherwise via
/// `DispatchQueue.main.async`. This is a deliberate, documented contract, not
/// an incidental effect of Phase 1 only emitting from CoreLocation's
/// main-run-loop callbacks — later phases add engine-side background work
/// (the log DB's private serial queue, the uploader's `http`/
/// `connectivitychange` events) that must not leak onto app-facing handlers,
/// which routinely touch UI.
///
/// The subscriber/buffer bookkeeping is guarded by a lock rather than pure
/// actor isolation: `AsyncStream.Continuation.onTermination` (wired up by
/// `stream(_:)`) fires on an arbitrary, non-main-actor context when its
/// consuming task is cancelled, and unsubscribing there must take effect
/// synchronously and immediately — hopping back to the main actor via a new
/// `Task` is only eventually consistent (unbounded delay), which both makes
/// cancellation-based tests racy and, worse, lets `receive` take the
/// has-subscribers path and dispatch into a subscriber that has in fact
/// already unsubscribed, dropping the event instead of buffering it.
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
    private nonisolated(unsafe) var latchedNames: Set<String> = []

    func attach(to engine: Engine) {
        engine.eventEmitter = { [weak self] name, body in
            self?.receive(name, body)
        }
    }

    private nonisolated func receive(_ name: String, _ body: [String: Any]) {
        lock.lock()
        // Snapshot under the lock, deliver outside it. A handler that calls
        // back into `subscribe`/`unsubscribe` during delivery must not
        // deadlock or re-enter the lock. One consequence, kept deliberately:
        // if an earlier handler in this same snapshot removes a later one's
        // subscription mid-delivery, the later handler still receives this
        // event — it was already part of the batch fanned out for it.
        let handlers = subscribers[name] ?? []
        if handlers.isEmpty {
            if !latchedNames.contains(name) {
                var buffered = buffers[name] ?? []
                if buffered.count < Self.bufferCap {
                    buffered.append(body)
                }
                buffers[name] = buffered
            }
            lock.unlock()
            return
        }
        lock.unlock()

        deliver(handlers, body)
    }

    private nonisolated func deliver(_ handlers: [Entry], _ body: [String: Any]) {
        if Thread.isMainThread {
            for entry in handlers {
                entry.handler(body)
            }
        } else {
            DispatchQueue.main.async {
                for entry in handlers {
                    entry.handler(body)
                }
            }
        }
    }

    /// Delivers `body` to every current subscriber of `name`, then flushes
    /// (once) any events buffered for `name` before this subscriber existed.
    /// Handlers are always invoked on the main thread — see the type-level
    /// doc comment.
    func subscribe(_ name: String, _ handler: @escaping ([String: Any]) -> Void) -> Subscription {
        let token = UUID()

        lock.lock()
        subscribers[name, default: []].append(Entry(token: token, handler: handler))
        latchedNames.insert(name)
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

    /// An `AsyncStream` view over `subscribe(_:_:)` — same buffering/latching
    /// contract, and the same main-thread delivery guarantee (each element is
    /// yielded to the stream from the main thread; see the type-level doc
    /// comment). Cancelling the consuming task's iteration unsubscribes.
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

    /// Detaches every current subscriber, but deliberately does NOT touch
    /// `buffers` or `latchedNames`. `buffers` only ever holds entries for
    /// names that have never been subscribed to (see `receive`'s
    /// `latchedNames` check — a latched name is never buffered again), so it
    /// already holds exactly the pre-subscribe buffer the latch exists to
    /// protect. Clearing it here would let an app that calls
    /// `removeListeners()` before its first `subscribe`/`stream` for a name
    /// discard that name's launch-time buffer for good.
    func removeAll() {
        lock.lock()
        subscribers.removeAll()
        lock.unlock()
    }

    /// Internal test support.
    func subscriberCount(for name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return subscribers[name]?.count ?? 0
    }
}
