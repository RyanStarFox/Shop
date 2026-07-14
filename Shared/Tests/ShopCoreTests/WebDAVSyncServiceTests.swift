import Foundation
import XCTest
@testable import ShopCore

@MainActor
final class WebDAVSyncServiceTests: XCTestCase {
    func testSyncNowFetchesMergesAndConditionallyUpdatesRemote() async throws {
        let localStore = DataStore(inMemory: true, deviceID: "local")
        localStore.addItem(name: "Local")
        let remoteStore = DataStore(inMemory: true, deviceID: "remote")
        remoteStore.addItem(name: "Remote")
        let remote = try remoteStore.shoppingStore.makeSnapshot()
        let transport = FakeWebDAVTransport(
            fetchedSnapshot: RemoteSnapshot(snapshot: remote, etag: "\"v4\"")
        )
        let now = Date(timeIntervalSince1970: 2_000)
        let service = WebDAVSyncService(transport: transport, now: { now })
        service.configure(with: localStore)

        await service.syncNow()

        XCTAssertEqual(transport.fetchCount, 1)
        XCTAssertEqual(transport.putPreconditions, [.etag("\"v4\"")])
        XCTAssertEqual(Set(transport.putSnapshots.singleValue.items.map(\.name)), ["Local", "Remote"])
        XCTAssertEqual(Set(localStore.items.map(\.name)), ["Local", "Remote"])
        XCTAssertEqual(service.lastSyncDate, now)
        XCTAssertFalse(service.isSyncing)
        XCTAssertNil(service.error)
    }

    func testSyncNowCreatesRemoteFileWhenFetchReturnsNotFound() async throws {
        let dataStore = DataStore(inMemory: true, deviceID: "local")
        dataStore.addItem(name: "Local")
        let transport = FakeWebDAVTransport(fetchedSnapshot: nil)
        let service = WebDAVSyncService(transport: transport)
        service.configure(with: dataStore)

        await service.syncNow()

        XCTAssertEqual(transport.fetchCount, 1)
        XCTAssertEqual(transport.putPreconditions, [.create])
        XCTAssertEqual(transport.putSnapshots.singleValue.items.map(\.name), ["Local"])
        XCTAssertNotNil(service.lastSyncDate)
    }

    func testSyncNowPublishesLocalizedRecoverableError() async {
        let dataStore = DataStore(inMemory: true)
        let transport = FakeWebDAVTransport(
            fetchedSnapshot: nil,
            putError: WebDAVError.preconditionFailed
        )
        let service = WebDAVSyncService(transport: transport)
        service.configure(with: dataStore)

        await service.syncNow()

        XCTAssertEqual(service.error, ShopStrings.webdavPreconditionFailed)
        XCTAssertNil(service.lastSyncDate)
        XCTAssertFalse(service.isSyncing)
        XCTAssertEqual(transport.putPreconditions, [.create, .create, .create])
    }
}

private final class FakeWebDAVTransport: WebDAVTransporting, @unchecked Sendable {
    private let fetchedSnapshot: RemoteSnapshot?
    private let fetchError: Error?
    private let putError: Error?

    private(set) var fetchCount = 0
    private(set) var putSnapshots: [SyncSnapshot] = []
    private(set) var putPreconditions: [WebDAVPrecondition] = []

    init(
        fetchedSnapshot: RemoteSnapshot?,
        fetchError: Error? = nil,
        putError: Error? = nil
    ) {
        self.fetchedSnapshot = fetchedSnapshot
        self.fetchError = fetchError
        self.putError = putError
    }

    func fetch() async throws -> RemoteSnapshot? {
        fetchCount += 1
        if let fetchError {
            throw fetchError
        }
        return fetchedSnapshot
    }

    func put(_ snapshot: SyncSnapshot, precondition: WebDAVPrecondition) async throws -> String? {
        putSnapshots.append(snapshot)
        putPreconditions.append(precondition)
        if let putError {
            throw putError
        }
        return "\"updated\""
    }
}

private extension Array {
    var singleValue: Element {
        precondition(count == 1)
        return self[0]
    }
}
