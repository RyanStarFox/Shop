import XCTest
@testable import ShopCore

@MainActor
final class ItemSelectionTests: XCTestCase {
    func testVisualOrderFlattensGroupsThenArchive() {
        let sections = ItemListSections(
            activeIDs: [],
            archivedIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000003")!],
            activeGroups: [
                ItemListTagGroup(
                    id: "a",
                    title: "A",
                    itemIDs: [
                        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
                    ]
                )
            ]
        )
        XCTAssertEqual(
            ItemSelection.visualOrderedIDs(from: sections).map(\.uuidString),
            [
                "00000000-0000-0000-0000-000000000001",
                "00000000-0000-0000-0000-000000000002",
                "00000000-0000-0000-0000-000000000003"
            ]
        )
    }

    func testRangeIsInclusiveAndOrderIndependent() {
        let order = [UUID(), UUID(), UUID(), UUID()]
        XCTAssertEqual(ItemSelection.range(from: order[3], to: order[1], in: order), Array(order[1...3]))
        XCTAssertEqual(ItemSelection.range(from: order[1], to: order[3], in: order), Array(order[1...3]))
    }

    func testMissingEndpointYieldsEmptyRange() {
        let order = [UUID(), UUID()]
        XCTAssertTrue(ItemSelection.range(from: UUID(), to: order[0], in: order).isEmpty)
    }

    func testTagMembershipTriState() {
        let tag = UUID()
        let other = UUID()
        let items: [(UUID, Set<UUID>)] = [
            (UUID(), [other]),
            (UUID(), [tag, other]),
            (UUID(), [tag])
        ]
        XCTAssertEqual(ItemSelection.membership(of: tag, in: items), .some)
        XCTAssertEqual(ItemSelection.membership(of: other, in: Array(items.prefix(2))), .all)
        XCTAssertEqual(ItemSelection.membership(of: UUID(), in: items), .none)
    }

    func testPruneRemovesInvisibleIDs() {
        let keep = UUID()
        let drop = UUID()
        XCTAssertEqual(
            ItemSelection.prunedSelection([keep, drop], visibleIDs: [keep]),
            [keep]
        )
    }
}
