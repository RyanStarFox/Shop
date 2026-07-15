import XCTest
@testable import ShopCore

@MainActor
final class ItemListLayoutTests: XCTestCase {
    func testSectionDerivationOrdersActiveBeforeArchiveHeaderBeforeArchived() {
        let active = makeItem(name: "Milk", completed: false, order: 0)
        let archivedA = makeItem(name: "Bread", completed: true, order: 1)
        let archivedB = makeItem(name: "Eggs", completed: true, order: 2)

        let sections = ItemListSections.derive(
            from: [active, archivedA, archivedB]
        )

        XCTAssertEqual(sections.activeIDs, [active.id])
        XCTAssertEqual(sections.archivedIDs, [archivedA.id, archivedB.id])
        XCTAssertEqual(
            sections.displayRows,
            [
                .activeItem(active.id),
                .archiveHeader,
                .archivedItem(archivedA.id),
                .archivedItem(archivedB.id),
            ]
        )
    }

    func testSectionDerivationOmitsArchiveHeaderWhenNoArchivedRows() {
        let first = makeItem(name: "Milk", completed: false, order: 0)
        let second = makeItem(name: "Bread", completed: false, order: 1)

        let sections = ItemListSections.derive(from: [first, second])

        XCTAssertEqual(sections.activeIDs, [first.id, second.id])
        XCTAssertTrue(sections.archivedIDs.isEmpty)
        XCTAssertFalse(sections.showsArchiveSection)
        XCTAssertEqual(
            sections.displayRows,
            [.activeItem(first.id), .activeItem(second.id)]
        )
    }

    func testSectionDerivationRespectsFilteredSubset() {
        let active = makeItem(name: "Milk", completed: false, order: 0)
        let archived = makeItem(name: "Bread", completed: true, order: 1)

        let sections = ItemListSections.derive(from: [archived])

        XCTAssertTrue(sections.activeIDs.isEmpty)
        XCTAssertEqual(sections.archivedIDs, [archived.id])
        XCTAssertEqual(
            sections.displayRows,
            [.archiveHeader, .archivedItem(archived.id)]
        )
        XCTAssertFalse(sections.displayRows.contains(.activeItem(active.id)))
    }

    func testFilteredMoveDoesNotChangeUnderlyingSortOrders() {
        let store = DataStore(inMemory: true)
        store.addTag(name: "Selected")
        let tag = store.tags.first!
        store.addItem(name: "First", tags: [tag])
        store.addItem(name: "Second")
        store.addItem(name: "Third", tags: [tag])
        let originalOrders = Dictionary(
            uniqueKeysWithValues: store.items.map { ($0.id, $0.sortOrder) }
        )

        store.selectedFilter = .active
        store.selectedTags = [tag.id]
        let filtered = store.filteredItems
        XCTAssertEqual(ItemListSections.derive(from: filtered).activeIDs.count, 2)

        store.moveItems(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0.sortOrder) }),
            originalOrders
        )
        XCTAssertFalse(
            ItemListReorderPolicy.canReorder(
                filter: store.selectedFilter,
                selectedTags: store.selectedTags,
                dateRange: store.dateRange,
                sortOption: store.sortOption
            )
        )
    }

    func testUnfilteredAllListAllowsActiveReorder() {
        let store = DataStore(inMemory: true)
        store.addItem(name: "First")
        store.addItem(name: "Second")
        store.addItem(name: "Third")
        store.selectedFilter = .all

        let before = store.activeItems.map(\.id)
        store.moveItems(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(store.activeItems.map(\.id), [before[1], before[0], before[2]])
    }

    func testReorderAllowedOnlyForUnfilteredActiveList() {
        XCTAssertTrue(
            ItemListReorderPolicy.canReorder(
                filter: .all,
                selectedTags: [],
                dateRange: nil
            )
        )
        XCTAssertTrue(
            ItemListReorderPolicy.canReorder(
                filter: .active,
                selectedTags: [],
                dateRange: nil
            )
        )
        XCTAssertFalse(
            ItemListReorderPolicy.canReorder(
                filter: .completed,
                selectedTags: [],
                dateRange: nil
            )
        )
        XCTAssertFalse(
            ItemListReorderPolicy.canReorder(
                filter: .all,
                selectedTags: [UUID()],
                dateRange: nil
            )
        )
        XCTAssertFalse(
            ItemListReorderPolicy.canReorder(
                filter: .all,
                selectedTags: [],
                dateRange: nil,
                searchIsActive: true
            )
        )
    }

    private func makeItem(
        name: String,
        completed: Bool,
        order: Int
    ) -> ShoppingItem {
        ShoppingItem(
            name: name,
            isCompleted: completed,
            createdAt: Date(timeIntervalSince1970: TimeInterval(order)),
            completedAt: completed ? Date(timeIntervalSince1970: TimeInterval(order)) : nil,
            sortOrder: order
        )
    }
}
