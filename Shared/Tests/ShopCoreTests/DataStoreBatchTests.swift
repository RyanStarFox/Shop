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

    func testBatchCompletePresentsSingleUndoAndOneObserver() {
        let store = DataStore(inMemory: true)
        store.addItem(name: "A")
        store.addItem(name: "B")
        let ids = store.items.map(\.id)
        var undos = 0
        var observers = 0
        _ = store.addLocalMutationObserver { observers += 1 }
        observers = 0
        store.setCompleted(ids, completed: true) { _ in undos += 1 }
        XCTAssertEqual(undos, 1)
        XCTAssertEqual(observers, 1)
        XCTAssertEqual(store.activeItems.count, 0)
    }

    func testBatchDeleteUndoRestoresAll() throws {
        let store = DataStore(inMemory: true)
        store.addItem(name: "A")
        store.addItem(name: "B")
        let ids = store.items.map(\.id)
        let coordinator = UndoCoordinator(
            duration: 60,
            performMutation: { mutation in
                try store.performUndoMutation(mutation)
            }
        )
        store.deleteItems(ids, presentUndo: coordinator.present)
        XCTAssertTrue(store.items.isEmpty)
        try coordinator.undo()
        XCTAssertEqual(Set(store.items.map(\.name)), ["A", "B"])
    }

    func testBatchTagAddUndoRestoresMembership() throws {
        let store = DataStore(inMemory: true)
        store.addTag(name: "Food", colorHex: "#C53A32")
        let tag = store.tags.first!
        store.addItem(name: "A")
        store.addItem(name: "B")
        let ids = store.items.map(\.id)
        let coordinator = UndoCoordinator(
            duration: 60,
            performMutation: { mutation in
                try store.performUndoMutation(mutation)
            }
        )
        store.addTag(tag, toItemIDs: ids, presentUndo: coordinator.present)
        XCTAssertTrue(store.items.allSatisfy { $0.tags.contains(where: { $0.id == tag.id }) })
        try coordinator.undo()
        XCTAssertTrue(store.items.allSatisfy { !$0.tags.contains(where: { $0.id == tag.id }) })
    }
}

private extension Date {
    static let t0 = Date(timeIntervalSince1970: 1_000)
    static let t1 = Date(timeIntervalSince1970: 2_000)
    static let t2 = Date(timeIntervalSince1970: 3_000)
}
