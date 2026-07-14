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

    func testShopHexColorValidation() {
        XCTAssertNotNil(Color(shopHex: "#34C759"))
        XCTAssertNil(Color(shopHex: "invalid"))
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
}
