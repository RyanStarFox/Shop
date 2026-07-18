import XCTest
@testable import ShopCore

final class WidgetSnapshotStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetStore()
    }

    override func tearDown() {
        resetStore()
        super.tearDown()
    }

    func testDecodesLegacySnapshotWithoutNewFields() throws {
        let legacy = """
        {"items":[{"id":"\(UUID().uuidString)","name":"Milk","sortOrder":0}],"updatedAt":0}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(WidgetSnapshotStore.Snapshot.self, from: legacy)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertTrue(snapshot.recentlyCompleted.isEmpty)
        XCTAssertTrue(snapshot.availableTags.isEmpty)
    }

    func testPublishOrdersRecentlyCompletedAndCapsAt20() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var completed: [(id: UUID, name: String, sortOrder: Int, tags: [(id: UUID, name: String, colorHex: String)], completedAt: Date)] = []
        for index in 0..<25 {
            completed.append((
                id: UUID(),
                name: "Item \(index)",
                sortOrder: index,
                tags: [],
                completedAt: base.addingTimeInterval(TimeInterval(index))
            ))
        }

        WidgetSnapshotStore.publish(
            activeItems: [],
            recentlyCompleted: completed,
            availableTags: []
        )

        let snapshot = WidgetSnapshotStore.load()
        XCTAssertEqual(snapshot.recentlyCompleted.count, 20)
        XCTAssertEqual(snapshot.recentlyCompleted.first?.name, "Item 24")
        XCTAssertEqual(
            snapshot.recentlyCompleted.map(\.completedAt),
            snapshot.recentlyCompleted.map(\.completedAt).sorted { ($0 ?? .distantPast) > ($1 ?? .distantPast) }
        )
    }

    func testMarkCompleteMovesItemToRecentlyCompletedAndQueuesID() {
        let itemID = UUID()
        WidgetSnapshotStore.publish(
            activeItems: [(id: itemID, name: "Milk", sortOrder: 0, tags: [])],
            recentlyCompleted: [],
            availableTags: []
        )

        let didMark = WidgetSnapshotStore.markCompleteInSnapshot(itemID: itemID)
        let snapshot = WidgetSnapshotStore.load()

        XCTAssertTrue(didMark)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.recentlyCompleted.count, 1)
        XCTAssertEqual(snapshot.recentlyCompleted.first?.id, itemID)
        XCTAssertNotNil(snapshot.recentlyCompleted.first?.completedAt)
        XCTAssertEqual(WidgetSnapshotStore.loadPendingCompletions(), [itemID])
        XCTAssertTrue(WidgetSnapshotStore.loadNeedsSync())
    }

    func testRestoreMovesItemBackAndQueuesRestore() {
        let itemID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        WidgetSnapshotStore.publish(
            activeItems: [],
            recentlyCompleted: [(
                id: itemID,
                name: "Milk",
                sortOrder: 2,
                tags: [],
                completedAt: completedAt
            )],
            availableTags: []
        )

        let didRestore = WidgetSnapshotStore.restoreInSnapshot(itemID: itemID)
        let snapshot = WidgetSnapshotStore.load()

        XCTAssertTrue(didRestore)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.id, itemID)
        XCTAssertEqual(snapshot.items.first?.sortOrder, 2)
        XCTAssertTrue(snapshot.recentlyCompleted.isEmpty)
        XCTAssertEqual(WidgetSnapshotStore.loadPendingRestores(), [itemID])
        XCTAssertTrue(WidgetSnapshotStore.loadNeedsSync())
    }

    func testRepeatedMarkNeedsSyncStaysSingleFlag() {
        WidgetSnapshotStore.markNeedsSync()
        WidgetSnapshotStore.markNeedsSync()
        XCTAssertTrue(WidgetSnapshotStore.loadNeedsSync())
    }

    private func resetStore() {
        WidgetSnapshotStore.write(
            WidgetSnapshotStore.Snapshot(items: [], recentlyCompleted: [], availableTags: [], updatedAt: .distantPast)
        )
        WidgetSnapshotStore.clearPendingCompletions()
        WidgetSnapshotStore.clearPendingRestores()
        WidgetSnapshotStore.clearNeedsSync()
    }
}
