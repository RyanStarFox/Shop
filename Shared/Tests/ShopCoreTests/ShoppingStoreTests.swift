import XCTest
import SwiftData
@testable import ShopCore

@MainActor
final class ShoppingStoreTests: XCTestCase {
    func testCompletingItemAdvancesVersionAndMovesItToArchive() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Milk", tagIDs: [])
        let oldVersion = item.updatedAt

        try store.setCompleted(
            itemID: item.id,
            completed: true,
            now: oldVersion.addingTimeInterval(1)
        )

        XCTAssertTrue(try XCTUnwrap(store.item(id: item.id)).isCompleted)
        XCTAssertEqual(store.activeItems.count, 0)
        XCTAssertEqual(store.archivedItems.map(\.id), [item.id])
        XCTAssertGreaterThan(try XCTUnwrap(store.item(id: item.id)).updatedAt, oldVersion)
        XCTAssertEqual(store.item(id: item.id)?.lastEditorDeviceID, "iphone")
    }

    func testDeletingTagUnlinksItemsAndCreatesTagTombstone() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let tag = try store.addTag(name: "Food", colorHex: "#2F7D63")
        let item = try store.addItem(name: "Milk", tagIDs: [tag.id])
        let deletionDate = Date()

        try store.deleteTag(id: tag.id, now: deletionDate)

        XCTAssertEqual(store.tag(id: tag.id)?.deletedAt, deletionDate)
        XCTAssertTrue(try XCTUnwrap(store.item(id: item.id)).tags.isEmpty)
        XCTAssertFalse(store.tags.contains { $0.id == tag.id })
    }

    func testSoftDeletedItemsAreExcludedFromActiveAndArchivedQueries() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "watch")
        let active = try store.addItem(name: "Milk", tagIDs: [])
        let archived = try store.addItem(name: "Bread", tagIDs: [])
        try store.setCompleted(itemID: archived.id, completed: true, now: Date())

        try store.softDeleteItem(itemID: active.id, now: Date())
        try store.softDeleteItem(itemID: archived.id, now: Date())

        XCTAssertTrue(store.activeItems.isEmpty)
        XCTAssertTrue(store.archivedItems.isEmpty)
        XCTAssertNotNil(store.item(id: active.id)?.deletedAt)
        XCTAssertNotNil(store.item(id: archived.id)?.deletedAt)
    }

    func testRestoringItemClearsTombstoneAndAdvancesVersion() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Milk", tagIDs: [])
        let deletedAt = item.updatedAt.addingTimeInterval(1)
        let restoredAt = deletedAt.addingTimeInterval(1)
        try store.softDeleteItem(itemID: item.id, now: deletedAt)

        try store.restoreItem(itemID: item.id, now: restoredAt)

        let restored = try XCTUnwrap(store.item(id: item.id))
        XCTAssertNil(restored.deletedAt)
        XCTAssertEqual(restored.updatedAt, restoredAt)
        XCTAssertEqual(store.activeItems.map(\.id), [item.id])
    }

    func testUpdatingItemChangesFieldsAndVersionMetadata() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let food = try store.addTag(name: "Food", colorHex: "#2F7D63")
        let item = try store.addItem(name: "Milk", tagIDs: [])
        let updateDate = item.updatedAt.addingTimeInterval(1)

        try store.updateItem(
            itemID: item.id,
            name: "Oat milk",
            tagIDs: [food.id],
            now: updateDate
        )

        let updated = try XCTUnwrap(store.item(id: item.id))
        XCTAssertEqual(updated.name, "Oat milk")
        XCTAssertEqual(updated.tags.map(\.id), [food.id])
        XCTAssertEqual(updated.updatedAt, updateDate)
        XCTAssertEqual(updated.lastEditorDeviceID, "mac")
    }

    func testMissingItemThrowsTypedError() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let missingID = UUID()

        XCTAssertThrowsError(
            try store.softDeleteItem(itemID: missingID, now: Date())
        ) { error in
            XCTAssertEqual(error as? ShoppingStoreError, .itemNotFound(missingID))
        }
    }

    func testApplyingSnapshotPersistsImportedRecordsInOneOperation() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let tagID = UUID()
        let itemID = UUID()
        let createdAt = Date(timeIntervalSince1970: 123)
        let snapshot = ExportData(
            items: [
                ExportItem(
                    id: itemID,
                    name: "Milk",
                    isCompleted: false,
                    createdAt: createdAt,
                    completedAt: nil,
                    sortOrder: 0,
                    tagIds: [tagID],
                    updatedAt: createdAt,
                    deletedAt: nil,
                    lastEditorDeviceID: "iphone"
                )
            ],
            tags: [
                ExportTag(
                    id: tagID,
                    name: "Food",
                    colorHex: "#2F7D63",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    lastEditorDeviceID: "iphone"
                )
            ]
        )

        try store.apply(snapshot: snapshot)

        XCTAssertEqual(store.item(id: itemID)?.tags.map(\.id), [tagID])
        XCTAssertEqual(store.item(id: itemID)?.lastEditorDeviceID, "iphone")
        XCTAssertEqual(store.tag(id: tagID)?.lastEditorDeviceID, "iphone")
    }

    func testModelDefaultsDeriveVersionFromCreationDate() {
        let creationDate = Date(timeIntervalSince1970: 123)

        let item = ShoppingItem(name: "Milk", createdAt: creationDate)
        let tag = Tag(name: "Food", createdAt: creationDate)

        XCTAssertEqual(item.updatedAt, creationDate)
        XCTAssertNil(item.deletedAt)
        XCTAssertEqual(item.lastEditorDeviceID, "")
        XCTAssertEqual(tag.updatedAt, creationDate)
        XCTAssertNil(tag.deletedAt)
        XCTAssertEqual(tag.lastEditorDeviceID, "")
    }

    func testOpeningDiskStoreBackfillsLegacyVersionSentinelsOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("shop.store")
        let itemID = UUID()
        let tagID = UUID()
        let itemCreatedAt = Date(timeIntervalSince1970: 100)
        let tagCreatedAt = Date(timeIntervalSince1970: 200)

        try seedLegacySentinelRecords(
            storeURL: storeURL,
            itemID: itemID,
            itemCreatedAt: itemCreatedAt,
            tagID: tagID,
            tagCreatedAt: tagCreatedAt
        )

        do {
            let store = try ShoppingStore(
                deviceID: "migration-device",
                storeURL: storeURL
            )
            XCTAssertEqual(store.item(id: itemID)?.updatedAt, itemCreatedAt)
            XCTAssertEqual(store.item(id: itemID)?.lastEditorDeviceID, "migration-device")
            XCTAssertEqual(store.tag(id: tagID)?.updatedAt, tagCreatedAt)
            XCTAssertEqual(store.tag(id: tagID)?.lastEditorDeviceID, "migration-device")
        }

        let reopened = try ShoppingStore(
            deviceID: "different-device",
            storeURL: storeURL
        )
        XCTAssertEqual(reopened.item(id: itemID)?.updatedAt, itemCreatedAt)
        XCTAssertEqual(reopened.item(id: itemID)?.lastEditorDeviceID, "migration-device")
        XCTAssertEqual(reopened.tag(id: tagID)?.updatedAt, tagCreatedAt)
        XCTAssertEqual(reopened.tag(id: tagID)?.lastEditorDeviceID, "migration-device")
    }

    func testShoppingStoreErrorsUseLocalizedFormattingEntryPoints() {
        let detail = "disk full"

        XCTAssertEqual(
            ShoppingStoreError.saveFailed(detail).errorDescription,
            ShopStrings.shoppingStoreSaveFailed(detail)
        )
        XCTAssertTrue(ShopStrings.shoppingStoreSaveFailed(detail).contains(detail))
        XCTAssertTrue(
            ShopStrings.shoppingStoreSaveFailed(detail, language: "en")
                .contains("Unable to save shopping data")
        )
        XCTAssertTrue(
            ShopStrings.shoppingStoreSaveFailed(detail, language: "zh-Hans")
                .contains("保存购物数据失败")
        )
    }

    private func seedLegacySentinelRecords(
        storeURL: URL,
        itemID: UUID,
        itemCreatedAt: Date,
        tagID: UUID,
        tagCreatedAt: Date
    ) throws {
        let schema = Schema([ShoppingItem.self, Tag.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        context.insert(
            ShoppingItem(
                id: itemID,
                name: "Legacy item",
                createdAt: itemCreatedAt,
                updatedAt: Date(timeIntervalSince1970: 0),
                lastEditorDeviceID: ""
            )
        )
        context.insert(
            Tag(
                id: tagID,
                name: "Legacy tag",
                createdAt: tagCreatedAt,
                updatedAt: Date(timeIntervalSince1970: 0),
                lastEditorDeviceID: ""
            )
        )
        try context.save()
    }
}
