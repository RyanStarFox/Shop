import XCTest
@testable import ShopCore

final class WatchSnapshotHandlerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)

    func testDuplicateMessageIsIdempotent() throws {
        let local = snapshot(items: [item(name: "Milk", updatedAt: t1, deviceID: "iphone")])
        let data = try encoded(local)
        let handler = WatchSnapshotHandler()

        let first = try handler.handleReceivedSnapshot(data, localSnapshot: local)
        let replayed = try handler.handleReceivedSnapshot(data, localSnapshot: first)

        XCTAssertEqual(first, local)
        XCTAssertEqual(replayed, first)
    }

    func testWatchNewerEditWins() throws {
        let id = UUID()
        let local = snapshot(items: [item(id: id, name: "Milk", updatedAt: t1, deviceID: "iphone")])
        let remote = snapshot(items: [item(id: id, name: "Oat milk", updatedAt: t2, deviceID: "watch")])

        let result = try WatchSnapshotHandler().handleReceivedSnapshot(
            encoded(remote),
            localSnapshot: local
        )

        XCTAssertEqual(result.items.first?.name, "Oat milk")
        XCTAssertEqual(result.items.first?.lastEditorDeviceID, "watch")
    }

    func testNewerIPhoneEditRemains() throws {
        let id = UUID()
        let local = snapshot(items: [item(id: id, name: "Oat milk", updatedAt: t2, deviceID: "iphone")])
        let remote = snapshot(items: [item(id: id, name: "Milk", updatedAt: t1, deviceID: "watch")])

        let result = try WatchSnapshotHandler().handleReceivedSnapshot(
            encoded(remote),
            localSnapshot: local
        )

        XCTAssertEqual(result.items.first?.name, "Oat milk")
        XCTAssertEqual(result.items.first?.lastEditorDeviceID, "iphone")
    }

    func testRemoteTombstonePropagates() throws {
        let id = UUID()
        let local = snapshot(items: [item(id: id, name: "Milk", updatedAt: t1, deviceID: "iphone")])
        let remote = snapshot(
            items: [item(id: id, name: "Milk", updatedAt: t2, deletedAt: t2, deviceID: "watch")]
        )

        let result = try WatchSnapshotHandler().handleReceivedSnapshot(
            encoded(remote),
            localSnapshot: local
        )

        XCTAssertEqual(result.items.first?.deletedAt, t2)
    }

    func testInvalidSnapshotThrowsObservableError() {
        XCTAssertThrowsError(
            try WatchSnapshotHandler().handleReceivedSnapshot(
                Data("not json".utf8),
                localSnapshot: snapshot()
            )
        ) { error in
            XCTAssertEqual(error as? WatchSnapshotHandlerError, .invalidSnapshot)
        }
    }

    private func encoded(_ snapshot: SyncSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func snapshot(items: [ItemSnapshot] = []) -> SyncSnapshot {
        SyncSnapshot(
            version: SyncSnapshot.currentVersion,
            generatedAt: t2,
            items: items,
            tags: []
        )
    }

    private func item(
        id: UUID = UUID(),
        name: String,
        updatedAt: Date,
        deletedAt: Date? = nil,
        deviceID: String
    ) -> ItemSnapshot {
        ItemSnapshot(
            id: id,
            name: name,
            isCompleted: false,
            createdAt: t0,
            completedAt: nil,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortOrder: 0,
            tagIDs: [],
            lastEditorDeviceID: deviceID
        )
    }
}
