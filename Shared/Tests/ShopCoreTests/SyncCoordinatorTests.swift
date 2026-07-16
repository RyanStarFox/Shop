import Foundation
import XCTest
@testable import ShopCore

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    func testSchedulerCancellationRemovesOnlyCancelledSleeper() async {
        let scheduler = TestScheduler()
        let cancelledSleep = Task {
            await scheduler.sleep(2)
        }
        let cancelledSleeperID = await scheduler.waitForNextSleeper()

        cancelledSleep.cancel()
        await cancelledSleep.value

        let countAfterCancellation = await scheduler.sleeperCount
        let containsCancelledSleeper = await scheduler.contains(cancelledSleeperID)
        XCTAssertEqual(countAfterCancellation, 0)
        XCTAssertFalse(containsCancelledSleeper)

        let activeSleep = Task {
            await scheduler.sleep(2)
        }
        let activeSleeperID = await scheduler.waitForNextSleeper(after: cancelledSleeperID)
        await scheduler.advance(activeSleeperID)
        await activeSleep.value

        let countAfterAdvancing = await scheduler.sleeperCount
        XCTAssertEqual(countAfterAdvancing, 0)
    }

    func testAutomaticSyncWithoutTransportKeepsIdleStatus() async {
        let store = DataStore(inMemory: true, deviceID: "local")
        let scheduler = TestScheduler()
        let coordinator = SyncCoordinator(
            dataStore: store,
            transport: nil,
            sleep: scheduler.sleep
        )

        store.addItem(name: "Local")
        coordinator.scheduleSync()

        let sleeperCount = await scheduler.sleeperCount
        XCTAssertEqual(sleeperCount, 0)
        XCTAssertEqual(coordinator.status, .idle(lastSuccess: nil))
        XCTAssertNil(coordinator.status.failureMessage)
    }

    func testManualSyncWithoutTransportReportsNotConfigured() async {
        let store = DataStore(inMemory: true, deviceID: "local")
        let coordinator = SyncCoordinator(
            dataStore: store,
            transport: nil
        )

        await coordinator.syncNow()

        XCTAssertEqual(
            coordinator.status,
            .failed(message: ShopStrings.webdavNotConfigured, canRetry: false)
        )
    }

    func testScheduledChangesWithinDebounceProduceOneSync() async throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        store.addItem(name: "Local")
        let scheduler = TestScheduler()
        let transport = FakeCoordinatorTransport()
        let coordinator = SyncCoordinator(
            dataStore: store,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: scheduler.sleep
        )

        coordinator.scheduleSync()
        let firstSleeperID = await scheduler.waitForNextSleeper()
        coordinator.scheduleSync()
        let secondSleeperID = await scheduler.waitForNextSleeper(after: firstSleeperID)
        let containsFirstSleeper = await scheduler.contains(firstSleeperID)
        XCTAssertFalse(containsFirstSleeper)
        XCTAssertEqual(transport.fetchCount, 0)
        coordinator.scheduleSync()
        let currentSleeperID = await scheduler.waitForNextSleeper(after: secondSleeperID)
        let containsSecondSleeper = await scheduler.contains(secondSleeperID)
        XCTAssertFalse(containsSecondSleeper)
        XCTAssertEqual(transport.fetchCount, 0)
        let registeredSleeperCount = await scheduler.sleeperCount
        XCTAssertEqual(registeredSleeperCount, 1)
        await scheduler.advance(currentSleeperID)
        await waitUntil { transport.putCount == 1 }

        XCTAssertEqual(transport.fetchCount, 1)
        XCTAssertEqual(transport.putCount, 1)
        let remainingSleeperCount = await scheduler.sleeperCount
        XCTAssertEqual(remainingSleeperCount, 0)
    }

    func testLocalChangeDuringSyncProducesExactlyOneFollowUpPass() async throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        store.addItem(name: "First")
        let transport = FakeCoordinatorTransport(blockFirstFetch: true)
        let coordinator = SyncCoordinator(dataStore: store, transport: transport)

        let sync = Task { await coordinator.syncNow() }
        await waitUntil { transport.fetchCount == 1 }
        store.addItem(name: "Second")
        transport.releaseFirstFetch()
        await sync.value
        await waitUntil { transport.putCount == 2 }

        XCTAssertEqual(transport.fetchCount, 2)
        XCTAssertEqual(transport.putCount, 2)
    }

    func testSyncMergesAppliesAndUploadsWithRemoteETag() async throws {
        let localStore = DataStore(inMemory: true, deviceID: "local")
        localStore.addItem(name: "Local")
        let remoteStore = DataStore(inMemory: true, deviceID: "remote")
        remoteStore.addItem(name: "Remote")
        let transport = FakeCoordinatorTransport(
            fetchResults: [.success(RemoteSnapshot(
                snapshot: try remoteStore.shoppingStore.makeSnapshot(),
                etag: "\"v4\""
            ))]
        )
        let coordinator = SyncCoordinator(dataStore: localStore, transport: transport)

        await coordinator.syncNow()

        XCTAssertEqual(transport.operations, [.fetch, .put(.etag("\"v4\""))])
        XCTAssertEqual(Set(localStore.items.map(\.name)), ["Local", "Remote"])
        XCTAssertEqual(Set(try XCTUnwrap(transport.putSnapshots.first).items.map(\.name)), ["Local", "Remote"])
    }

    func testMissingRemoteCreatesIt() async throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        store.addItem(name: "Local")
        let transport = FakeCoordinatorTransport(fetchResults: [.success(nil)])
        let coordinator = SyncCoordinator(dataStore: store, transport: transport)

        await coordinator.syncNow()

        XCTAssertEqual(transport.operations, [.fetch, .put(.create)])
    }

    func testPreconditionFailuresRefetchAndRetryAtMostThreeTimes() async throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        store.addItem(name: "Local")
        let snapshot = try store.shoppingStore.makeSnapshot()
        let transport = FakeCoordinatorTransport(
            fetchResults: [
                .success(RemoteSnapshot(snapshot: snapshot, etag: "\"v1\"")),
                .success(RemoteSnapshot(snapshot: snapshot, etag: "\"v2\"")),
                .success(RemoteSnapshot(snapshot: snapshot, etag: "\"v3\""))
            ],
            putResults: [
                .failure(WebDAVError.preconditionFailed),
                .failure(WebDAVError.preconditionFailed),
                .failure(WebDAVError.preconditionFailed)
            ]
        )
        let coordinator = SyncCoordinator(dataStore: store, transport: transport)

        await coordinator.syncNow()

        XCTAssertEqual(transport.fetchCount, 3)
        XCTAssertEqual(transport.putCount, 3)
        XCTAssertEqual(
            coordinator.status,
            .failed(message: WebDAVError.preconditionFailed.userFacingMessage, canRetry: true)
        )
        XCTAssertEqual(store.items.map(\.name), ["Local"])
    }

    func testNetworkFailureKeepsLocalDataAndCanBeRetried() async throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        store.addItem(name: "Local")
        let transport = FakeCoordinatorTransport(
            fetchResults: [.failure(WebDAVError.network(.notConnectedToInternet)), .success(nil)]
        )
        let coordinator = SyncCoordinator(dataStore: store, transport: transport)

        await coordinator.syncNow()

        XCTAssertEqual(store.items.map(\.name), ["Local"])
        XCTAssertEqual(
            coordinator.status,
            .failed(message: WebDAVError.network(.notConnectedToInternet).userFacingMessage, canRetry: true)
        )

        await coordinator.syncNow()

        XCTAssertEqual(transport.putCount, 1)
        XCTAssertEqual(coordinator.status, .idle(lastSuccess: coordinator.lastSuccess))
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

