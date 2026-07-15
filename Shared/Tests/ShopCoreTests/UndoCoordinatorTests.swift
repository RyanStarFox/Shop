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
            duration: 60,
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
        XCTAssertNil(coordinator.currentAction)
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
            duration: 60,
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
            duration: 60,
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
            duration: 60,
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
            duration: 60,
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

    func testPresentReplacesExistingActionAndIgnoresStaleExpiry() async {
        let scheduler = UndoTestScheduler()
        let coordinator = UndoCoordinator(sleep: scheduler.sleep)
        let firstID = UUID()
        let secondID = UUID()

        coordinator.present(UndoAction(id: firstID, message: "First") {})
        let first = await scheduler.waitForNextSleeper()
        coordinator.present(UndoAction(id: secondID, message: "Second") {})
        let second = await scheduler.waitForNextSleeper(after: first)

        XCTAssertEqual(coordinator.currentAction?.id, secondID)

        await scheduler.advance(first)
        await Task.yield()
        XCTAssertEqual(coordinator.currentAction?.id, secondID)

        await scheduler.advance(second)
        await waitUntil { coordinator.currentAction == nil }
        XCTAssertNil(coordinator.currentAction)
    }

    func testDismissClearsActionBeforeExpiry() async {
        let scheduler = UndoTestScheduler()
        let coordinator = UndoCoordinator(sleep: scheduler.sleep)
        coordinator.present(UndoAction(message: "Temp") {})
        let sleeper = await scheduler.waitForNextSleeper()

        coordinator.dismiss()

        XCTAssertNil(coordinator.currentAction)
        await scheduler.advance(sleeper)
        await Task.yield()
        XCTAssertNil(coordinator.currentAction)
    }

    private func waitUntil(condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

private extension Date {
    static let t0 = Date(timeIntervalSince1970: 1_000)
    static let t1 = Date(timeIntervalSince1970: 2_000)
    static let t2 = Date(timeIntervalSince1970: 3_000)
    static let t3 = Date(timeIntervalSince1970: 4_000)
    static let t4 = Date(timeIntervalSince1970: 5_000)
}

private actor UndoTestScheduler {
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var latestRegisteredID: UUID?

    func sleep(_ interval: TimeInterval) async {
        let id = UUID()
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
            latestRegisteredID = id
        }
    }

    var sleeperCount: Int {
        continuations.count
    }

    func contains(_ id: UUID) -> Bool {
        continuations[id] != nil
    }

    func waitForNextSleeper(after previousID: UUID? = nil) async -> UUID {
        while latestRegisteredID == previousID
                || latestRegisteredID.flatMap({ continuations[$0] }) == nil {
            await Task.yield()
        }
        return latestRegisteredID!
    }

    func advance(_ id: UUID) {
        continuations.removeValue(forKey: id)?.resume()
    }
}
