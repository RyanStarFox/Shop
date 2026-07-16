import Foundation
import XCTest
@testable import ShopCore

@MainActor
final class DataStoreBatchTests: XCTestCase {
    func testBatchCompleteSkipsAlreadyCompletedAndUsesOneSaveTimestamp() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let a = try store.addItem(name: "A", tagIDs: [], now: .t0)
        let b = try store.addItem(name: "B", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: a.id, completed: true, now: .t1)
        let changed = try store.setCompleted(
            itemIDs: [a.id, b.id, UUID()],
            completed: true,
            now: .t2
        )
        XCTAssertEqual(changed, [b.id])
        XCTAssertEqual(store.item(id: b.id)?.completedAt, .t2)
        XCTAssertEqual(store.item(id: a.id)?.completedAt, .t1)
    }

    func testBatchRestoreClearsCompletedAt() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let a = try store.addItem(name: "A", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: a.id, completed: true, now: .t1)
        let changed = try store.setCompleted(itemIDs: [a.id], completed: false, now: .t2)
        XCTAssertEqual(changed, [a.id])
        XCTAssertFalse(try XCTUnwrap(store.item(id: a.id)).isCompleted)
        XCTAssertNil(store.item(id: a.id)?.completedAt)
    }

    func testBatchDeleteIsSoftDelete() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let a = try store.addItem(name: "A", tagIDs: [], now: .t0)
        let deleted = try store.softDeleteItems(itemIDs: [a.id], now: .t1)
        XCTAssertEqual(deleted, [a.id])
        XCTAssertTrue(store.activeItems.isEmpty)
        XCTAssertNotNil(store.item(id: a.id)?.deletedAt)
    }

    func testBatchAddAndRemoveTagTriStateSemantics() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let tag = try store.addTag(name: "Food", colorHex: "#C53A32", now: .t0)
        let a = try store.addItem(name: "A", tagIDs: [tag.id], now: .t0)
        let b = try store.addItem(name: "B", tagIDs: [], now: .t0)
        let added = try store.addTag(tagID: tag.id, toItemIDs: [a.id, b.id], now: .t1)
        XCTAssertEqual(added, [b.id])
        let removed = try store.removeTag(tagID: tag.id, fromItemIDs: [a.id, b.id], now: .t2)
        XCTAssertEqual(Set(removed), [a.id, b.id])
    }
}

private extension Date {
    static let t0 = Date(timeIntervalSince1970: 1_000)
    static let t1 = Date(timeIntervalSince1970: 2_000)
    static let t2 = Date(timeIntervalSince1970: 3_000)
}
