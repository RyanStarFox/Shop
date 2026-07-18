import Foundation
import XCTest
@testable import ShopCore

@MainActor
final class UndoCoordinatorTests: XCTestCase {
    func testUndoCompletingItemRestoresActiveStateWithLaterVersion() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Milk", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: item.id, completed: true, now: .t1)
        let completedVersion = try XCTUnwrap(store.item(id: item.id)).updatedAt

        var observerCalls = 0
        let coordinator = UndoCoordinator(
            performMutation: { mutation in
                try mutation()
                observerCalls += 1
            }
        )
        coordinator.present(
            ShoppingUndo.undoCompletion(
                itemID: item.id,
                previousIsCompleted: false,
                previousCompletedAt: nil,
                store: store,
                now: .t2
            )
        )

        try coordinator.undo()

        let restored = try XCTUnwrap(store.item(id: item.id))
        XCTAssertFalse(restored.isCompleted)
        XCTAssertNil(restored.completedAt)
        XCTAssertEqual(store.activeItems.map(\.id), [item.id])
        XCTAssertGreaterThan(restored.updatedAt, completedVersion)
        XCTAssertEqual(observerCalls, 1)
        XCTAssertFalse(coordinator.canUndo)
    }

    func testUndoRestoringCompletedItemReturnsToArchiveWithLaterVersion() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let item = try store.addItem(name: "Bread", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: item.id, completed: true, now: .t1)
        let completedAt = try XCTUnwrap(store.item(id: item.id)).completedAt
        try store.setCompleted(itemID: item.id, completed: false, now: .t2)
        let restoredVersion = try XCTUnwrap(store.item(id: item.id)).updatedAt

        var observerCalls = 0
        let coordinator = UndoCoordinator(
            performMutation: { mutation in
                try mutation()
                observerCalls += 1
            }
        )
        coordinator.present(
            ShoppingUndo.undoCompletion(
                itemID: item.id,
                previousIsCompleted: true,
                previousCompletedAt: completedAt,
                store: store,
                now: .t3
            )
        )

        try coordinator.undo()

        let archived = try XCTUnwrap(store.item(id: item.id))
        XCTAssertTrue(archived.isCompleted)
        XCTAssertEqual(archived.completedAt, completedAt)
        XCTAssertEqual(store.archivedItems.map(\.id), [item.id])
        XCTAssertGreaterThan(archived.updatedAt, restoredVersion)
        XCTAssertEqual(observerCalls, 1)
    }

    func testUndoDeletingItemRestoresTombstoneWithLaterVersion() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Eggs", tagIDs: [], now: .t0)
        try store.softDeleteItem(itemID: item.id, now: .t1)
        let deletedVersion = try XCTUnwrap(store.item(id: item.id)).updatedAt

        var observerCalls = 0
        let coordinator = UndoCoordinator(
            performMutation: { mutation in
                try mutation()
                observerCalls += 1
            }
        )
        coordinator.present(
            ShoppingUndo.undoItemDelete(
                itemID: item.id,
                store: store,
                now: .t2
            )
        )

        try coordinator.undo()

        let restored = try XCTUnwrap(store.item(id: item.id))
        XCTAssertNil(restored.deletedAt)
        XCTAssertEqual(store.activeItems.map(\.id), [item.id])
        XCTAssertGreaterThan(restored.updatedAt, deletedVersion)
        XCTAssertEqual(observerCalls, 1)
    }

    func testUndoDeletingTagRestoresTagAndLinksOnlyLiveItems() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let tag = try store.addTag(name: "Food", colorHex: "#2F7D63", now: .t0)
        let live = try store.addItem(name: "Milk", tagIDs: [tag.id], now: .t1)
        let deleted = try store.addItem(name: "Gone", tagIDs: [tag.id], now: .t1)
        try store.softDeleteItem(itemID: deleted.id, now: .t2)
        try store.deleteTag(id: tag.id, now: .t3)
        let tagDeletedVersion = try XCTUnwrap(store.tag(id: tag.id)).updatedAt

        var observerCalls = 0
        let coordinator = UndoCoordinator(
            performMutation: { mutation in
                try mutation()
                observerCalls += 1
            }
        )
        coordinator.present(
            ShoppingUndo.undoTagDelete(
                tagID: tag.id,
                linkedItemIDs: [live.id, deleted.id],
                store: store,
                now: .t4
            )
        )

        try coordinator.undo()

        let restoredTag = try XCTUnwrap(store.tag(id: tag.id))
        XCTAssertNil(restoredTag.deletedAt)
        XCTAssertGreaterThan(restoredTag.updatedAt, tagDeletedVersion)
        XCTAssertEqual(try XCTUnwrap(store.item(id: live.id)).tags.map(\.id), [tag.id])
        XCTAssertTrue(try XCTUnwrap(store.item(id: deleted.id)).tags.isEmpty)
        XCTAssertNotNil(try XCTUnwrap(store.item(id: deleted.id)).deletedAt)
        XCTAssertEqual(observerCalls, 1)
    }

    func testUndoKeepsActionWhenMutationFails() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Milk", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: item.id, completed: true, now: .t1)

        let missingID = UUID()
        let coordinator = UndoCoordinator(
            performMutation: { mutation in
                try mutation()
            }
        )
        coordinator.present(
            ShoppingUndo.undoCompletion(
                itemID: missingID,
                previousIsCompleted: false,
                previousCompletedAt: nil,
                store: store,
                now: .t2
            )
        )
        let actionID = try XCTUnwrap(coordinator.currentAction?.id)

        XCTAssertThrowsError(try coordinator.undo())

        XCTAssertEqual(coordinator.currentAction?.id, actionID)
        XCTAssertTrue(try XCTUnwrap(store.item(id: item.id)).isCompleted)
    }

    func testStackKeepsMultipleActionsAndUndoesInReverseOrder() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let first = try store.addItem(name: "Milk", tagIDs: [], now: .t0)
        let second = try store.addItem(name: "Bread", tagIDs: [], now: .t0)

        let coordinator = UndoCoordinator(
            performMutation: { mutation in try mutation() }
        )

        coordinator.present(UndoAction(message: "First") {
            try store.softDeleteItem(itemID: first.id, now: .t1)
        })
        coordinator.present(UndoAction(message: "Second") {
            try store.softDeleteItem(itemID: second.id, now: .t1)
        })

        XCTAssertEqual(coordinator.currentAction?.message, "Second")

        try coordinator.undo()
        XCTAssertNotNil(try store.item(id: second.id))
        XCTAssertEqual(coordinator.currentAction?.message, "First")

        try coordinator.undo()
        XCTAssertNotNil(try store.item(id: first.id))
        XCTAssertFalse(coordinator.canUndo)
    }

    func testStackTrimsOldestActionsWhenExceedingMaxHistory() throws {
        let coordinator = UndoCoordinator(maxHistoryCount: 2)

        coordinator.present(UndoAction(message: "One") {})
        coordinator.present(UndoAction(message: "Two") {})
        coordinator.present(UndoAction(message: "Three") {})

        XCTAssertEqual(coordinator.undoStack.map(\.message), ["Two", "Three"])
    }

    func testDismissRemovesMostRecentActionWithoutExecuting() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Milk", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: item.id, completed: true, now: .t1)

        let coordinator = UndoCoordinator()
        coordinator.present(UndoAction(message: "Temp") {
            try store.setCompleted(itemID: item.id, completed: false, now: .t2)
        })

        coordinator.dismiss()

        XCTAssertFalse(coordinator.canUndo)
        XCTAssertTrue(try XCTUnwrap(store.item(id: item.id)).isCompleted)
    }
}

private extension Date {
    static let t0 = Date(timeIntervalSince1970: 1_000)
    static let t1 = Date(timeIntervalSince1970: 2_000)
    static let t2 = Date(timeIntervalSince1970: 3_000)
    static let t3 = Date(timeIntervalSince1970: 4_000)
    static let t4 = Date(timeIntervalSince1970: 5_000)
}
