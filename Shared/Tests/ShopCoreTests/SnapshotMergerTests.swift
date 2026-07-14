import XCTest
@testable import ShopCore

@MainActor
final class SnapshotMergerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)

    func testMergeChoosesNewerLocalRecord() {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let result = SnapshotMerger().merge(
            local: snapshot(items: [item(id: id, name: "Local", updatedAt: t2)]),
            remote: snapshot(items: [item(id: id, name: "Remote", updatedAt: t1)])
        )

        XCTAssertEqual(result.items, [item(id: id, name: "Local", updatedAt: t2)])
    }

    func testMergeChoosesNewerRemoteRecord() {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let result = SnapshotMerger().merge(
            local: snapshot(items: [item(id: id, name: "Local", updatedAt: t1)]),
            remote: snapshot(items: [item(id: id, name: "Remote", updatedAt: t2)])
        )

        XCTAssertEqual(result.items, [item(id: id, name: "Remote", updatedAt: t2)])
    }

    func testMergeUsesDeviceIDAsStableTieBreakForEqualDates() {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let result = SnapshotMerger().merge(
            local: snapshot(items: [item(id: id, name: "iPhone", updatedAt: t1, deviceID: "iphone")]),
            remote: snapshot(items: [item(id: id, name: "Mac", updatedAt: t1, deviceID: "mac")])
        )

        XCTAssertEqual(result.items, [item(id: id, name: "Mac", updatedAt: t1, deviceID: "mac")])
    }

    func testNewerTombstonePreventsDeletedItemFromReviving() {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let result = SnapshotMerger().merge(
            local: snapshot(items: [item(id: id, name: "Milk", updatedAt: t0)]),
            remote: snapshot(items: [item(id: id, name: "Milk", updatedAt: t1, deletedAt: t1, deviceID: "mac")])
        )

        XCTAssertEqual(result.items.first?.deletedAt, t1)
    }

    func testMergeFiltersDeletedAndMissingTagIDsAfterMergingTags() {
        let liveTagID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let deletedTagID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let missingTagID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let result = SnapshotMerger().merge(
            local: snapshot(
                items: [item(id: itemID, name: "Milk", updatedAt: t2, tagIDs: [liveTagID, deletedTagID, missingTagID])],
                tags: [
                    tag(id: liveTagID, name: "Food", updatedAt: t1),
                    tag(id: deletedTagID, name: "Removed", updatedAt: t1)
                ]
            ),
            remote: snapshot(
                tags: [tag(id: deletedTagID, name: "Removed", updatedAt: t2, deletedAt: t2)]
            )
        )

        XCTAssertEqual(result.items.first?.tagIDs, [liveTagID])
    }

    func testMergeIsIdempotentAndIndependentOfArrayInputOrder() {
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let local = snapshot(items: [
            item(id: secondID, name: "Second", updatedAt: t1),
            item(id: firstID, name: "First", updatedAt: t1)
        ])
        let remote = snapshot(items: [
            item(id: firstID, name: "First updated", updatedAt: t2),
            item(id: secondID, name: "Second", updatedAt: t1)
        ])

        let merged = SnapshotMerger().merge(local: local, remote: remote)
        let replayed = SnapshotMerger().merge(local: merged, remote: merged)
        let reversed = SnapshotMerger().merge(
            local: snapshot(items: local.items.reversed()),
            remote: snapshot(items: remote.items.reversed())
        )

        XCTAssertEqual(merged, replayed)
        XCTAssertEqual(merged, reversed)
        XCTAssertEqual(merged.items.map(\.id), [firstID, secondID])
    }

    func testUnversionedSnapshotDecodesAsLegacyRecords() throws {
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let tagID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let json = """
        {
          "items": [{
            "id": "\(itemID.uuidString)",
            "name": "Milk",
            "isCompleted": false,
            "createdAt": 1000,
            "sortOrder": 0,
            "tagIDs": ["\(tagID.uuidString)"]
          }],
          "tags": [{
            "id": "\(tagID.uuidString)",
            "name": "Food",
            "colorHex": "#007AFF",
            "createdAt": 1000
          }]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let snapshot = try decoder.decode(SyncSnapshot.self, from: json)

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.items.first?.updatedAt, t0)
        XCTAssertNil(snapshot.items.first?.deletedAt)
        XCTAssertEqual(snapshot.items.first?.lastEditorDeviceID, "legacy")
        XCTAssertEqual(snapshot.tags.first?.updatedAt, t0)
        XCTAssertNil(snapshot.tags.first?.deletedAt)
        XCTAssertEqual(snapshot.tags.first?.lastEditorDeviceID, "legacy")
    }

    func testStoreAppliesSnapshotByUpsertingCanonicalModelsAndExportsTombstones() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "local")
        let tagID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let original = snapshot(
            items: [item(id: itemID, name: "Milk", updatedAt: t1, tagIDs: [tagID], deviceID: "iphone")],
            tags: [tag(id: tagID, name: "Food", updatedAt: t1, deviceID: "iphone")]
        )
        let updated = snapshot(
            items: [item(id: itemID, name: "Oat milk", updatedAt: t2, tagIDs: [tagID], deviceID: "mac")],
            tags: [tag(id: tagID, name: "Pantry", updatedAt: t2, deletedAt: t2, deviceID: "mac")]
        )

        try store.apply(snapshot: original)
        let canonicalItem = try XCTUnwrap(store.item(id: itemID))
        let canonicalTag = try XCTUnwrap(store.tag(id: tagID))
        try store.apply(snapshot: updated)
        let exported = try store.makeSnapshot(now: t2)

        XCTAssertTrue(canonicalItem === store.item(id: itemID))
        XCTAssertTrue(canonicalTag === store.tag(id: tagID))
        XCTAssertEqual(store.allItems.count, 1)
        XCTAssertEqual(store.allTags.count, 1)
        XCTAssertEqual(store.item(id: itemID)?.name, "Oat milk")
        XCTAssertTrue(store.item(id: itemID)?.tags.isEmpty ?? false)
        XCTAssertEqual(exported.items.first?.lastEditorDeviceID, "mac")
        XCTAssertEqual(exported.tags.first?.deletedAt, t2)
        XCTAssertEqual(exported.items.first?.tagIDs, [])
    }

    private func snapshot(
        items: [ItemSnapshot] = [],
        tags: [TagSnapshot] = []
    ) -> SyncSnapshot {
        SyncSnapshot(version: 2, generatedAt: t2, items: items, tags: tags)
    }

    private func item(
        id: UUID,
        name: String,
        updatedAt: Date,
        deletedAt: Date? = nil,
        tagIDs: [UUID] = [],
        deviceID: String = "iphone"
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
            tagIDs: tagIDs,
            lastEditorDeviceID: deviceID
        )
    }

    private func tag(
        id: UUID,
        name: String,
        updatedAt: Date,
        deletedAt: Date? = nil,
        deviceID: String = "iphone"
    ) -> TagSnapshot {
        TagSnapshot(
            id: id,
            name: name,
            colorHex: "#007AFF",
            createdAt: t0,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastEditorDeviceID: deviceID
        )
    }
}
