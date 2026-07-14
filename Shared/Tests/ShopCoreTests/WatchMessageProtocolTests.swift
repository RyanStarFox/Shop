import XCTest
@testable import ShopCore

final class WatchMessageProtocolTests: XCTestCase {
    func testRequestReplyCarriesApplicableSnapshotWithinBudget() throws {
        let itemID = UUID()
        let remote = snapshot(itemID: itemID, name: "Watch milk", updatedAt: 2_000)
        let local = snapshot(itemID: itemID, name: "iPhone milk", updatedAt: 1_000)
        let data = try encoded(remote)

        let reply = WatchMessageProtocol.makeSnapshotReply(
            data,
            safeByteLimit: data.count
        )
        let result = try WatchMessageProtocol.parseSnapshotReply(reply)

        guard case .snapshot(let replyData) = result else {
            return XCTFail("Expected an immediate snapshot reply")
        }
        let merged = try WatchSnapshotHandler().handleReceivedSnapshot(
            replyData,
            localSnapshot: local
        )
        XCTAssertEqual(merged.items.first?.name, "Watch milk")
    }

    func testOversizedRequestReplyIsExplicitlyDeferred() throws {
        let data = Data(repeating: 0xAB, count: 11)

        let reply = WatchMessageProtocol.makeSnapshotReply(
            data,
            safeByteLimit: 10
        )

        XCTAssertEqual(
            try WatchMessageProtocol.parseSnapshotReply(reply),
            .deferred
        )
    }

    func testMissingSnapshotIsNotAcceptedAsSuccessfulReply() {
        XCTAssertThrowsError(
            try WatchMessageProtocol.parseSnapshotReply(["status": "snapshot"])
        ) { error in
            XCTAssertEqual(error as? WatchMessageProtocolError, .invalidReply)
        }
    }

    private func encoded(_ snapshot: SyncSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func snapshot(
        itemID: UUID,
        name: String,
        updatedAt: TimeInterval
    ) -> SyncSnapshot {
        let date = Date(timeIntervalSince1970: updatedAt)
        return SyncSnapshot(
            generatedAt: date,
            items: [
                ItemSnapshot(
                    id: itemID,
                    name: name,
                    isCompleted: false,
                    createdAt: Date(timeIntervalSince1970: 500),
                    completedAt: nil,
                    updatedAt: date,
                    deletedAt: nil,
                    sortOrder: 0,
                    tagIDs: [],
                    lastEditorDeviceID: name.hasPrefix("Watch") ? "watch" : "iphone"
                )
            ],
            tags: []
        )
    }
}