private actor TestScheduler {
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

private final class FakeCoordinatorTransport: WebDAVTransporting, @unchecked Sendable {
    enum Operation: Equatable {
        case fetch
        case put(WebDAVPrecondition)
    }

    private let lock = NSLock()
    private var fetchResults: [Result<RemoteSnapshot?, Error>]
    private var putResults: [Result<String?, Error>]
    private var firstFetchContinuation: CheckedContinuation<Void, Never>?
    private let blockFirstFetch: Bool

    private(set) var operations: [Operation] = []
    private(set) var putSnapshots: [SyncSnapshot] = []
    private(set) var fetchCount = 0
    private(set) var putCount = 0
    var diagnosticFileURL: String? { nil }

    init(
        fetchResults: [Result<RemoteSnapshot?, Error>] = [.success(nil)],
        putResults: [Result<String?, Error>] = [.success("\"updated\"")],
        blockFirstFetch: Bool = false
    ) {
        self.fetchResults = fetchResults
        self.putResults = putResults
        self.blockFirstFetch = blockFirstFetch
    }

    func fetch() async throws -> RemoteSnapshot? {
        let (index, result) = recordFetch()

        if blockFirstFetch, index == 0 {
            await withCheckedContinuation { continuation in
                storeFirstFetchContinuation(continuation)
            }
        }
        return try result.get()
    }

    func put(_ snapshot: SyncSnapshot, precondition: WebDAVPrecondition) async throws -> String? {
        try recordPut(snapshot, precondition: precondition).get()
    }

    private func recordFetch() -> (Int, Result<RemoteSnapshot?, Error>) {
        lock.lock()
        defer { lock.unlock() }
        fetchCount += 1
        operations.append(.fetch)
        let index = fetchCount - 1
        return (index, fetchResults[min(index, fetchResults.count - 1)])
    }

    private func recordPut(
        _ snapshot: SyncSnapshot,
        precondition: WebDAVPrecondition
    ) -> Result<String?, Error> {
        lock.lock()
        defer { lock.unlock() }
        putCount += 1
        operations.append(.put(precondition))
        putSnapshots.append(snapshot)
        return putResults[min(putCount - 1, putResults.count - 1)]
    }

    private func storeFirstFetchContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        firstFetchContinuation = continuation
        lock.unlock()
    }

    func releaseFirstFetch() {
        lock.lock()
        let continuation = firstFetchContinuation
        firstFetchContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
