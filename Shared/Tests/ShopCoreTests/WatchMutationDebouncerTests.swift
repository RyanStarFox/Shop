import Foundation
import XCTest
@testable import ShopCore

@MainActor
final class WatchMutationDebouncerTests: XCTestCase {
    func testThreeRapidSchedulesSendOnlyLatestOnce() async {
        let scheduler = DebounceTestScheduler()
        let debouncer = WatchMutationDebouncer(sleep: scheduler.sleep)
        var sendCount = 0

        debouncer.schedule { sendCount += 1 }
        let first = await scheduler.waitForNextSleeper()
        debouncer.schedule { sendCount += 1 }
        let second = await scheduler.waitForNextSleeper(after: first)
        debouncer.schedule { sendCount += 1 }
        let third = await scheduler.waitForNextSleeper(after: second)

        await scheduler.advance(third)
        await waitUntil { sendCount == 1 }

        let sleeperCount = await scheduler.sleeperCount
        XCTAssertEqual(sendCount, 1)
        XCTAssertEqual(sleeperCount, 0)
    }

    func testNewScheduleCancelsOldSleeper() async {
        let scheduler = DebounceTestScheduler()
        let debouncer = WatchMutationDebouncer(sleep: scheduler.sleep)

        debouncer.schedule {}
        let first = await scheduler.waitForNextSleeper()
        debouncer.schedule {}
        _ = await scheduler.waitForNextSleeper(after: first)

        let containsFirst = await scheduler.contains(first)
        let sleeperCount = await scheduler.sleeperCount
        XCTAssertFalse(containsFirst)
        XCTAssertEqual(sleeperCount, 1)
    }

    func testMutationDuringStartedSendSchedulesNextWithoutCancellingCurrent() async {
        let scheduler = DebounceTestScheduler()
        let debouncer = WatchMutationDebouncer(sleep: scheduler.sleep)
        var events: [String] = []

        debouncer.schedule {
            events.append("first-started")
            debouncer.schedule {
                events.append("second")
            }
            events.append("first-finished")
        }
        let first = await scheduler.waitForNextSleeper()
        await scheduler.advance(first)
        await waitUntil { events == ["first-started", "first-finished"] }

        let second = await scheduler.waitForNextSleeper(after: first)
        await scheduler.advance(second)
        await waitUntil { events.count == 3 }

        XCTAssertEqual(events, ["first-started", "first-finished", "second"])
    }

    func testDeinitCancelsPendingSleeper() async {
        let scheduler = DebounceTestScheduler()
        var debouncer: WatchMutationDebouncer? = WatchMutationDebouncer(
            sleep: scheduler.sleep
        )
        debouncer?.schedule {}
        _ = await scheduler.waitForNextSleeper()

        debouncer = nil
        for _ in 0..<100 {
            if await scheduler.sleeperCount == 0 {
                break
            }
            await Task.yield()
        }

        let sleeperCount = await scheduler.sleeperCount
        XCTAssertEqual(sleeperCount, 0)
    }

    private func waitUntil(
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

private actor DebounceTestScheduler {
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var latestRegisteredID: UUID?

    func sleep(_ interval: TimeInterval) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                continuations[id] = continuation
                latestRegisteredID = id
            }
        } onCancel: {
            Task {
                await self.cancel(id)
            }
        }
    }

    var sleeperCount: Int {
        continuations.count
    }

    func contains(_ id: UUID) -> Bool {
        continuations[id] != nil
    }

    func waitForNextSleeper(after previousID: UUID? = nil) async -> UUID {
        while latestRegisteredID == previousID
                || latestRegisteredID.flatMap({ continuations[$0] }) == nil {
            await Task.yield()
        }
        return latestRegisteredID!
    }

    func advance(_ id: UUID) {
        continuations.removeValue(forKey: id)?.resume()
    }

    private func cancel(_ id: UUID) {
        continuations.removeValue(forKey: id)?.resume()
    }
}
