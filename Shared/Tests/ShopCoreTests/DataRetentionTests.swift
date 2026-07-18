import XCTest
@testable import ShopCore

@MainActor
final class DataRetentionTests: XCTestCase {
    func testForeverCutoffIsNil() {
        XCTAssertNil(DataRetentionPolicy.forever.cutoff(relativeTo: .t0))
        XCTAssertEqual(DataRetentionPolicy.default, .oneYear)
    }

    func testPruneSoftDeletesExpiredArchivesThenPurgesAgedTombstones() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let twoDays: TimeInterval = 2 * 24 * 60 * 60

        let completed = try store.addItem(
            name: "Old Milk",
            tagIDs: [],
            now: now.addingTimeInterval(-eightDays - 86_400)
        )
        try store.setCompleted(
            itemID: completed.id,
            completed: true,
            now: now.addingTimeInterval(-eightDays)
        )
        let recent = try store.addItem(
            name: "Fresh Bread",
            tagIDs: [],
            now: now.addingTimeInterval(-twoDays)
        )
        try store.setCompleted(
            itemID: recent.id,
            completed: true,
            now: now.addingTimeInterval(-twoDays / 2)
        )
        let active = try store.addItem(name: "Active Eggs", tagIDs: [], now: now)

        let deleted = try store.addItem(
            name: "Gone",
            tagIDs: [],
            now: now.addingTimeInterval(-eightDays - 86_400)
        )
        try store.softDeleteItem(itemID: deleted.id, now: now.addingTimeInterval(-eightDays))

        let first = try store.pruneExpiredData(retention: .oneWeek, now: now)
        XCTAssertEqual(first.softDeletedItemCount, 1)
        XCTAssertEqual(first.purgedItemCount, 1)
        XCTAssertNil(store.item(id: deleted.id))
        XCTAssertEqual(store.item(id: completed.id)?.deletedAt, now)
        XCTAssertNil(store.item(id: recent.id)?.deletedAt)
        XCTAssertEqual(store.activeItems.map(\.id), [active.id])

        let later = now.addingTimeInterval(eightDays)
        let second = try store.pruneExpiredData(retention: .oneWeek, now: later)
        XCTAssertEqual(second.purgedItemCount, 1)
        XCTAssertNil(store.item(id: completed.id))
    }

    func testForeverDoesNotPrune() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let item = try store.addItem(name: "Keep", tagIDs: [], now: now.addingTimeInterval(-1_000_000))
        try store.setCompleted(itemID: item.id, completed: true, now: now.addingTimeInterval(-900_000))
        try store.softDeleteItem(itemID: item.id, now: now.addingTimeInterval(-800_000))

        let result = try store.pruneExpiredData(retention: .forever, now: now)
        XCTAssertFalse(result.didChange)
        XCTAssertNotNil(store.item(id: item.id)?.deletedAt)
    }

    func testRecentlyCompletedOldCreatedItemIsNotPruned() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let item = try store.addItem(
            name: "Old then done",
            tagIDs: [],
            createdAt: now.addingTimeInterval(-eightDays * 3),
            now: now.addingTimeInterval(-60)
        )
        try store.setCompleted(itemID: item.id, completed: true, now: now.addingTimeInterval(-60))

        let result = try store.pruneExpiredData(retention: .oneWeek, now: now)
        XCTAssertEqual(result.softDeletedItemCount, 0)
        XCTAssertNil(store.item(id: item.id)?.deletedAt)
        XCTAssertTrue(store.item(id: item.id)?.isCompleted == true)
        XCTAssertEqual(store.archivedItems.map(\.id), [item.id])
    }

    func testPruneUsesCompletedAtNotCreatedAt() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let item = try store.addItem(
            name: "Created long ago",
            tagIDs: [],
            createdAt: now.addingTimeInterval(-eightDays * 5),
            now: now.addingTimeInterval(-eightDays * 5)
        )
        // Completed recently — must stay in archive even though createdAt is ancient.
        try store.setCompleted(itemID: item.id, completed: true, now: now.addingTimeInterval(-60))

        let result = try store.pruneExpiredData(retention: .oneWeek, now: now)
        XCTAssertEqual(result.softDeletedItemCount, 0)
        XCTAssertNil(store.item(id: item.id)?.deletedAt)
        XCTAssertEqual(store.archivedItems.map(\.id), [item.id])
    }

    func testPruneNeverTouchesActiveItems() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let item = try store.addItem(
            name: "Still to buy",
            tagIDs: [],
            createdAt: now.addingTimeInterval(-eightDays * 10),
            now: now.addingTimeInterval(-eightDays * 10)
        )

        let result = try store.pruneExpiredData(retention: .oneWeek, now: now)
        XCTAssertEqual(result.softDeletedItemCount, 0)
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(store.item(id: item.id)?.deletedAt)
        XCTAssertEqual(store.activeItems.map(\.id), [item.id])
    }
}

private extension Date {
    static let t0 = Date(timeIntervalSince1970: 0)
}
