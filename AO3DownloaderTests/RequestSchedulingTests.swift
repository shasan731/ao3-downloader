import XCTest
@testable import AO3Downloader

private actor ActivityCounter {
    var active = 0
    var maximum = 0
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
}

private struct ImmediateSleeper: Sleeping { func sleep(for duration: Duration) async throws {} }

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
}
