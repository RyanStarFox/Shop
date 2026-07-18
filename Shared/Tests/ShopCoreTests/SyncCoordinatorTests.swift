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

    func testRemoteCompletionSyncsAsArchiveNotDeletion() async throws {
        let mac = DataStore(inMemory: true, deviceID: "mac")
        mac.addItem(name: "Milk")
        let itemID = try XCTUnwrap(mac.items.first?.id)

        let phone = DataStore(inMemory: true, deviceID: "iphone")
        try phone.shoppingStore.applyCanonicalSnapshot(try mac.shoppingStore.makeSnapshot())
        phone.fetchData()
        let phoneItem = try XCTUnwrap(phone.items.first { $0.id == itemID })
        phone.setCompleted(phoneItem, completed: true, presentUndo: { _ in })

        let remoteSnapshot = try phone.shoppingStore.makeSnapshot()
        XCTAssertEqual(remoteSnapshot.items.first?.isCompleted, true)
        XCTAssertNil(remoteSnapshot.items.first?.deletedAt)

        let transport = FakeCoordinatorTransport(
            fetchResults: [.success(RemoteSnapshot(snapshot: remoteSnapshot, etag: "\"v1\""))]
        )
        let coordinator = SyncCoordinator(dataStore: mac, transport: transport)
        await coordinator.syncNow()

        let synced = try XCTUnwrap(mac.items.first { $0.id == itemID })
        XCTAssertTrue(synced.isCompleted)
        XCTAssertNil(synced.deletedAt)
        XCTAssertEqual(mac.archivedItems.map(\.id), [itemID])
        XCTAssertTrue(mac.activeItems.isEmpty)
        XCTAssertEqual(try XCTUnwrap(transport.putSnapshots.first).items.first?.isCompleted, true)
        XCTAssertNil(try XCTUnwrap(transport.putSnapshots.first).items.first?.deletedAt)
    }

    func testPruneBeforeSyncCanLoseFresherRemoteCompletion() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let id = UUID()

        let mac = DataStore(inMemory: true, deviceID: "mac")
        mac.dataRetention = .oneWeek
        _ = try mac.shoppingStore.addItem(name: "Milk", tagIDs: [], createdAt: now.addingTimeInterval(-eightDays * 2), now: now.addingTimeInterval(-eightDays * 2))
        // Force known id by applying snapshot
        let oldCompleted = ItemSnapshot(
            id: id,
            name: "Milk",
            isCompleted: true,
            createdAt: now.addingTimeInterval(-eightDays * 2),
            completedAt: now.addingTimeInterval(-eightDays - 86_400),
            updatedAt: now.addingTimeInterval(-eightDays - 86_400),
            deletedAt: nil,
            sortOrder: 0,
            tagIDs: [],
            lastEditorDeviceID: "mac"
        )
        try mac.shoppingStore.applyCanonicalSnapshot(
            SyncSnapshot(generatedAt: now, items: [oldCompleted], tags: [])
        )
        mac.fetchData()

        let phoneCompletedAt = now.addingTimeInterval(-60)
        let phoneSnapshot = SyncSnapshot(
            generatedAt: now,
            items: [
                ItemSnapshot(
                    id: id,
                    name: "Milk",
                    isCompleted: true,
                    createdAt: now.addingTimeInterval(-eightDays * 2),
                    completedAt: phoneCompletedAt,
                    updatedAt: phoneCompletedAt,
                    deletedAt: nil,
                    sortOrder: 0,
                    tagIDs: [],
                    lastEditorDeviceID: "iphone"
                )
            ],
            tags: []
        )

        // Bug path: prune first creates a newer tombstone that beats the phone completion.
        _ = mac.pruneExpiredData(now: now)
        XCTAssertNotNil(mac.shoppingStore.item(id: id)?.deletedAt)

        let transport = FakeCoordinatorTransport(
            fetchResults: [.success(RemoteSnapshot(snapshot: phoneSnapshot, etag: "\"v2\""))]
        )
        let coordinator = SyncCoordinator(dataStore: mac, transport: transport)
        await coordinator.syncNow()

        let afterBug = try XCTUnwrap(transport.putSnapshots.first?.items.first)
        XCTAssertNotNil(afterBug.deletedAt, "Prune-before-sync should upload a tombstone")
    }

    func testSyncThenPruneKeepsFresherRemoteCompletion() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let id = UUID()

        let mac = DataStore(inMemory: true, deviceID: "mac")
        mac.dataRetention = .oneWeek
        let oldCompleted = ItemSnapshot(
            id: id,
            name: "Milk",
            isCompleted: true,
            createdAt: now.addingTimeInterval(-eightDays * 2),
            completedAt: now.addingTimeInterval(-eightDays - 86_400),
            updatedAt: now.addingTimeInterval(-eightDays - 86_400),
            deletedAt: nil,
            sortOrder: 0,
            tagIDs: [],
            lastEditorDeviceID: "mac"
        )
        try mac.shoppingStore.applyCanonicalSnapshot(
            SyncSnapshot(generatedAt: now, items: [oldCompleted], tags: [])
        )
        mac.fetchData()

        let phoneCompletedAt = now.addingTimeInterval(-60)
        let phoneSnapshot = SyncSnapshot(
            generatedAt: now,
            items: [
                ItemSnapshot(
                    id: id,
                    name: "Milk",
                    isCompleted: true,
                    createdAt: now.addingTimeInterval(-eightDays * 2),
                    completedAt: phoneCompletedAt,
                    updatedAt: phoneCompletedAt,
                    deletedAt: nil,
                    sortOrder: 0,
                    tagIDs: [],
                    lastEditorDeviceID: "iphone"
                )
            ],
            tags: []
        )

        let transport = FakeCoordinatorTransport(
            fetchResults: [.success(RemoteSnapshot(snapshot: phoneSnapshot, etag: "\"v2\""))]
        )
        let coordinator = SyncCoordinator(dataStore: mac, transport: transport)
        await coordinator.syncNow()
        _ = mac.pruneExpiredData(now: now)

        let kept = try XCTUnwrap(mac.items.first { $0.id == id })
        XCTAssertTrue(kept.isCompleted)
        XCTAssertNil(kept.deletedAt)
        XCTAssertEqual(mac.archivedItems.map(\.id), [id])
    }

    func testSyncPreservesItemsWithoutTags() async throws {
        let phone = DataStore(inMemory: true, deviceID: "iphone")
        phone.addItem(name: "NoTag Milk")
        phone.addTag(name: "Food")
        let food = try XCTUnwrap(phone.tags.first)
        phone.addItem(name: "Tagged Bread", tags: [food])

        let phoneSnapshot = try phone.shoppingStore.makeSnapshot()
        XCTAssertEqual(phoneSnapshot.items.filter { $0.tagIDs.isEmpty }.count, 1)
        XCTAssertEqual(phoneSnapshot.items.count, 2)

        let mac = DataStore(inMemory: true, deviceID: "mac")
        mac.addItem(name: "Mac Local")
        let transport = FakeCoordinatorTransport(
            fetchResults: [.success(RemoteSnapshot(snapshot: phoneSnapshot, etag: "\"v-notag\""))]
        )
        let coordinator = SyncCoordinator(dataStore: mac, transport: transport)
        await coordinator.syncNow()

        XCTAssertEqual(Set(mac.items.map(\.name)), ["NoTag Milk", "Tagged Bread", "Mac Local"])
        let noTag = try XCTUnwrap(mac.items.first { $0.name == "NoTag Milk" })
        XCTAssertTrue(noTag.tags.isEmpty)
        XCTAssertNil(noTag.deletedAt)

        let uploaded = try XCTUnwrap(transport.putSnapshots.first)
        XCTAssertEqual(uploaded.items.filter { $0.name == "NoTag Milk" }.count, 1)
        XCTAssertTrue(uploaded.items.first { $0.name == "NoTag Milk" }?.tagIDs.isEmpty == true)
    }

    func testApplyCanonicalKeepsUntaggedItemAcrossResync() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let untagged = try store.addItem(name: "Solo", tagIDs: [])
        let tag = try store.addTag(name: "A", colorHex: "#C53A32")
        let tagged = try store.addItem(name: "WithTag", tagIDs: [tag.id])

        let snap1 = try store.makeSnapshot()
        try store.applyCanonicalSnapshot(snap1)
        XCTAssertEqual(store.items.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [untagged.id, tagged.id].sorted { $0.uuidString < $1.uuidString })

        // Remote-looking snapshot that still includes the untagged item with empty tagIDs.
        let remote = SyncSnapshot(
            generatedAt: Date(),
            items: snap1.items,
            tags: snap1.tags
        )
        try store.apply(snapshot: remote)
        XCTAssertNotNil(store.item(id: untagged.id))
        XCTAssertTrue(store.item(id: untagged.id)?.tags.isEmpty == true)
        XCTAssertNil(store.item(id: untagged.id)?.deletedAt)
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
