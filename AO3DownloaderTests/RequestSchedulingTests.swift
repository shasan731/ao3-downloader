import XCTest
@testable import AO3Downloader

private actor ActivityCounter {
    var active = 0
    var maximum = 0
    var entries = 0
    func enter() { active += 1; entries += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
}

private struct ImmediateSleeper: Sleeping { func sleep(for duration: Duration) async throws {} }

private final class CooldownRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date?
    func record(_ date: Date) { lock.lock(); value = date; lock.unlock() }
    func latest() -> Date? { lock.lock(); defer { lock.unlock() }; return value }
}

private actor StartSignal {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func markStarted() { started = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
    func wait() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

final class RequestSchedulingTests: XCTestCase {
    func testSerializesEntireRequestLifecycle() async throws {
        let scheduler = AO3RequestScheduler(minimumInterval: 10, sleeper: ImmediateSleeper(), jitter: { 0 })
        let counter = ActivityCounter()
        async let first: Int = scheduler.perform {
            await counter.enter(); try await Task.sleep(for: .milliseconds(25)); await counter.leave(); return 1
        }
        async let second: Int = scheduler.perform {
            await counter.enter(); try await Task.sleep(for: .milliseconds(25)); await counter.leave(); return 2
        }
        _ = try await (first, second)
        let maximum = await counter.maximum
        XCTAssertEqual(maximum, 1)
    }


    func testCancellationWhileWaitingDoesNotRunQueuedRequest() async throws {
        let scheduler = AO3RequestScheduler(minimumInterval: 10, sleeper: ImmediateSleeper(), jitter: { 0 })
        let counter = ActivityCounter()
        let signal = StartSignal()
        let first = Task {
            try await scheduler.perform {
                await counter.enter(); await signal.markStarted()
                try await Task.sleep(for: .milliseconds(100)); await counter.leave()
            }
        }
        await signal.wait()
        let second = Task {
            try await scheduler.perform {
                await counter.enter(); await counter.leave()
            }
        }
        second.cancel()
        _ = try await first.value
        do {
            _ = try await second.value
            XCTFail("Cancelled queued request unexpectedly ran")
        } catch is CancellationError {
            // Expected.
        }
        let maximum = await counter.maximum
        XCTAssertEqual(maximum, 1)
        let entries = await counter.entries
        XCTAssertEqual(entries, 1)
    }

    func testPublishesCourtesyAndServerCooldownChangesForPersistence() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recorder = CooldownRecorder()
        let scheduler = AO3RequestScheduler(minimumInterval: 10, sleeper: ImmediateSleeper(),
                                            now: { now }, jitter: { 0 }, cooldownChanged: recorder.record)
        _ = try await scheduler.perform { 1 }
        XCTAssertEqual(recorder.latest(), now.addingTimeInterval(10))

        let serverCooldown = now.addingTimeInterval(600)
        await scheduler.applyCooldown(until: serverCooldown)
        XCTAssertEqual(recorder.latest(), serverCooldown)
        let appliedCooldown = await scheduler.cooldownDate()
        XCTAssertEqual(appliedCooldown, serverCooldown)
    }
}
