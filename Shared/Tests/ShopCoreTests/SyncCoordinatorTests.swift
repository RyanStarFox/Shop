import Foundation
import XCTest
@testable import ShopCore

@MainActor
final class SyncCoordinatorTests: XCTestCase {
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
        coordinator.scheduleSync()
        coordinator.scheduleSync()
        await scheduler.waitForSleeper()
        await scheduler.resumeAll()
        await waitUntil { transport.putCount == 1 }

        XCTAssertEqual(transport.fetchCount, 1)
        XCTAssertEqual(transport.putCount, 1)
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
            .failed(message: ShopStrings.webdavPreconditionFailed, canRetry: true)
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
            .failed(message: ShopStrings.webdavNetworkFailed, canRetry: true)
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
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ interval: TimeInterval) async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitForSleeper() async {
        while continuations.isEmpty {
            await Task.yield()
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
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
