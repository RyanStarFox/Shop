import XCTest
import SwiftUI
@testable import ShopCore

@MainActor
final class DataStoreTests: XCTestCase {
    lazy var dataStore = DataStore(inMemory: true)

    // MARK: - Item tests

    func testAddItem() {
        dataStore.addItem(name: "Milk")
        XCTAssertEqual(dataStore.items.count, 1)
        XCTAssertEqual(dataStore.items.first?.name, "Milk")
    }

    func testAddItemWithCustomCreatedAt() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        dataStore.addItem(name: "Milk", createdAt: stamp)
        XCTAssertEqual(dataStore.items.first?.createdAt, stamp)
    }

    func testToggleItem() {
        dataStore.addItem(name: "Bread")
        let item = dataStore.items.first!
        XCTAssertFalse(item.isCompleted)

        dataStore.toggleItem(item)
        XCTAssertTrue(item.isCompleted)
        XCTAssertNotNil(item.completedAt)
    }

    func testDeleteItem() {
        dataStore.addItem(name: "Eggs")
        XCTAssertEqual(dataStore.items.count, 1)

        dataStore.deleteItem(dataStore.items.first!)
        XCTAssertEqual(dataStore.items.count, 0)
    }

    func testFailedCompletionDoesNotPresentUndo() {
        let missing = ShoppingItem(name: "Ghost")
        var presented = 0

        dataStore.setCompleted(missing, completed: true) { _ in
            presented += 1
        }

        XCTAssertEqual(presented, 0)
        XCTAssertEqual(dataStore.lastError, .itemNotFound(missing.id))
    }

    func testFilterActive() {
        dataStore.addItem(name: "Item 1")
        dataStore.addItem(name: "Item 2")
        dataStore.toggleItem(dataStore.items.first!)

        dataStore.selectedFilter = .active
        XCTAssertEqual(dataStore.filteredItems.count, 1)
        XCTAssertEqual(dataStore.filteredItems.first?.name, "Item 2")
    }

    func testFilterCompleted() {
        dataStore.addItem(name: "Item 1")
        dataStore.addItem(name: "Item 2")
        dataStore.toggleItem(dataStore.items.first!)

        dataStore.selectedFilter = .completed
        XCTAssertEqual(dataStore.filteredItems.count, 1)
        XCTAssertEqual(dataStore.filteredItems.first?.name, "Item 1")
    }

    func testMoveItemsDoesNotReorderFullCollectionWhileFiltered() {
        dataStore.addTag(name: "Selected")
        let tag = dataStore.tags.first!
        dataStore.addItem(name: "First", tags: [tag])
        dataStore.addItem(name: "Second")
        dataStore.addItem(name: "Third", tags: [tag])
        let originalOrders = Dictionary(
            uniqueKeysWithValues: dataStore.items.map { ($0.id, $0.sortOrder) }
        )
        dataStore.selectedFilter = .active
        dataStore.selectedTags = [tag.id]

        dataStore.moveItems(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: dataStore.items.map { ($0.id, $0.sortOrder) }),
            originalOrders
        )
    }

    // MARK: - Tag tests

    func testAddTag() {
        dataStore.addTag(name: "Groceries", colorHex: "#34C759")
        XCTAssertEqual(dataStore.tags.count, 1)
        XCTAssertEqual(dataStore.tags.first?.name, "Groceries")
    }

    func testTagFiltering() {
        dataStore.addTag(name: "Urgent", colorHex: "#FF3B30")
        let tag = dataStore.tags.first!

        dataStore.addItem(name: "Important task", tags: [tag])
        dataStore.addItem(name: "Casual task")

        dataStore.selectedTags = [tag.id]
        XCTAssertEqual(dataStore.filteredItems.count, 1)
        XCTAssertEqual(dataStore.filteredItems.first?.name, "Important task")
    }

    func testEmptySelectedTagsMeansAllTags() {
        dataStore.addTag(name: "Food", colorHex: "#34C759")
        let tag = dataStore.tags.first!
        dataStore.addItem(name: "Milk", tags: [tag])
        dataStore.addItem(name: "No tag item")

        dataStore.selectedTags = []
        XCTAssertEqual(dataStore.filteredItems.count, 2)

        dataStore.selectedTags = [tag.id]
        XCTAssertEqual(dataStore.filteredItems.map(\.name), ["Milk"])
    }

    func testTagMatchModeAnyIsOR() {
        dataStore.addTag(name: "A", colorHex: "#007AFF")
        dataStore.addTag(name: "B", colorHex: "#34C759")
        let a = dataStore.tags.first { $0.name == "A" }!
        let b = dataStore.tags.first { $0.name == "B" }!
        dataStore.addItem(name: "Only A", tags: [a])
        dataStore.addItem(name: "Only B", tags: [b])
        dataStore.addItem(name: "Both", tags: [a, b])

        dataStore.selectedTags = [a.id, b.id]
        dataStore.tagMatchMode = .any
        XCTAssertEqual(Set(dataStore.filteredItems.map(\.name)), ["Only A", "Only B", "Both"])
    }

    func testTagMatchModeAllIsAND() {
        dataStore.addTag(name: "A", colorHex: "#007AFF")
        dataStore.addTag(name: "B", colorHex: "#34C759")
        let a = dataStore.tags.first { $0.name == "A" }!
        let b = dataStore.tags.first { $0.name == "B" }!
        dataStore.addItem(name: "Only A", tags: [a])
        dataStore.addItem(name: "Only B", tags: [b])
        dataStore.addItem(name: "Both", tags: [a, b])

        dataStore.selectedTags = [a.id, b.id]
        dataStore.tagMatchMode = .all
        XCTAssertEqual(dataStore.filteredItems.map(\.name), ["Both"])
    }

    func testRestoredTagSelectionDropsDeletedTags() {
        let existingTag = Tag(name: "Existing")
        let deletedTagID = UUID()

        XCTAssertEqual(
            DataStore.validSelectedTagIDs(
                [existingTag.id, deletedTagID],
                availableTags: [existingTag]
            ),
            [existingTag.id]
        )
    }

    func testShopHexColorValidation() {
        XCTAssertNotNil(Color(shopHex: "#34C759"))
        XCTAssertNil(Color(shopHex: "invalid"))
    }

    func testShopHexColorNormalize() {
        XCTAssertEqual(ShopHexColor.normalize("#34C759"), "#34C759")
        XCTAssertEqual(ShopHexColor.normalize("34c759"), "#34C759")
        XCTAssertEqual(ShopHexColor.normalize("#F0A"), "#FF00AA")
        XCTAssertEqual(ShopHexColor.normalize("3C5"), "#33CC55")
        XCTAssertNil(ShopHexColor.normalize("invalid"))
        XCTAssertNil(ShopHexColor.normalize(""))
    }

    func testTagProvidesDisplayColor() {
        let tag = Tag(name: "Groceries", colorHex: "#34C759")

        _ = tag.displayColor
    }

    // MARK: - Export/Import tests

    func testExportImport() {
        dataStore.addTag(name: "Test", colorHex: "#007AFF")
        dataStore.addItem(name: "Export test")

        guard let data = dataStore.exportData() else {
            XCTFail("Export failed")
            return
        }

        let newStore = DataStore(inMemory: true)
        newStore.importData(data)

        XCTAssertEqual(newStore.items.count, 1)
        XCTAssertEqual(newStore.items.first?.name, "Export test")
        XCTAssertEqual(newStore.tags.count, 1)
    }

    func testExportDataEncodesCurrentSyncSnapshot() throws {
        dataStore.addItem(name: "Milk")

        let data = try XCTUnwrap(dataStore.exportData())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(SyncSnapshot.self, from: data)

        XCTAssertEqual(snapshot.version, SyncSnapshot.currentVersion)
        XCTAssertEqual(snapshot.items.first?.name, "Milk")
    }

    func testLocalMutationNotifiesAllObserversButRemoteImportDoesNotEcho() throws {
        var firstObserverCalls = 0
        var secondObserverCalls = 0
        dataStore.addLocalMutationObserver { firstObserverCalls += 1 }
        dataStore.addLocalMutationObserver { secondObserverCalls += 1 }

        dataStore.addItem(name: "Local")
        dataStore.importData(try encoded(snapshot(
            itemID: UUID(),
            name: "Remote",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deviceID: "watch"
        )))

        XCTAssertEqual(firstObserverCalls, 1)
        XCTAssertEqual(secondObserverCalls, 1)
    }

    func testRemovedLocalMutationObserverIsNotCalled() {
        var observerCalls = 0
        let observerID = dataStore.addLocalMutationObserver {
            observerCalls += 1
        }

        dataStore.removeLocalMutationObserver(observerID)
        dataStore.addItem(name: "Local")

        XCTAssertEqual(observerCalls, 0)
    }

    func testImportDataDoesNotReviveNewerLocalTombstone() throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let deletedAt = Date(timeIntervalSince1970: 3_000)
        try store.shoppingStore.apply(snapshot: snapshot(
            itemID: itemID,
            name: "Milk",
            updatedAt: createdAt,
            deviceID: "remote"
        ))
        try store.shoppingStore.softDeleteItem(itemID: itemID, now: deletedAt)

        store.importData(try encoded(snapshot(
            itemID: itemID,
            name: "Milk",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deviceID: "remote"
        )))

        XCTAssertEqual(store.shoppingStore.item(id: itemID)?.deletedAt, deletedAt)
        XCTAssertNil(store.lastError)
    }

    func testImportDataDoesNotOverwriteNewerLocalEdit() throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        try store.shoppingStore.apply(snapshot: snapshot(
            itemID: itemID,
            name: "Original",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deviceID: "remote"
        ))
        try store.shoppingStore.updateItem(
            itemID: itemID,
            name: "Local edit",
            now: Date(timeIntervalSince1970: 3_000)
        )

        store.importData(try encoded(snapshot(
            itemID: itemID,
            name: "Stale remote",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deviceID: "remote"
        )))

        XCTAssertEqual(store.shoppingStore.item(id: itemID)?.name, "Local edit")
        XCTAssertEqual(
            store.shoppingStore.item(id: itemID)?.updatedAt,
            Date(timeIntervalSince1970: 3_000)
        )
    }

    func testImportDataAppliesNewerRemoteEdit() throws {
        let store = DataStore(inMemory: true, deviceID: "local")
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        try store.shoppingStore.apply(snapshot: snapshot(
            itemID: itemID,
            name: "Local",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deviceID: "local"
        ))

        store.importData(try encoded(snapshot(
            itemID: itemID,
            name: "New remote",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deviceID: "remote"
        )))

        XCTAssertEqual(store.shoppingStore.item(id: itemID)?.name, "New remote")
        XCTAssertEqual(
            store.shoppingStore.item(id: itemID)?.updatedAt,
            Date(timeIntervalSince1970: 2_000)
        )
    }

    func testImportDataAcceptsUnversionedLegacyJSON() throws {
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let json = """
        {
          "items": [{
            "id": "\(itemID.uuidString)",
            "name": "Legacy milk",
            "isCompleted": false,
            "createdAt": "1970-01-01T00:16:40Z",
            "sortOrder": 0,
            "tagIds": []
          }],
          "tags": []
        }
        """.data(using: .utf8)!

        dataStore.importData(json)

        XCTAssertEqual(dataStore.items.first?.name, "Legacy milk")
        XCTAssertEqual(dataStore.items.first?.updatedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(dataStore.items.first?.lastEditorDeviceID, "legacy")
        XCTAssertNil(dataStore.lastError)
    }

    func testImportDataReportsDecodeFailure() {
        dataStore.importData(Data("not json".utf8))

        guard case .fetchFailed = dataStore.lastError else {
            return XCTFail("Expected typed decode failure")
        }
    }

    func testPublishWidgetSnapshotIncludesRecentlyCompletedAndTagIDs() {
        dataStore.addTag(name: "Dairy", colorHex: "#007AFF")
        let tag = dataStore.tags.first!
        dataStore.addItem(name: "Milk", tags: [tag])
        dataStore.addItem(name: "Bread")
        let milk = dataStore.activeItems.first { $0.name == "Milk" }!
        dataStore.toggleItem(milk)

        dataStore.publishWidgetSnapshot()
        let snapshot = WidgetSnapshotStore.load()

        XCTAssertEqual(snapshot.items.map(\.name), ["Bread"])
        XCTAssertEqual(snapshot.recentlyCompleted.map(\.name), ["Milk"])
        XCTAssertEqual(snapshot.recentlyCompleted.first?.tags.first?.id, tag.id)
        XCTAssertTrue(snapshot.availableTags.contains { $0.id == tag.id })
    }

    func testApplyPendingRestoreUncompletesItem() {
        dataStore.addItem(name: "Milk")
        let item = dataStore.items.first!
        dataStore.toggleItem(item)
        XCTAssertTrue(item.isCompleted)

        WidgetSnapshotStore.enqueuePendingRestore(item.id)
        dataStore.applyPendingWidgetMutations()

        XCTAssertFalse(dataStore.items.first { $0.id == item.id }!.isCompleted)
        XCTAssertTrue(WidgetSnapshotStore.loadPendingRestores().isEmpty)
    }

    private func snapshot(
        itemID: UUID,
        name: String,
        updatedAt: Date,
        deviceID: String
    ) -> SyncSnapshot {
        SyncSnapshot(
            version: SyncSnapshot.currentVersion,
            generatedAt: updatedAt,
            items: [
                ItemSnapshot(
                    id: itemID,
                    name: name,
                    isCompleted: false,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    completedAt: nil,
                    updatedAt: updatedAt,
                    deletedAt: nil,
                    sortOrder: 0,
                    tagIDs: [],
                    lastEditorDeviceID: deviceID
                )
            ],
            tags: []
        )
    }

    private func encoded(_ snapshot: SyncSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }
}
