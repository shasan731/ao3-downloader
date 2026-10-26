import Foundation

protocol Sleeping: Sendable { func sleep(for duration: Duration) async throws }
struct ContinuousSleeper: Sleeping { func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) } }

actor AO3RequestScheduler {
    private var nextAllowedAt: Date
    private let interval: TimeInterval
    private let jitter: @Sendable () -> TimeInterval
    private let sleeper: Sleeping
    private let now: @Sendable () -> Date
    private var inFlight = false
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []

    init(minimumInterval: TimeInterval = 15, persistedCooldown: Date = .distantPast,
         sleeper: Sleeping = ContinuousSleeper(), now: @escaping @Sendable () -> Date = Date.init,
         jitter: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0.25...1.5) }) {
        self.interval = max(10, minimumInterval)
        self.nextAllowedAt = persistedCooldown
        self.sleeper = sleeper; self.now = now; self.jitter = jitter
    }

    func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        let delay = max(0, nextAllowedAt.timeIntervalSince(now()))
        if delay > 0 { try await sleeper.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        defer { nextAllowedAt = now().addingTimeInterval(interval + max(0, jitter())) }
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard inFlight else { inFlight = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(.init(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func release() {
        if waiters.isEmpty { inFlight = false } else { waiters.removeFirst().continuation.resume() }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }

    func applyCooldown(until date: Date) { nextAllowedAt = max(nextAllowedAt, date) }
    func cooldownDate() -> Date { nextAllowedAt }
}

