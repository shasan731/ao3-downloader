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
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(minimumInterval: TimeInterval = 15, persistedCooldown: Date = .distantPast,
         sleeper: Sleeping = ContinuousSleeper(), now: @escaping @Sendable () -> Date = Date.init,
         jitter: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0.25...1.5) }) {
        self.interval = max(10, minimumInterval)
        self.nextAllowedAt = persistedCooldown
        self.sleeper = sleeper; self.now = now; self.jitter = jitter
    }

    func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        let delay = max(0, nextAllowedAt.timeIntervalSince(now()))
        if delay > 0 { try await sleeper.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        defer { nextAllowedAt = now().addingTimeInterval(interval + max(0, jitter())) }
        return try await operation()
    }

    private func acquire() async {
        guard inFlight else { inFlight = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { inFlight = false } else { waiters.removeFirst().resume() }
    }

    func applyCooldown(until date: Date) { nextAllowedAt = max(nextAllowedAt, date) }
    func cooldownDate() -> Date { nextAllowedAt }
}

